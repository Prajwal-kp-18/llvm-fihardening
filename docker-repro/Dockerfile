# Dockerfile for FIHardeningTransform Reproducibility
# Builds plugin from source against LLVM (version set by LLVM_VERSION below)
FROM ubuntu:24.04

ARG LLVM_VERSION=23

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install LLVM and dependencies
RUN apt-get update && \
    apt-get install -y wget gnupg software-properties-common lsb-release && \
    wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh ${LLVM_VERSION} && \
    apt-get update && \
    apt-get install -y \
        clang-${LLVM_VERSION} \
        llvm-${LLVM_VERSION} \
        llvm-${LLVM_VERSION}-dev \
        llvm-${LLVM_VERSION}-tools \
        cmake \
        make \
        build-essential \
        git \
        python3 \
        python3-pip \
        graphviz \
        vim \
        less && \
    rm -rf /var/lib/apt/lists/* llvm.sh

# Unversioned tool names
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${LLVM_VERSION} 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${LLVM_VERSION} 100 && \
    update-alternatives --install /usr/bin/opt opt /usr/bin/opt-${LLVM_VERSION} 100 && \
    update-alternatives --install /usr/bin/llc llc /usr/bin/llc-${LLVM_VERSION} 100 && \
    update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-${LLVM_VERSION} 100

# Set environment variables
ENV LLVM_DIR=/usr/lib/llvm-${LLVM_VERSION}
ENV PATH="/usr/lib/llvm-${LLVM_VERSION}/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/lib/llvm-${LLVM_VERSION}/lib"

# Set up working directory
WORKDIR /fihardening

# Copy source files for building
COPY CMakeLists.txt ./
COPY lib/ ./lib/
COPY runtime/ ./runtime/

# Build the plugin from source
RUN mkdir -p build && \
    cd build && \
    cmake -DLLVM_DIR=${LLVM_DIR}/cmake .. && \
    make -j$(nproc) && \
    cd /fihardening && \
    ln -sf /fihardening/build/FIHardeningTransform.so /fihardening/FIHardeningTransform.so

# Create welcome message
RUN echo '#!/bin/bash' > /usr/local/bin/welcome && \
    echo 'echo "================================================"' >> /usr/local/bin/welcome && \
    echo 'echo "  FIHardening Docker Container"' >> /usr/local/bin/welcome && \
    echo 'echo "  FIHardeningTransform built from source"' >> /usr/local/bin/welcome && \
    echo 'echo "================================================"' >> /usr/local/bin/welcome && \
    echo 'echo ""' >> /usr/local/bin/welcome && \
    echo 'clang --version | head -n 1' >> /usr/local/bin/welcome && \
    echo 'echo ""' >> /usr/local/bin/welcome && \
    echo 'echo "Plugin built: FIHardeningTransform.so (from build/FIHardeningTransform.so)"' >> /usr/local/bin/welcome && \
    echo 'ls -lh build/FIHardeningTransform.so 2>/dev/null || echo "(not found)"' >> /usr/local/bin/welcome && \
    echo 'echo ""' >> /usr/local/bin/welcome && \
    chmod +x /usr/local/bin/welcome

CMD ["bash", "-c", "welcome && bash"]
