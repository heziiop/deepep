# `csrc/` 目录重构方案

> 目标：把 host 扩展、`ops`、`ops2` 统一收进 `csrc/`，删除根 `CMakeLists.txt`，让三个子工程各自有构建入口，同时保持编译器、产物和运行时行为不变。

---

## 1. 背景与目标

当前布局：

```text
.
├── CMakeLists.txt          # 只做 host 扩展的公共配置 + add_subdirectory(csrc)
├── cmake/                  # host 扩展的 CMake helper
├── csrc/                   # host 扩展（deep_ep_cpp）
├── ops/                    # A3/A5 OPP 工程
├── ops2/                   # A2 OPP 工程
├── python/
├── tests/
├── scripts/
└── ...
```

目标布局：

```text
.
├── csrc/
│   ├── runtime/            # 原 csrc，host 运行时 + pybind11 扩展
│   │   ├── CMakeLists.txt  # 原根 CMake + 原 csrc/CMakeLists 合并
│   │   ├── cmake/          # 原根 cmake/
│   │   ├── config.cpp/.hpp
│   │   ├── deep_ep.cpp/.hpp
│   │   ├── pybind_extension.cpp
│   │   ├── pytorch_npu_helper.hpp
│   │   ├── event.hpp / exception.hpp
│   │   └── profiling/
│   ├── ops/                # 原 ops/
│   └── ops2/               # 原 ops2/
├── python/
├── tests/
├── scripts/
│   ├── prepare_opp_scaffold.sh   # 原 compile_ascend_proj.sh
│   └── templates/
│       └── opp_scaffold.json     # 原 ops/AddCustom.json
├── docs/
├── .github/
├── build.sh
└── README.md
```

目标：

1. `csrc/` 成为 native 源码根目录；
2. `csrc/runtime` 是 host 运行时，不再叫 `host`，避免和 `ops/op_host` 的 host 语义冲突；
3. 删除根 `CMakeLists.txt`，公共配置下沉到 `csrc/runtime/CMakeLists.txt`；
4. `csrc/runtime`、`csrc/ops`、`csrc/ops2` 各自可构建；
5. `build.sh` 仍然是“按 SoC 选择算子包 + 打 wheel”的总编排；
6. **不改变任何运行时逻辑和算子实现**，只改目录和构建胶水。

---

## 2. 关键决策

| 决策 | 结论 | 理由 |
|---|---|---|
| host 目录名 | 使用 `csrc/runtime` | `host` 会和 `ops/op_host` 冲突；`runtime` 表示库级 host 运行时 |
| 根 `CMakeLists.txt` | 删除 | 只服务 host 扩展，下沉到 `csrc/runtime/CMakeLists.txt` |
| 根 `cmake/` | 移到 `csrc/runtime/cmake/` | 只被 host 使用，让 `runtime` 自包含 |
| `ops`、`ops2` | 移到 `csrc/ops`、`csrc/ops2` | 统一到 `csrc` 下，各自仍是独立 OPP 工程 |
| `compile_ascend_proj.sh` | 改名 `prepare_opp_scaffold.sh`，留在 `scripts/` | 它是 ops/ops2 共用的构建工具，不属于某个算子工程；原名有“编译”的误导 |
| `AddCustom.json` | 移到 `scripts/templates/opp_scaffold.json` | 它是共享的 msopgen 脚手架种子，不是 A3/A5 算子定义 |
| `ops/CMakePresets.json` | 本次仍由 msopgen 生成，继续 gitignore | A3/A5 的 preset 不同；本次不混入构建机制重构 |
| `ops2/CMakePresets.json` | 保持 tracked | 上游已有默认 A2 preset |
| `build.sh` | 保留 | 仍负责 SoC 识别、msopgen 脚手架、选择 ops/ops2、打 wheel |
| `csrc` 命名 | 暂不改成 `src` | 本次只做目录收敛，避免额外重命名 |

