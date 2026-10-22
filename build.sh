#!/bin/bash
set -e

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OUTPUT_DIR="${PROJECT_ROOT}/output"
readonly BUILD_DIR="${PROJECT_ROOT}/build"
readonly DEFAULT_ASCEND_ROOT="/usr/local/Ascend/ascend-toolkit"

export VERSION="${VERSION:-1.0.0}"

BUILD_TARGET="deepep"
REQUESTED_SOC_VERSION=""
SOC_VERSION=""
CMAKE_SOC_VERSION="Ascend910_9382"
DEEPEP_VARIANT="deepep"
DEEPEP_IS_A5_BUILD="OFF"

DEBUG_MODE="OFF"
ASC_CMAKE_DIR=""
ASCEND_INCLUDE_DIR=""

function die()
{
    echo "Error: $*" 1>&2
    exit 1
}

function print_help()
{
    cat <<'EOF'
Usage:
    ./build.sh [SOC_VERSION]                    Build deep_ep for the detected chip.
    ./build.sh -a deepep [SOC_VERSION]          Build deep_ep (A2, A3, or A5).
    ./build.sh -a deepep2 [SOC_VERSION]         Build deep_ep with the A2 operator package.

Omitting SOC_VERSION auto-detects it with npu-smi; hosts without a device fall
back to Ascend910_9382 (A3).

TARGET:
    deepep         (default) Build deep_ep and select csrc/ops/ (A3/A5) or csrc/ops2/ (A2)
                   from the detected SoC.
    deepep2        Build deep_ep with csrc/ops2/ for A2 (compatible alias).

SOC_VERSION:
    Ascend910B1         A2 chip. Valid for deepep/deepep2.
    Ascend910_9382      A3 chip. Valid for deepep.
    Ascend950           Ascend 950 family alias. Valid for deepep.
    (omitted)           deepep: auto-detect via npu-smi, fallback Ascend910_9382.
                        deepep2: defaults to Ascend910B1.

SOC_VERSION aliases:
    910B | Ascend910B1                       A2
    910  | 910C | Ascend910_9382             A3
    950  | Ascend950 | Ascend950{PR,DT}_*    Ascend 950 (A5)

Options:
    -d             Enable debug logging.
    -h             Show this help.

Examples:
    ./build.sh                                  # auto-detect chip
    ./build.sh -a deepep Ascend950              # explicit A5 DeepEP
    ./build.sh -a deepep2                       # A2 DeepEP
    ./build.sh -a deepep Ascend910_9382 -d      # A3 DeepEP with debug logs
EOF
}

function parse_arguments()
{
    local opt
    OPTIND=1

    while getopts ":a:hd" opt; do
        case "$opt" in
            a )
                BUILD_TARGET="$OPTARG"
                ;;
            d )
                DEBUG_MODE="ON"
                ;;
            h )
                print_help
                exit 0
                ;;
            \? )
                die "Unknown flag: -$OPTARG. Run './build.sh -h' for more information."
                ;;
            : )
                die "-$OPTARG requires a value. Run './build.sh -h' for more information."
                ;;
        esac
    done

    shift $((OPTIND - 1))
    if [[ "$#" -gt 1 ]]; then
        die "Expected at most one SOC_VERSION argument."
    fi
    REQUESTED_SOC_VERSION="${1:-}"
}

function configure_build_target()
{
    case "$BUILD_TARGET" in
        all | deepep )
            BUILD_TARGET="deepep"
            DEEPEP_VARIANT="deepep"
            ;;
        deepep2 )
            DEEPEP_VARIANT="deepep2"
            ;;
        * )
            die "Invalid target '$BUILD_TARGET'. Allowed values: deepep|deepep2"
            ;;
    esac
}

