# Host-side C++/pybind11 extension (deep_ep_cpp).
# The AscendC operator packages live in ../ops (A3/A5) and ../ops2 (A2) and are
# separate CANN OPP projects built by build.sh, not by this CMake project.

cmake_minimum_required(VERSION 3.20 FATAL_ERROR)
project(deep_ep LANGUAGES CXX)

option(DEEPEP_IS_A5_BUILD "build deep_ep for Ascend 950 (A5)" OFF)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Repository root: csrc/runtime/../..
set(DEEPEP_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RELEASE)
endif()

# Mirrors the upstream top-level project so a standalone build uses exactly the
# same compiler flags for every DeepEP source file.
add_compile_options(-hno-unused-parameter -lno-unused-function -Wunused-value -Wcast-align)
add_compile_options(-Wcast-qual -Winvalid-pch -Wwrite-strings -Wsign-compare -Wextra)

if(${CMAKE_BUILD_TYPE} MATCHES "RELEASE")
    add_compile_options(-O3)
    add_compile_options(-fvisibility=hidden -fvisibility-inlines-hidden)
    add_compile_options(-fstack-protector-strong)
    add_compile_options(-Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -fPIE -fPIC -ftrapv -s)
    message(STATUS "build type set to RELEASE")
else()
    add_compile_options(-g -rdynamic)
endif()

if(DEFINED ENV{DEBUG_MODE})
    if("$ENV{DEBUG_MODE}" STREQUAL "ON")
        add_compile_definitions(DEBUG_MODE)
        message(STATUS "Debug logging enabled from environment")
    endif()
endif()

# ASCEND_HOME_PATH can come from build.sh (-DASCEND_HOME_PATH=...) or from the
# environment when CMake is invoked directly.
if(NOT DEFINED ASCEND_HOME_PATH AND DEFINED ENV{ASCEND_HOME_PATH})
    set(ASCEND_HOME_PATH "$ENV{ASCEND_HOME_PATH}" CACHE PATH "ASCEND CANN package installation directory" FORCE)
endif()
if(NOT DEFINED ASCEND_HOME_PATH OR NOT EXISTS "${ASCEND_HOME_PATH}")
    message(FATAL_ERROR
        "ASCEND_HOME_PATH is not set or does not exist: '${ASCEND_HOME_PATH}'.\n"
        "Source the CANN environment first (source /usr/local/Ascend/ascend-toolkit/set_env.sh) "
        "or pass -DASCEND_HOME_PATH=<cann-root>.")
endif()

set(PROJECT_BUILD_PATH ${PROJECT_BINARY_DIR})
set(PROJECT_OUTPUT_PATH ${DEEPEP_REPO_ROOT}/output)

include(cmake/config_git_last_commit.cmake)
include(cmake/config_envs.cmake)