---

## 3. 文件移动清单

### 3.1 `runtime`

| 当前 | 目标 |
|---|---|
| `csrc/config.cpp` | `csrc/runtime/config.cpp` |
| `csrc/config.hpp` | `csrc/runtime/config.hpp` |
| `csrc/deep_ep.cpp` | `csrc/runtime/deep_ep.cpp` |
| `csrc/deep_ep.hpp` | `csrc/runtime/deep_ep.hpp` |
| `csrc/event.hpp` | `csrc/runtime/event.hpp` |
| `csrc/exception.hpp` | `csrc/runtime/exception.hpp` |
| `csrc/pybind_extension.cpp` | `csrc/runtime/pybind_extension.cpp` |
| `csrc/pytorch_npu_helper.hpp` | `csrc/runtime/pytorch_npu_helper.hpp` |
| `csrc/profiling/` | `csrc/runtime/profiling/` |
| `csrc/CMakeLists.txt` | `csrc/runtime/CMakeLists.txt` |
| `cmake/` | `csrc/runtime/cmake/` |

### 3.2 算子工程

| 当前 | 目标 |
|---|---|
| `ops/` | `csrc/ops/` |
| `ops2/` | `csrc/ops2/` |

### 3.3 脚本与模板

| 当前 | 目标 |
|---|---|
| `scripts/compile_ascend_proj.sh` | `scripts/prepare_opp_scaffold.sh` |
| `ops/AddCustom.json` | `scripts/templates/opp_scaffold.json` |

### 3.4 删除

| 文件 | 处理 |
|---|---|
| 根 `CMakeLists.txt` | 删除，内容合并到 `csrc/runtime/CMakeLists.txt` |

---

## 4. 分阶段执行

### Phase 0：准备

```bash
cd /home/heziiop/project/deepep
git status
git switch -c refactor/csrc-runtime
python3 -m compileall -q python/deep_ep tests
git rev-parse HEAD > /tmp/deepep-refactor-base.txt
```

建议在动手前保存一份基线：

```bash
git grep -n -E "(^|/)ops2?/" > /tmp/deepep-path-refs-before.txt
```

---

### Phase 1：移动目录

```bash
mkdir -p csrc/runtime
git mv csrc/config.cpp csrc/config.hpp \
       csrc/deep_ep.cpp csrc/deep_ep.hpp \
       csrc/event.hpp csrc/exception.hpp \
       csrc/pybind_extension.cpp csrc/pytorch_npu_helper.hpp \
       csrc/runtime/
git mv csrc/profiling csrc/runtime/profiling
git mv csrc/CMakeLists.txt csrc/runtime/CMakeLists.txt

git mv ops csrc/ops
git mv ops2 csrc/ops2

git mv cmake csrc/runtime/cmake

mkdir -p scripts/templates
git mv csrc/ops/AddCustom.json scripts/templates/opp_scaffold.json

git mv scripts/compile_ascend_proj.sh scripts/prepare_opp_scaffold.sh

git rm CMakeLists.txt
```

移动后检查：

```bash
find csrc -maxdepth 2 -type d | sort
```

期望：

```text
csrc
csrc/ops
csrc/ops/op_host
csrc/ops/op_kernel
csrc/ops2
csrc/ops2/op_host
csrc/ops2/op_kernel
csrc/runtime
csrc/runtime/cmake
csrc/runtime/profiling
```

---

### Phase 2：合并 CMake

`csrc/runtime/CMakeLists.txt` 由两部分组成：

1. 原根 `CMakeLists.txt` 的公共配置；
2. 原 `csrc/CMakeLists.txt` 的 target 定义。

#### P2.1 公共配置