# $1: pass "strict" to abort when npu-smi reports a chip this script does not
# recognize. deepep picks its ops variant from the SoC, so guessing wrong is
# worse than stopping; hosts without npu-smi fall back to the A3 target.
function detect_soc_version()
{
    local strict="${1:-}"
    local board_info=""

    if ! command -v npu-smi >/dev/null 2>&1; then
        SOC_VERSION="Ascend910_9382"
        echo "Cannot find npu-smi; defaulting SOC_VERSION to $SOC_VERSION"
        return
    fi

    # A5 supports the device-level query and reports Chip Name as Ascend950*.
    board_info="$(npu-smi info -t board -i 0 2>/dev/null || true)"
    if printf '%s\n' "$board_info" |
        grep -Eiq '^[[:space:]]*Chip Name[[:space:]]*:[[:space:]]*Ascend950'; then
        SOC_VERSION="Ascend950"
        echo "Detected A5: SOC_VERSION=$SOC_VERSION"
        return
    fi

    # A2 and A3 require a chip ID. Check A2 first because it reports 910B*,
    # while A3 reports Ascend910.
    board_info="$(npu-smi info -t board -i 0 -c 0 2>/dev/null || true)"
    if printf '%s\n' "$board_info" |
        grep -Eiq '^[[:space:]]*Chip Name[[:space:]]*:[[:space:]]*910B'; then
        SOC_VERSION="Ascend910B1"
        echo "Detected A2: SOC_VERSION=$SOC_VERSION"
        return
    fi

    if printf '%s\n' "$board_info" |
        grep -Eiq '^[[:space:]]*Chip Name[[:space:]]*:[[:space:]]*Ascend910'; then
        SOC_VERSION="Ascend910_9382"
        echo "Detected A3: SOC_VERSION=$SOC_VERSION"
        return
    fi

    if [[ "$strict" == "strict" ]]; then
        die "Cannot determine the device type (A2/A3/A5) from npu-smi output."
    fi

    SOC_VERSION="Ascend910_9382"
    echo "Cannot recognize the NPU from npu-smi output; falling back to SOC_VERSION=$SOC_VERSION"
}

# Fold friendly product names onto canonical SoC names.
function normalize_soc_version()
{
    case "$SOC_VERSION" in
        910 | Ascend910 | 910C )
            SOC_VERSION="Ascend910_9382"
            ;;
        910B )
            SOC_VERSION="Ascend910B1"
            ;;
        950 | [Aa]scend950 )
            SOC_VERSION="Ascend950"
            ;;
        [Aa]scend950[Pp][Rr]_* | [Aa]scend950[Dd][Tt]_* )
            # The operator project only needs the Ascend 950 family name.
            SOC_VERSION="Ascend950"
            ;;
        * )
            # Anything else is a concrete AscendC compiler target
            # (Ascend910B2, Ascend910_9391, ...); validate it below.
            ;;
    esac
}

function configure_soc_version()
{
    if [[ -n "$REQUESTED_SOC_VERSION" ]]; then
        SOC_VERSION="$REQUESTED_SOC_VERSION"
    elif [[ "$BUILD_TARGET" == "deepep2" ]]; then
        # A2-only by definition, so there is nothing to detect.
        SOC_VERSION="Ascend910B1"
    else
        detect_soc_version strict
    fi

    normalize_soc_version

    case "$SOC_VERSION" in
        Ascend910B1 )
            DEEPEP_VARIANT="deepep2"
            ;;
        Ascend910_9382 | Ascend950 )
            DEEPEP_VARIANT="deepep"
            ;;
        * )
            die "Target '$BUILD_TARGET' supports only Ascend910B1 (A2), Ascend910_9382 (A3), or Ascend950 (A5)."
            ;;
    esac

    if [[ "$BUILD_TARGET" == "deepep2" && "$SOC_VERSION" != "Ascend910B1" ]]; then
        die "Target 'deepep2' supports only Ascend910B1 (A2)."
    fi

    # The host-side CMake project is SoC agnostic; keep the historical A3 value
    # so that the generated operator scaffolding matches previous builds.
    CMAKE_SOC_VERSION="Ascend910_9382"

    if [[ "$SOC_VERSION" == "Ascend950" ]]; then
        DEEPEP_IS_A5_BUILD="ON"
        export ASCEND_COMPUTE_UNIT="ascend950"
    else
        unset ASCEND_COMPUTE_UNIT
    fi

    echo "Build target: $BUILD_TARGET"
    echo "DeepEP variant: $DEEPEP_VARIANT"
    echo "DeepEP SOC_VERSION: $SOC_VERSION"
    echo "DeepEP ASCEND_COMPUTE_UNIT: ${ASCEND_COMPUTE_UNIT:-<unset>}"
    echo "CMake SOC_VERSION: $CMAKE_SOC_VERSION"
}

