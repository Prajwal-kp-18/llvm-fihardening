# Dockerfile for FIHardeningTransform Reproducibility
# Builds plugin from source with LLVM 18
FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install LLVM 18 and dependencies
RUN apt-get update && \
    apt-get install -y wget gnupg software-properties-common lsb-release && \
    wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 18 && \
    apt-get update && \
    apt-get install -y \
        clang-18 \
        llvm-18 \
        llvm-18-dev \
        llvm-18-tools \
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

# Set up symbolic links for LLVM 18
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-18 100 && \
    update-alternatives --install /usr/bin/opt opt /usr/bin/opt-18 100 && \
    update-alternatives --install /usr/bin/llc llc /usr/bin/llc-18 100 && \
    update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-18 100

# Set environment variables
ENV LLVM_DIR=/usr/lib/llvm-18
ENV PATH="/usr/lib/llvm-18/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/lib/llvm-18/lib:${LD_LIBRARY_PATH}"

# Set up working directory
WORKDIR /fihardening

# Copy source files for building
COPY CMakeLists.txt ./
COPY FIHardeningPass.cpp ./
COPY FIHardeningTransform.cpp ./
COPY FIHardeningRuntime.cpp ./
COPY FIHardeningRuntime.h ./
COPY tests/ ./tests/
COPY scripts/run_tests.sh ./scripts/

# Build the plugin from source with LLVM 18
RUN mkdir -p build && \
    cd build && \
    cmake -DLLVM_DIR=/usr/lib/llvm-18/cmake .. && \
    make -j$(nproc) && \
    cd /fihardening && \
    ln -sf /fihardening/build/FIHardeningTransform.so /fihardening/FIHardeningTransform.so

# Create test results directory
RUN mkdir -p ./test_results

# Make scripts executable
RUN chmod +x ./scripts/run_tests.sh

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
    echo 'echo "Test Runner Usage Examples:"' >> /usr/local/bin/welcome && \
    echo 'echo "  # Run all tests (default)"' >> /usr/local/bin/welcome && \
    echo 'echo "  bash scripts/run_tests.sh"' >> /usr/local/bin/welcome && \
    echo 'echo "  # Run a specific test file"' >> /usr/local/bin/welcome && \
    echo 'echo "  bash scripts/run_tests.sh tests/test_comprehensive.c"' >> /usr/local/bin/welcome && \
    echo 'echo "  # Run multiple test files"' >> /usr/local/bin/welcome && \
    echo 'echo "  bash scripts/run_tests.sh tests/test1.c tests/test2.c"' >> /usr/local/bin/welcome && \
    echo 'echo "  # Run with full path"' >> /usr/local/bin/welcome && \
    echo 'echo "  bash scripts/run_tests.sh /path/to/my_test.c"' >> /usr/local/bin/welcome && \
    echo 'echo ""' >> /usr/local/bin/welcome && \
    echo 'echo "Test results and CFG images are saved in ./test_results/"' >> /usr/local/bin/welcome && \
    echo 'echo ""' >> /usr/local/bin/welcome && \
    chmod +x /usr/local/bin/welcome

CMD ["bash", "-c", "welcome && bash"]