```cmake
cmake_minimum_required(VERSION 3.20 FATAL_ERROR)
project(deep_ep LANGUAGES CXX)

option(DEEPEP_IS_A5_BUILD "build deep_ep for Ascend 950 (A5)" OFF)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 仓库根：csrc/runtime/../..
set(DEEPEP_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

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

if(NOT DEFINED ASCEND_HOME_PATH AND DEFINED ENV{ASCEND_HOME_PATH})
    set(ASCEND_HOME_PATH "$ENV{ASCEND_HOME_PATH}" CACHE PATH "ASCEND CANN package installation directory" FORCE)
endif()
if(NOT DEFINED ASCEND_HOME_PATH OR NOT EXISTS "${ASCEND_HOME_PATH}")
    message(FATAL_ERROR
        "ASCEND_HOME_PATH is not set or does not exist: '${ASCEND_HOME_PATH}'.\n"
        "Source the CANN environment first or pass -DASCEND_HOME_PATH=<cann-root>.")
endif()

include(cmake/config_git_last_commit.cmake)
include(cmake/config_envs.cmake)

find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
endif()
```

#### P2.2 保留原 target 逻辑

其余内容保持原 `csrc/CMakeLists.txt` 不变：

- `DEEPEP_ARCH` 判断；
- `find_program(PYTHON_EXECUTABLE ...)`；
- `find_package(pybind11)`；
- `SOURCES_DEEPEP` + `profiling/*.cpp`；
- `pybind11_add_module(deep_ep_cpp ...)`；
- A5 `__DAV_C310__`；
- `check_cxx_source_compiles`；
- `target_link_libraries`；
- `install`。

#### P2.3 关键 include path 修改

原 `csrc/CMakeLists.txt` 有：

```cmake
target_include_directories(deep_ep_cpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${PROJECT_SOURCE_DIR}      # 原仓库根
    ...
)
```

下沉后 `PROJECT_SOURCE_DIR` 变成 `csrc/runtime`，必须改为：

```cmake
target_include_directories(deep_ep_cpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${DEEPEP_REPO_ROOT}/csrc
    ...
)
```

原因：`csrc/runtime/profiling/common/profile_protocol_common.h` 里有：

```cpp
#include "ops/profiling/common/profile_protocol_common_core.h"
```

把 `csrc/` 加进 include path 后，这个 include 会解析到：

```text
csrc/ops/profiling/common/profile_protocol_common_core.h
```

不需要修改头文件本身。

#### P2.4 修改 `config_git_last_commit.cmake`

当前 helper 使用：

```cmake
WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
```

下沉后应改为仓库根优先：

```cmake
if(DEFINED DEEPEP_REPO_ROOT)
    set(_DEEPEP_GIT_WORKTREE "${DEEPEP_REPO_ROOT}")
else()
    set(_DEEPEP_GIT_WORKTREE "${PROJECT_SOURCE_DIR}")
endif()

execute_process(
    COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
    WORKING_DIRECTORY ${_DEEPEP_GIT_WORKTREE}
    ...
)
```

---

### Phase 3：修改 `build.sh`

#### P3.1 `prepare_ops_project`

```diff
 if [[ "$DEEPEP_VARIANT" == "deepep2" ]]; then
-    proj_dir="ops2"
+    proj_dir="csrc/ops2"
 else
-    proj_dir="ops"
+    proj_dir="csrc/ops"
 fi

 echo "Preparing ${proj_dir} project for ${SOC_VERSION}"
-bash "$PROJECT_ROOT/scripts/compile_ascend_proj.sh" "$SOC_VERSION" "$DEEPEP_VARIANT"
+bash "$PROJECT_ROOT/scripts/prepare_opp_scaffold.sh" "$SOC_VERSION" "$DEEPEP_VARIANT"
```

#### P3.2 `build_host_extension`

```diff
-    cmake "${cmake_args[@]}" \
-        -B "$BUILD_DIR" \
-        -S "$PROJECT_ROOT"
+    cmake "${cmake_args[@]}" \
+        -B "$BUILD_DIR" \
+        -S "$PROJECT_ROOT/csrc/runtime"
```