find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    message(STATUS "Found ccache: ${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
else()
    message(STATUS "ccache not found, proceeding with normal compilation")
endif()

if(${CMAKE_SYSTEM_PROCESSOR} STREQUAL "x86_64")
    set(DEEPEP_ARCH "x86_64")
elseif(${CMAKE_SYSTEM_PROCESSOR} STREQUAL "aarch64")
    set(DEEPEP_ARCH "aarch64")
else()
    message(FATAL_ERROR "Unsupported host processor: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

set(TARGET_INSTALL_DIR ${CMAKE_INSTALL_PREFIX})
set(ASCEND_HOME_PATH ${ASCEND_HOME_PATH})

find_program(PYTHON_EXECUTABLE NAMES python3 python)
message(STATUS "PYTHON_EXECUTABLE:${PYTHON_EXECUTABLE}")

list(APPEND CMAKE_PREFIX_PATH ${PYBIND11_DIR})
find_package(pybind11 REQUIRED)
include(CheckCXXSourceCompiles)

message(STATUS "CMAKE_PREFIX_PATH = ${CMAKE_PREFIX_PATH}")

file(GLOB SOURCES_DEEPEP *.cpp)
list(APPEND SOURCES_DEEPEP
    profiling/core/profile_exporter.cpp
    profiling/core/profile_runtime.cpp
    profiling/core/profile_session.cpp
    profiling/adapters/fused_deep_moe_a5/fused_deep_moe_a5_profile_traits.cpp
    profiling/adapters/fused_deep_moe_a5/fused_deep_moe_a5_profile_adapter.cpp
)

pybind11_add_module(deep_ep_cpp pybind_extension.cpp ${SOURCES_DEEPEP})
set_target_properties(deep_ep_cpp PROPERTIES CXX_STANDARD 17)

# Define __DAV_C310__ for C310/A5 chip builds so that #ifdef __DAV_C310__ guards
# work in host/pybind compilation context (they only exist natively in AscendC device compilation)
# DEEPEP_IS_A5_BUILD is passed from build.sh when SOC_VERSION=Ascend950
if("${DEEPEP_IS_A5_BUILD}" STREQUAL "ON")
    target_compile_definitions(deep_ep_cpp PRIVATE __DAV_C310__)
endif()
target_include_directories( deep_ep_cpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    # Host profiling code includes shared protocol headers as
    # "ops/profiling/common/...", so csrc/ must be on the include path
    # (ops/ is now csrc/ops/ in this layout).
    ${DEEPEP_REPO_ROOT}/csrc

    ${TORCH_DIR}/include
    ${TORCH_DIR}/include/torch/csrc/api/include
    ${TORCH_NPU_DIR}/include
    ${TORCH_NPU_DIR}/include/third_party/acl/inc/acl
    ${TORCH_NPU_DIR}/include/third_party/acl/inc
    ${ASCEND_HOME_PATH}/include
    ${ASCEND_HOME_PATH}/${DEEPEP_ARCH}-linux/include/experiment/platform
)

set(CMAKE_REQUIRED_INCLUDES
    ${TORCH_NPU_DIR}/include
    ${TORCH_NPU_DIR}/include/third_party/acl/inc/acl
    ${TORCH_NPU_DIR}/include/third_party/acl/inc
    ${ASCEND_HOME_PATH}/include
)
set(_DEEPEP_OLD_TRY_COMPILE_TARGET_TYPE "${CMAKE_TRY_COMPILE_TARGET_TYPE}")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
check_cxx_source_compiles(
    "#include <acl/acl_rt.h>\nint main() { auto fn = &aclrtEventGetTimestamp; (void)fn; return 0; }\n"
    DEEPEP_HAS_ACLRT_EVENT_GET_TIMESTAMP)
if(DEFINED _DEEPEP_OLD_TRY_COMPILE_TARGET_TYPE AND NOT "${_DEEPEP_OLD_TRY_COMPILE_TARGET_TYPE}" STREQUAL "")
    set(CMAKE_TRY_COMPILE_TARGET_TYPE "${_DEEPEP_OLD_TRY_COMPILE_TARGET_TYPE}")
else()
    unset(CMAKE_TRY_COMPILE_TARGET_TYPE)
endif()
unset(_DEEPEP_OLD_TRY_COMPILE_TARGET_TYPE)
unset(CMAKE_REQUIRED_INCLUDES)

if(DEEPEP_HAS_ACLRT_EVENT_GET_TIMESTAMP)
    target_compile_definitions(deep_ep_cpp PRIVATE DEEPEP_HAS_ACLRT_EVENT_GET_TIMESTAMP=1)
    message(STATUS "deep_ep profiling timestamp alignment: enabled")
else()
    target_compile_definitions(deep_ep_cpp PRIVATE DEEPEP_HAS_ACLRT_EVENT_GET_TIMESTAMP=0)
    message(STATUS "deep_ep profiling timestamp alignment: disabled (profiling collection still enabled)")
endif()
target_link_directories(deep_ep_cpp PRIVATE
        ${TORCH_DIR}/lib
        ${TORCH_NPU_DIR}/lib
        ${ASCEND_HOME_PATH}/lib64
)
target_link_libraries(deep_ep_cpp PRIVATE
    torch_python
    ascendcl
    hccl
    torch_npu
    opapi
    nnopbase
)

message(STATUS "TARGET_INSTALL_DIR = ${TARGET_INSTALL_DIR}")
install(TARGETS deep_ep_cpp
    LIBRARY DESTINATION ${TARGET_INSTALL_DIR}/lib
    PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
)
