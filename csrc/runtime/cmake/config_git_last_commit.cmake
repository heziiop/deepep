find_program(GIT_EXECUTABLE NAMES git)

# When this project is configured from csrc/runtime, PROJECT_SOURCE_DIR points
# at csrc/runtime. Prefer DEEPEP_REPO_ROOT so GIT_LAST_COMMIT always reflects
# the repository commit, and keep PROJECT_SOURCE_DIR as a fallback for direct
# standalone use.
if(DEFINED DEEPEP_REPO_ROOT)
    set(_DEEPEP_GIT_WORKTREE "${DEEPEP_REPO_ROOT}")
else()
    set(_DEEPEP_GIT_WORKTREE "${PROJECT_SOURCE_DIR}")
endif()

if (EXISTS ${GIT_EXECUTABLE})
    execute_process(
            COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
            WORKING_DIRECTORY ${_DEEPEP_GIT_WORKTREE}
            RESULT_VARIABLE GIT_COMMIT_RESULT
            OUTPUT_VARIABLE GIT_COMMIT_ID
            OUTPUT_STRIP_TRAILING_WHITESPACE)

    if (GIT_COMMIT_RESULT EQUAL 0)
        add_compile_definitions(GIT_LAST_COMMIT=${GIT_COMMIT_ID})
        message(STATUS "set GIT_LAST_COMMIT to ${GIT_COMMIT_ID} as compile definition")
    else()
        message(STATUS "Failed to git last commit with git")
    endif()

else()
    message(STATUS "Failed to find git command, not GIT_LAST_COMMIT will be set")
endif()