#### P3.3 `build_device_ops`

```diff
 if [[ "$DEEPEP_VARIANT" == "deepep2" ]]; then
-    kernel_dir="${PROJECT_ROOT}/ops2"
+    kernel_dir="${PROJECT_ROOT}/csrc/ops2"
 else
-    kernel_dir="${PROJECT_ROOT}/ops"
+    kernel_dir="${PROJECT_ROOT}/csrc/ops"
 fi
```

#### P3.4 帮助文本

```diff
-    deepep         (default) Build deep_ep and select ops/ (A3/A5) or ops2/ (A2)
+    deepep         (default) Build deep_ep and select csrc/ops/ (A3/A5) or csrc/ops2/ (A2)
```

---

### Phase 4：脚本与模板

#### P4.1 `scripts/prepare_opp_scaffold.sh`

修改路径：

```bash
OPS_DIR="${PROJECT_ROOT}/csrc/ops2"    # 或 csrc/ops
ADD_CUSTOM_JSON="${PROJECT_ROOT}/scripts/templates/opp_scaffold.json"
```

其他逻辑保持不变：

- `msopgen gen`；
- 删除 `op_host/add_custom*`、`op_kernel/add_custom*`；
- 拷贝 `cmake/`、`CMakePresets.json`；
- `sed customize -> hwcomputing`。

**重要**：`opp_scaffold.json` 的 `"op": "AddCustom"` 不要改。脚本删除示例算子的 glob 是：

```bash
rm -f "${GEN_DIR}"/op_host/add_custom* "${GEN_DIR}"/op_kernel/add_custom*
```

改了 `op` 字段会导致生成的文件名变化，删不掉示例算子。

#### P4.2 `ops` 的 preset

本次不改生成机制：

- `csrc/ops/CMakePresets.json` 仍由 `prepare_opp_scaffold.sh` 生成；
- 继续在 `.gitignore` 中忽略；
- `csrc/ops2/CMakePresets.json` 保持 tracked。

因此：

```bash
# ops2 可以直接构建（前提是 CANN 环境正确）
cd csrc/ops2 && ./build.sh

# ops 需要先生成脚手架
bash scripts/prepare_opp_scaffold.sh Ascend910_9382 deepep
cd csrc/ops && ./build.sh
```

如果后续希望 `csrc/ops` 也完全独立，再按“per-SoC preset”方案单独做，不混在本次重构里。

---

### Phase 5：CI 修改

涉及文件：

- `.github/workflows/pr-test-deepep-npu.yml`
- `.github/workflows/push_build_cache.yml`
- `.github/workflows/build_and_release.yml`

#### P5.1 path filter

`pr-test-deepep-npu.yml`：

```diff
     paths:
       - "build.sh"
       - ".clang-format"
       - "python/deep_ep/**"
       - "csrc/**"
       - "tests/**"
       - "scripts/**"
```

`build_and_release.yml`、`push_build_cache.yml` 同理：

```diff
-      - 'CMakeLists.txt'
-      - 'cmake/**'
-      - 'ops/**'
-      - 'ops2/**'
       - 'csrc/**'
```

#### P5.2 changed-files 分组

`pr-test` 的 `files_yaml`：

```yaml
ops:
  - csrc/ops/**
ops2:
  - csrc/ops2/**
common:
  - csrc/**
  - '!csrc/ops/**'
  - '!csrc/ops2/**'
  - build.sh
  - .clang-format
  - python/**
  - tests/**
  - scripts/**
  - .github/workflows/pr-test-deepep-npu.yml
```

注意：根 `CMakeLists.txt` 已删除，因此从 path filter 和 `common` 分组中一并去掉。

#### P5.3 build hash

当前：

```bash
find ./csrc ./cmake ./ops ./ops2 ./python ./tests ./build.sh ./CMakeLists.txt \
     ./scripts/prepare_deepep_in_container.sh \
     ./scripts/npu_ci_install_dependency.sh
```

