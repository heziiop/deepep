cmake_minimum_required(VERSION 3.20 FATAL_ERROR)
project(deep_ep LANGUAGES CXX)

option(DEEPEP_IS_A5_BUILD "build deep_ep for Ascend 950 (A5)" OFF)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RELEASE)
endif()

if(${CMAKE_BUILD_TYPE} MATCHES "RELEASE")
    add_compile_options(-O3)
    add_compile_options(-fvisibility=hidden -fvisibility-inlines-hidden)
    add_compile_options(-fstack-protector-strong)
    add_compile_options(-fPIC)
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
        "or pass -DASCEND_HOME_PATH=<cann-root>."
    )
endif()

set(PROJECT_BUILD_PATH ${PROJECT_SOURCE_DIR}/build)
set(PROJECT_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/output)

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

# Host-side pybind11 extension (deep_ep_cpp). The AscendC operator packages in
# ops/ and ops2/ are separate OPP projects and are built by build.sh before this
# project is configured.
add_subdirectory(csrc)
