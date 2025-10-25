cmake_minimum_required(VERSION 3.20)
project(FIHardeningPass)

# Find LLVM
find_package(LLVM REQUIRED CONFIG)

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include LLVM directories and definitions
include_directories(${LLVM_INCLUDE_DIRS})
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
add_definitions(${LLVM_DEFINITIONS_LIST})

# Add LLVM's CMake module path
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")
include(AddLLVM)

# =============================================================================
# 1. Analysis Pass (Detection Only)
# =============================================================================
add_library(FIHardeningPass MODULE
  FIHardeningPass.cpp
)

set_target_properties(FIHardeningPass PROPERTIES
  COMPILE_FLAGS "-fno-rtti"
  PREFIX ""
)

message(STATUS "Building FIHardeningPass (analysis pass)")

# =============================================================================
# 2. Transformation Pass (IR Hardening)
# =============================================================================
add_library(FIHardeningTransform MODULE
  FIHardeningTransform.cpp
)

set_target_properties(FIHardeningTransform PROPERTIES
  COMPILE_FLAGS "-fno-rtti"
  PREFIX ""
)

message(STATUS "Building FIHardeningTransform (transformation pass)")

# =============================================================================
# 3. Runtime Verification Library
# =============================================================================
add_library(FIHardeningRuntime STATIC
  FIHardeningRuntime.cpp
)

# Runtime doesn't need LLVM, so no -fno-rtti required
set_target_properties(FIHardeningRuntime PROPERTIES
  OUTPUT_NAME "FIHardeningRuntime"
)

message(STATUS "Building FIHardeningRuntime (runtime verification library)")

# Ensure LLVM components are available (if needed for linking)
# llvm_map_components_to_libnames(llvm_libs core support passes)
# target_link_libraries(FIHardeningPass ${llvm_libs})