改为：

```bash
find ./csrc ./python ./tests ./scripts ./build.sh
```

这样：

- `csrc` 覆盖 runtime + ops + ops2；
- `scripts` 覆盖 `prepare_opp_scaffold.sh`、`prepare_deepep_in_container.sh`、`npu_ci_install_dependency.sh`；
- 删除不存在的 `./cmake`、`./ops`、`./ops2`、`./CMakeLists.txt`。

#### P5.4 缓存 key

建议把：

```text
deep-ep-build-v1
```

改为：

```text
deep-ep-build-v2
```

涉及 `pr-test-deepep-npu.yml` 的 4 处、`push_build_cache.yml` 的 1 处。即使 build hash 变了，显式升版本可以避免旧缓存混淆。

---

### Phase 6：测试、脚本、文档

#### P6.1 `tests/run_ascend_testcase.sh`

把 6 处：

```bash
./ops2/build_out
```

改为：

```bash
./csrc/ops2/build_out
```

涉及行：81、85、100、101、113、114。

#### P6.2 `.gitignore`

```diff
-ops/cmake/
-ops/scripts/
-ops2/cmake/
-ops2/scripts/
-ops/CMakePresets.json
+csrc/ops/cmake/
+csrc/ops/scripts/
+csrc/ops2/cmake/
+csrc/ops2/scripts/
+csrc/ops/CMakePresets.json

 # catlass is fetched by ops/build.sh at build time
-ops/third_party/
+csrc/ops/third_party/

 # CANN header copied into ops2/ by its CMake project at configure time
-ops2/op_kernel/moe_distribute_comm_ctx.h
+csrc/ops2/op_kernel/moe_distribute_comm_ctx.h
```

#### P6.3 README 布局表

英文和中文的仓库布局表都要改：

```diff
-| `csrc/` | Host-side C++/pybind11 extension (`deep_ep_cpp`). |
-| `ops/` | AscendC operator project for A3/A5. |
-| `ops2/` | AscendC operator project for A2. |
+| `csrc/runtime/` | Host-side C++/pybind11 extension (`deep_ep_cpp`). |
+| `csrc/ops/` | AscendC operator project for A3/A5. |
+| `csrc/ops2/` | AscendC operator project for A2. |
```

同时更新：

- `bash build.sh` 仍是唯一完整构建入口；
- 单独构建 host：`cmake -S csrc/runtime -B build`；
- 单独构建 ops/ops2 的说明。

#### P6.4 `docs/MIGRATION.md`

更新映射：

| 上游 | 新仓库 |
|---|---|
| `csrc/deepep/*.cpp`、`*.hpp` | `csrc/runtime/` |
| `csrc/deepep/profiling/` | `csrc/runtime/profiling/` |
| `csrc/deepep/ops/` | `csrc/ops/` |
| `csrc/deepep/ops2/` | `csrc/ops2/` |
| `csrc/deepep/AddCustom.json` | `scripts/templates/opp_scaffold.json` |
| `csrc/deepep/compile_ascend_proj.sh` | `scripts/prepare_opp_scaffold.sh` |
| `csrc/deepep/CMakeLists.txt` + 根 `CMakeLists.txt` | `csrc/runtime/CMakeLists.txt` |
| `cmake/config_*.cmake` | `csrc/runtime/cmake/` |

#### P6.5 `UPSTREAM_COMPARISON.md`

该文档记录的是重构前的映射。重构完成后应：

1. 按新路径重新生成映射；
2. 或将其标注为“重构前快照”，并在文首说明新布局。

---

## 5. 独立构建矩阵

