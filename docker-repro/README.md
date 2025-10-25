# FIHardeningTransform Docker Reproducibility

This folder contains a Dockerfile and instructions to build a Docker image for reproducing the results of the FIHardeningTransform LLVM pass paper.

## Contents
- Prebuilt FIHardeningTransform and runtime binaries
- Comprehensive test suite (`test_comprehensive.c`)
- Test runner script (`run_tests.sh`)
- Precomputed results and IR artifacts (`test_results/`)
- Paper and documentation

## Usage

1. **Build the Docker image:**
   ```sh
   docker build -t fihardening-repro docker-repro/
   ```
2. **Run the container:**
   ```sh
   docker run -it fihardening-repro
   ```
3. **Reproduce results inside the container:**
   ```sh
   bash scripts/run_tests.sh
   # Results will appear in /fihardening/test_results
   ```

## Notes
- The image includes all dependencies (LLVM, Clang, Graphviz, etc.).
- The prebuilt pass and runtime are in `/fihardening/build/`.
- The test suite and scripts are in `/fihardening/tests/` and `/fihardening/scripts/`.
- The paper and documentation are included for reference.

For any issues, refer to the main project documentation or contact the authors.