function resolve_ascend_home()
{
    local configured_path="${ASCEND_HOME_PATH:-}"
    local candidate=""
    local path=""

    if [[ -f "$configured_path" && "$(basename "$configured_path")" == "set_env.sh" ]]; then
        configured_path="$(dirname "$configured_path")"
    fi

    if [[ -n "$configured_path" && "$(basename "$configured_path")" == "latest" ]]; then
        candidate="$(readlink -f "$configured_path" 2>/dev/null || true)"
        if [[ -n "$candidate" ]]; then
            configured_path="$candidate"
        fi
    fi

    if [[ -n "$configured_path" && -d "$configured_path" && -f "$configured_path/set_env.sh" ]]; then
        candidate="$configured_path"
    else
        if [[ -n "$configured_path" ]]; then
            echo "Warning: Ignoring invalid ASCEND_HOME_PATH: $configured_path"
        fi

        candidate=""
        while IFS= read -r path; do
            if [[ -f "$path/set_env.sh" ]]; then
                candidate="$path"
            fi
        done < <(find "$DEFAULT_ASCEND_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            ! -name latest \
            -print 2>/dev/null | sort -V)

        if [[ -z "$candidate" && -d "$DEFAULT_ASCEND_ROOT/latest" ]]; then
            path="$(readlink -f "$DEFAULT_ASCEND_ROOT/latest" 2>/dev/null || true)"
            if [[ -n "$path" && -f "$path/set_env.sh" ]]; then
                candidate="$path"
            fi
        fi

        if [[ -z "$candidate" && -f "$DEFAULT_ASCEND_ROOT/set_env.sh" ]]; then
            candidate="$DEFAULT_ASCEND_ROOT"
        fi
    fi

    if [[ -z "$candidate" ]]; then
        die "Cannot find an Ascend toolkit directory containing set_env.sh"
    fi

    export ASCEND_HOME_PATH="$candidate"
}

function setup_ascend_environment()
{
    local resolved_ascend_home=""
    local asc_config_cmake=""

    resolve_ascend_home
    resolved_ascend_home="$ASCEND_HOME_PATH"

    # CANN's environment script may rewrite ASCEND_HOME_PATH to "latest".
    # Keep the resolved installation directory as the source of truth.
    source "$resolved_ascend_home/set_env.sh"
    export ASCEND_HOME_PATH="$resolved_ascend_home"
    export ASCEND_TOOLKIT_HOME="${ASCEND_TOOLKIT_HOME:-$resolved_ascend_home}"

    asc_config_cmake="$(find "$ASCEND_HOME_PATH" \
        -name "ASCConfig.cmake" \
        -type f \
        -print \
        -quit 2>/dev/null)"
    if [[ -n "$asc_config_cmake" ]]; then
        ASC_CMAKE_DIR="$(dirname "$asc_config_cmake")"
        export CMAKE_PREFIX_PATH="$ASC_CMAKE_DIR${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
        export ASC_DIR="$ASC_CMAKE_DIR"
        echo "Found ASCConfig.cmake at: $asc_config_cmake"
    else
        echo "Warning: Cannot find ASCConfig.cmake under $ASCEND_HOME_PATH"
    fi

    ASCEND_INCLUDE_DIR="${ASCEND_TOOLKIT_HOME}/$(arch)-linux/include"

    echo "ASCEND_HOME_PATH: $ASCEND_HOME_PATH"
    echo "ASCEND_TOOLKIT_HOME: $ASCEND_TOOLKIT_HOME"
    echo "ASCEND_INCLUDE_DIR: $ASCEND_INCLUDE_DIR"
}

function ensure_wheel_package()
{
    if python3 -m pip show wheel >/dev/null 2>&1; then
        echo "wheel has been installed"
    else
        python3 -m pip install wheel==0.45.1
    fi
}

# Generate the OPP project scaffolding (CMakePresets, optional cmake helpers)
# required by csrc/ops/ or csrc/ops2/ before the operator package can be built.
function prepare_ops_project()
{
    local proj_dir=""
    if [[ "$DEEPEP_VARIANT" == "deepep2" ]]; then
        proj_dir="csrc/ops2"
    else
        proj_dir="csrc/ops"
    fi

    echo "Preparing ${proj_dir} project for ${SOC_VERSION}"
    bash "$PROJECT_ROOT/scripts/prepare_opp_scaffold.sh" "$SOC_VERSION" "$DEEPEP_VARIANT"
}

# Build and install the host-side pybind11 extension (deep_ep_cpp).
function build_host_extension()
{
    local cmake_args=(
        "-DCMAKE_INSTALL_PREFIX=$OUTPUT_DIR"
        "-DASCEND_HOME_PATH=$ASCEND_HOME_PATH"
        "-DDEEPEP_IS_A5_BUILD=$DEEPEP_IS_A5_BUILD"
    )

    if [[ -n "$ASC_CMAKE_DIR" ]]; then
        cmake_args+=(
            "-DCMAKE_PREFIX_PATH=$ASC_CMAKE_DIR"
            "-DASC_DIR=$ASC_CMAKE_DIR"
        )
    fi

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # output/ is the install prefix and survives between builds; drop a module
    # built for a different Python ABI so it cannot be packaged alongside the
    # one installed below.
    rm -f "$OUTPUT_DIR"/lib/deep_ep_cpp*.so

    cmake "${cmake_args[@]}" \
        -B "$BUILD_DIR" \
        -S "$PROJECT_ROOT/csrc/runtime"
    cmake --build "$BUILD_DIR" --target install -j "${BUILD_JOBS:-16}"
}

# Build the AscendC operator package and install it into the Python package.
function build_device_ops()
{
    local kernel_dir=""
    local custom_opp_dir="${PROJECT_ROOT}/python/deep_ep/deep_ep"
    local custom_opp_file=""

    if [[ "$DEEPEP_VARIANT" == "deepep2" ]]; then
        kernel_dir="${PROJECT_ROOT}/csrc/ops2"
    else
        kernel_dir="${PROJECT_ROOT}/csrc/ops"
    fi

    (
        cd "$kernel_dir"
        chmod +x build.sh
        ./build.sh

        custom_opp_file="$(find ./build_out \
            -maxdepth 1 \
            -type f \
            -name "custom_opp*.run" \
            -print \
            -quit)"
        if [[ -z "$custom_opp_file" ]]; then
            die "Cannot find custom_opp*.run under $kernel_dir/build_out"
        fi

        echo "Found run package: $custom_opp_file"
        chmod +x "$custom_opp_file"
        rm -rf "$custom_opp_dir/vendors"
        "$custom_opp_file" --install-path="$custom_opp_dir"
    )
}

function make_deepep_package()
{
    (
        cd "$PROJECT_ROOT/python/deep_ep"
        # Drop extensions built for a previous Python ABI so setup.py's
        # deep_ep_cpp*.so glob cannot ship more than one module.
        rm -f "$PROJECT_ROOT"/python/deep_ep/deep_ep/deep_ep_cpp*.so
        cp -v "$OUTPUT_DIR"/lib/* "$PROJECT_ROOT/python/deep_ep/deep_ep/"
        rm -rf build dist
        python3 setup.py clean --all
        python3 setup.py bdist_wheel
        mv -v dist/deep_ep*.whl "$OUTPUT_DIR/"
        rm -rf dist
    )
}

function main()
{
    parse_arguments "$@"
    configure_build_target
    configure_soc_version
    export DEBUG_MODE

    setup_ascend_environment
    mkdir -p "$OUTPUT_DIR"
    echo "Output directory: $OUTPUT_DIR"
    echo "CANN path: $ASCEND_HOME_PATH"

    prepare_ops_project
    build_host_extension
    build_device_ops

    ensure_wheel_package
    make_deepep_package

    echo "Build finished. Wheel:"
    ls -1 "$OUTPUT_DIR"/deep_ep*.whl
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