| 目标 | 命令 | 前提 |
|---|---|---|
| host 扩展 | `cmake -S csrc/runtime -B build && cmake --build build --target install` | CANN、torch、torch_npu、pybind11 |
| A2 算子包 | `cd csrc/ops2 && ./build.sh` | CANN、msopgen、tracked `CMakePresets.json` |
| A3 算子包 | `bash scripts/prepare_opp_scaffold.sh Ascend910_9382 deepep` 然后 `cd csrc/ops && ./build.sh` | CANN、msopgen |
| A5 算子包 | `bash scripts/prepare_opp_scaffold.sh Ascend950 deepep` 然后 `cd csrc/ops && ./build.sh` | CANN、msopgen、`ASCEND_COMPUTE_UNIT=ascend950` |
| 完整 wheel | `bash build.sh` | CANN、msopgen、torch/torch_npu |

> 根目录不再是 CMake 工程，`cmake -S .` 不再可用。host 构建请用 `-S csrc/runtime`，完整构建请用 `bash build.sh`。

说明：

- `csrc/ops2` 有 tracked preset，独立构建体验最好；
- `csrc/ops` 仍需 `prepare_opp_scaffold.sh`，因为 A3/A5 preset 不同；
- `build.sh` 仍是推荐入口，因为它会自动处理 SoC 选择、脚手架和打包。

---

## 6. 验证清单

### 6.1 静态检查

```bash
# 旧路径是否还有残留
git grep -n -E "(^|/)ops2?/" -- ':!csrc/ops/**' ':!csrc/ops2/**' ':!UPSTREAM_COMPARISON.md' || true
git grep -n "csrc/ops2/build_out" || true
git grep -n "compile_ascend_proj" || true
git grep -n "AddCustom" || true

# Python 语法
python3 -m compileall -q python/deep_ep tests

# Shell 语法
bash -n build.sh
for f in scripts/*.sh tests/*.sh; do bash -n "$f"; done

# YAML 语法
python3 - <<'PY'
import glob, yaml
for f in glob.glob(".github/workflows/*.yml"):
    with open(f) as fh:
        yaml.safe_load(fh)
    print("OK", f)
PY
```

### 6.2 构建验证

```bash
# host
cmake -S csrc/runtime -B build \
  -DASCEND_HOME_PATH="$ASCEND_HOME_PATH" \
  -DCMAKE_INSTALL_PREFIX="$PWD/output"
cmake --build build --target install -j16

# A2
bash scripts/prepare_opp_scaffold.sh Ascend910B1 deepep2
cd csrc/ops2 && ./build.sh
cd -

# A3
bash scripts/prepare_opp_scaffold.sh Ascend910_9382 deepep
cd csrc/ops && ./build.sh
cd -

# A5
bash scripts/prepare_opp_scaffold.sh Ascend950 deepep
cd csrc/ops && ./build.sh
cd -

# 完整流程
bash build.sh
```

### 6.3 wheel 检查

```bash
unzip -l output/deep_ep*.whl | grep -E "deep_ep_cpp.*\.so|vendors/hwcomputing"
python3 -c "import deep_ep; print(deep_ep.__path__)"
```

设备侧测试需要真实 A2/A3/A5 NPU，静态环境无法替代。

---

## 7. 风险与回滚

| 风险 | 影响 | 处理 |
|---|---|---|
| `PROJECT_SOURCE_DIR` 变化导致 `ops/profiling` include 失败 | host 编译失败 | 使用 `${DEEPEP_REPO_ROOT}/csrc` include path，优先验证 configure |
| 仍有脚本引用旧 `ops/` 路径 | CI 或本地构建失败 | 用 `git grep` 全量检查 |
| CI build hash 漏掉 `scripts` | 缓存复用旧 wheel | hash 改为包含 `./scripts`，并升 `v2` |
| `csrc/ops` preset 仍依赖 `prepare_opp_scaffold.sh` | 不能完全独立构建 | 文档说明；后续可做 per-SoC preset |
| 根 `cmake/` 被外部脚本引用 | 外部构建失败 | 仓库内无引用；如有外部使用，保留根目录 symlink 或文档说明 |

