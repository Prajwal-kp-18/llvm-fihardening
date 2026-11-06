cmake_minimum_required(VERSION 3.20)
project(FIHarden CXX)

find_package(LLVM REQUIRED CONFIG)

# Not find_package(LLVM 23): LLVM's version check wants an exact major.minor match (23.1),
# which would also reject trunk.
if(LLVM_VERSION_MAJOR VERSION_LESS 23)
  message(FATAL_ERROR "LLVM ${LLVM_PACKAGE_VERSION} found; need 23+. Pass -DLLVM_DIR=/usr/lib/llvm-23/lib/cmake/llvm")
endif()
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION} in ${LLVM_DIR}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB FI_SOURCES CONFIGURE_DEPENDS lib/*.cpp)
add_library(FIHarden MODULE ${FI_SOURCES})
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
target_compile_definitions(FIHarden PRIVATE ${LLVM_DEFINITIONS_LIST})
target_include_directories(FIHarden SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS})
target_compile_options(FIHarden PRIVATE -fno-rtti)
set_target_properties(FIHarden PROPERTIES PREFIX "")

# Tests: ninja check-fi
find_program(LIT NAMES lit llvm-lit HINTS ${LLVM_TOOLS_BINARY_DIR})
if(LIT)
  configure_file(test/lit.site.cfg.py.in test/lit.site.cfg.py @ONLY)
  add_custom_target(check-fi COMMAND ${LIT} -sv ${CMAKE_BINARY_DIR}/test DEPENDS FIHarden USES_TERMINAL)
endif()
