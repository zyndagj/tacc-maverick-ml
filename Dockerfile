#Image: gzynda/tacc-maverick-ml
#Version: 0.0.2

FROM gzynda/tacc-maverick-cuda8:0.0.2

########################################
# Configure environment
########################################

# Add conda to path for all users
RUN sed -i 's~="~="/opt/conda/bin:~' /etc/environment \
    && echo 'LD_LIBRARY_PATH="/usr/local/cuda/lib64/stubs/:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64"' >> /etc/environment \
    && echo 'CONDA_DIR="/opt/conda"' >> /etc/environment \
    && echo 'XDG_RUNTIME_DIR=""' >> /etc/environment \
    && echo 'LANG="C.UTF-8"' >> /etc/environment \
    && echo 'LC_ALL="C.UTF-8"' >> /etc/environment

###################################################################
# Add entrypoint
###################################################################
# Add Tini
ARG TINI_VERSION=v0.17.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/local/bin/tini
RUN chmod a+rx /usr/local/bin/tini
ENTRYPOINT ["tini", "--"]
CMD ["bash"]

########################################
# Install miniconda
########################################

# Install dependencies
RUN apt-get update \
    && apt-get install -yq --no-install-recommends \
        unzip wget bzip2 ca-certificates git \
        libglib2.0-0 libxext6 libsm6 libxrender1 \
    && docker-clean

# Add conda env variables
ENV MINICONDA_VERSION=4.4.10 \
    CONDA_DIR=/opt/conda
ENV PATH=${CONDA_DIR}/bin:${PATH}
# Download and install miniconda
RUN mkdir $CONDA_DIR && chmod -R a+rX $CONDA_DIR \
    && wget --quiet https://repo.continuum.io/miniconda/Miniconda3-${MINICONDA_VERSION}-Linux-x86_64.sh \
    && bash Miniconda3-${MINICONDA_VERSION}-Linux-x86_64.sh -f -b -p $CONDA_DIR \
    && rm Miniconda3-${MINICONDA_VERSION}-Linux-x86_64.sh \
    && conda config --system --set auto_update_conda false \
    && conda config --system --set show_channel_urls true \
    && conda update -n base conda \
    && conda update --all --quiet --yes \
    && rm -rf ${CONDA_DIR}/pkgs/* \
    && docker-clean
# Activate conda on login
RUN ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh

########################################
# Install tensorflow
########################################

# Install python dependencies
RUN conda install --yes --no-update-deps \
        pillow \
        h5py \
        ipykernel \
        jupyter \
        matplotlib \
        mock \
        numpy \
        scipy \
        scikit-learn \
        pandas \
        cython \
    && python -m ipykernel.kernelspec \
    && docker-clean && rm -rf ${CONDA_DIR}/pkgs/*

##### Install bazel
# Running bazel inside a `docker build` command causes trouble, cf:
#   https://github.com/bazelbuild/bazel/issues/134
# The easiest solution is to set up a bazelrc file forcing --batch.
RUN echo "startup --batch" >>/etc/bazel.bazelrc
# Similarly, we need to workaround sandboxing issues:
#   https://github.com/bazelbuild/bazel/issues/418
RUN echo "build --spawn_strategy=standalone --genrule_strategy=standalone" >>/etc/bazel.bazelrc
# Install the most recent bazel release.
ENV BAZEL_VERSION 0.11.1
ARG BAZEL_DIR=/opt/bazel
ARG WEBSTR="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36"
RUN cd ${BAZEL_DIR} && \
    curl -H "${WEBSTR}" -fSsL -O https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/bazel-$BAZEL_VERSION-installer-linux-x86_64.sh && \
    curl -H "${WEBSTR}" -fSL -o ${BAZEL_DIR}/LICENSE.txt https://raw.githubusercontent.com/bazelbuild/bazel/master/LICENSE && \
    bash bazel-$BAZEL_VERSION-installer-linux-x86_64.sh && \
    cd / && rm -f ${BAZEL_DIR}/bazel-$BAZEL_VERSION-installer-linux-x86_64.sh

# Configure the build for our CUDA configuration.
ENV CI_BUILD_PYTHON=python \
    TF_NEED_CUDA=1 \
    TF_CUDA_COMPUTE_CAPABILITIES=3.0,3.5,5.2,6.0,6.1 \
    TF_CUDA_VERSION=8.0 \
    TF_CUDNN_VERSION=7

# Install TF
RUN git clone https://github.com/tensorflow/tensorflow.git && \
    cd tensorflow && git checkout v1.8.0 && \
    sed -i 's/^#if TF_HAS_.*$/#if !defined(__NVCC__)/g' tensorflow/core/platform/macros.h && \
    ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 && \
    ln -s /usr/local/cuda-8.0/nvvm/libdevice/libdevice.compute_50.10.bc /usr/local/cuda-8.0/nvvm/libdevice/libdevice.10.bc && \
    export LD_LIBRARY_PATH="/usr/local/cuda/lib64/stubs/:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:${LD_LIBRARY_PATH}" && \
    tensorflow/tools/ci_build/builds/configured GPU \
    bazel build -c opt --copt=-mavx --config=cuda \
	--cxxopt="-D_GLIBCXX_USE_CXX11_ABI=0" \
        --local_resources 6144,4.0,2.0 \
        tensorflow/tools/pip_package:build_pip_package && \
    bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/pip && \
    pip --no-cache-dir install /tmp/pip/tensorflow-*.whl && \
    cd / && rm -rf /tmp/pip /root/.cache /tensorflow && \
    docker-clean

########################################
# Install ML
########################################

# Install pytorch
RUN pip install torch torchvision \
    && docker-clean
# Install keras
RUN pip install keras \
    && docker-clean
# List packages
RUN conda list -n base