回滚：

```bash
git reset --hard <refactor-base-commit>
```

本次只移动文件和改路径，不涉及数据迁移，回滚成本低。

---

## 8. 不在本次范围

1. **per-SoC preset**：让 `csrc/ops` 也完全独立；
2. 把 `csrc` 改名为 `src`；
3. 恢复上游的编译 hardening flags（`-Wl,-z,relro`、`-ftrapv` 等）；
4. 重写 `msopgen` 脚手架机制；
5. 改动任何算子实现或运行时逻辑。

---

## 9. 执行清单

- [ ] Phase 0：建分支、记录基线
- [ ] Phase 1：移动 `csrc/runtime`、`csrc/ops`、`csrc/ops2`、`csrc/runtime/cmake`
- [ ] Phase 1：移动 `AddCustom.json`、重命名 `compile_ascend_proj.sh`
- [ ] Phase 1：删除根 `CMakeLists.txt`
- [ ] Phase 2：合并 `csrc/runtime/CMakeLists.txt`
- [ ] Phase 2：修改 `config_git_last_commit.cmake`
- [ ] Phase 2：修正 `ops/profiling` include path
- [ ] Phase 3：修改 `build.sh` 三处路径 + 帮助文本
- [ ] Phase 4：修改 `prepare_opp_scaffold.sh` 路径
- [ ] Phase 5：修改 3 个 workflow 的 paths、changed-files、build hash、cache key
- [ ] Phase 6：修改 `tests/run_ascend_testcase.sh`
- [ ] Phase 6：修改 `.gitignore`
- [ ] Phase 6：修改 README / MIGRATION
- [ ] Phase 6：重新生成或标注 `UPSTREAM_COMPARISON.md`
- [ ] 验证：静态检查、CMake configure、A2/A3/A5 构建、wheel 检查
- [ ] 提交：`refactor: group native code under csrc/{runtime,ops,ops2}`

---

## 10. 预期结果

重构完成后：

- 根目录不再有 `CMakeLists.txt` 和 `cmake/`；
- 所有 native 代码位于 `csrc/` 下；
- `csrc/runtime` 可以独立走 CMake 构建；
- `csrc/ops`、`csrc/ops2` 仍是独立 OPP 工程；
- `build.sh` 行为不变，仍然产出同一个 wheel；
- 运行时行为、算子实现、Python API 完全不变。

---

## 11. 执行记录（2026-10-22）

执行环境：

- 分支：`refactor/csrc-runtime`
- CANN：9.1.0
- Python：3.12.13
- torch：2.10.0+cpu
- torch_npu：2.10.0.post6
- 无 NPU 设备，设备测试未运行
- 内存约 13 GiB

构建结果：

| 目标 | 命令 | 结果 |
|---|---|---|
| host 扩展 | `cmake -S csrc/runtime -B build` + `cmake --build build --target install -j2` | 通过 |
| A2 | `bash build.sh -a deepep2` | 通过，wheel 内含 `ascend910b` 算子 |
| A3 | `bash build.sh -a deepep Ascend910_9382` | 通过，wheel 内含 `ascend910_93` 算子 |
| A5 | `bash build.sh -a deepep Ascend950` | 通过，wheel 内含 `ascend950` 算子 |

额外验证：

- `python3 -m compileall -q python/deep_ep tests` 通过；
- `bash -n` 检查所有构建/测试 shell 脚本通过；
- 7 个 workflow YAML 解析通过；
- 最终 wheel 安装到临时目录后，`import deep_ep`、`deep_ep.Buffer`、`deep_ep_cpp` 均成功。

说明：

- `build.sh` 每次构建会清理 `output/deep_ep*.whl`，因此最终 `output/` 中保留的是最后一次 A5 构建的 wheel；
  A2/A3 的构建成功记录保留在 `/tmp/deepep_build_a2.log` 和 `/tmp/deepep_build_a3.log`。
