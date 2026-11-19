# Reproducible build of the FIHarden plugin against LLVM from apt.llvm.org.
FROM ubuntu:24.04

ARG LLVM_VERSION=23
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y wget gnupg lsb-release software-properties-common \
        build-essential cmake ninja-build python3 python3-pip csmith libcsmith-dev && \
    wget -q https://apt.llvm.org/llvm.sh && \
    bash llvm.sh ${LLVM_VERSION} && \
    apt-get install -y llvm-${LLVM_VERSION}-dev llvm-${LLVM_VERSION}-tools \
        libclang-rt-${LLVM_VERSION}-dev && \
    rm -rf /var/lib/apt/lists/* llvm.sh && \
    # eval/fisim.py's modules, the versions docs/RESULTS.md used. Ubuntu's
    # python3-unicorn imports distutils, which Python 3.12 dropped.
    pip install --break-system-packages unicorn==2.1.2 capstone==6.0.0a11 pyelftools==0.33

ENV PATH="/usr/lib/llvm-${LLVM_VERSION}/bin:${PATH}"

WORKDIR /fihardening
COPY CMakeLists.txt ./
COPY lib/ lib/
COPY test/ test/
COPY runtime/ runtime/
COPY eval/ eval/

RUN cmake -S . -B build -G Ninja -DLLVM_DIR=/usr/lib/llvm-${LLVM_VERSION}/lib/cmake/llvm && \
    ninja -C build && \
    ninja -C build check-fi

CMD ["bash"]
