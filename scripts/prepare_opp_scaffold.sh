#!/bin/bash
# Generate the OPP project scaffolding used by the standalone operator projects.
#
# The AscendC operator sources in csrc/ops/ (A3/A5) and csrc/ops2/ (A2) are configured as
# a regular OPP CMake project. `msopgen` is used to produce the SoC-specific
# CMakePresets.json (and, on CANN releases that still ship it, the cmake helper
# directory) that the project expects. The generated sample operator sources are
# discarded; only the scaffolding is copied into the operator project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOC_VERSION="${1:-}"
VARIANT="${2:-deepep}"

if [[ -z "${SOC_VERSION}" ]]; then
    echo "Usage: $0 <SOC_VERSION> [deepep|deepep2]" 1>&2
    exit 1
fi

case "${VARIANT}" in
    deepep | deepep2 )
        ;;
    * )
        echo "Unsupported DeepEP variant: ${VARIANT} (expected deepep or deepep2)" 1>&2
        exit 1
        ;;
esac

if ! command -v msopgen >/dev/null 2>&1; then
    echo "Error: msopgen is required but was not found in PATH." 1>&2
    echo "Source the CANN environment first: source /usr/local/Ascend/ascend-toolkit/set_env.sh" 1>&2
    exit 1
fi

if [[ "${VARIANT}" == "deepep2" ]]; then
    OPS_DIR="${PROJECT_ROOT}/csrc/ops2"
    OPS_NAME="ops2"
else
    OPS_DIR="${PROJECT_ROOT}/csrc/ops"
    OPS_NAME="ops"
fi

# opp_scaffold.json is only a template used to make msopgen emit a project
# skeleton; both operator projects share it. Keep "op": "AddCustom" unchanged:
# the generated sample files are deleted with the add_custom* glob below.
SCAFFOLD_TEMPLATE="${PROJECT_ROOT}/scripts/templates/opp_scaffold.json"
if [[ ! -f "${SCAFFOLD_TEMPLATE}" ]]; then
    echo "Error: missing msopgen template: ${SCAFFOLD_TEMPLATE}" 1>&2
    exit 1
fi

GEN_ROOT="${PROJECT_ROOT}/build/opp_gen"
GEN_DIR="${GEN_ROOT}/${OPS_NAME}_${SOC_VERSION}"
rm -rf "${GEN_DIR}"
mkdir -p "${GEN_ROOT}"

echo "msopgen gen -i ${SCAFFOLD_TEMPLATE} -c ai_core-${SOC_VERSION} -f pytorch -lan cpp -out ${GEN_DIR}"
export OPS_PROJECT_NAME=aclnnInner
msopgen gen -i "${SCAFFOLD_TEMPLATE}" \
    -c "ai_core-${SOC_VERSION}" \
    -f pytorch \
    -lan cpp \
    -out "${GEN_DIR}"

# Drop the generated sample operator; the real operator sources live in OPS_DIR.
# -r keeps this working if a CANN release ships a directory instead of files.
rm -rf "${GEN_DIR}"/op_host/add_custom* "${GEN_DIR}"/op_kernel/add_custom*

if [[ -d "${GEN_DIR}/cmake" ]]; then
    rm -rf "${OPS_DIR}/cmake"
    cp -r "${GEN_DIR}/cmake" "${OPS_DIR}/"
fi

if [[ ! -f "${GEN_DIR}/CMakePresets.json" ]]; then
    echo "Error: msopgen did not generate CMakePresets.json under ${GEN_DIR}" 1>&2
    exit 1
fi
cp -f "${GEN_DIR}/CMakePresets.json" "${OPS_DIR}/CMakePresets.json"

rm -rf "${GEN_DIR}"

# The OPP package is installed as the "hwcomputing" vendor (see
# python/deep_ep/deep_ep/__init__.py, which points ASCEND_CUSTOM_OPP_PATH at
# vendors/hwcomputing).
sed -i 's/customize/hwcomputing/g' "${OPS_DIR}/CMakePresets.json"

echo "${OPS_DIR} scaffolding ready (SOC_VERSION=${SOC_VERSION})"
