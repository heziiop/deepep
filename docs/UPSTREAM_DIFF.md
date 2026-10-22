# 上游一致性报告

本文件逐文件记录独立仓库与其上游源码之间的对比结果。

- 上游：`sgl-project/sgl-kernel-npu`，commit
  `a5c12d19fe12dc03aca474852f63cf49f5df8eb2`（2026-10-19）
- 独立仓库：当前 `HEAD`
- 方法：对两边分别执行 `git ls-files`，把上游 DeepEP 路径映射到独立仓库路径，
  再比较 git blob（SHA-1 对象 ID）。只比较 tracked 文件，构建产物不参与。

审计范围是上游 **406 个**属于 DeepEP 的 tracked 文件：`csrc/deepep/`、
`python/deep_ep/`、`tests/python/deepep/` 下的全部文件，以及仅供 DeepEP 使用
的 `scripts/`、CMake helper、workflow 和仓库根文件。

## 总览

| 指标 | 数量 |
|---|---:|
| 上游 DeepEP 文件 | 406 |
| 在本仓库找到对应文件 | 404 |
| ——逐字节一致 | **385** |
| ——内容有修改 | **19** |
| 有意不迁移 | 2 |
| 上游没有对应文件的新增文件 | **5** |
| 本仓库 tracked 文件总数 | **409** |

即 `404 个映射文件 + 5 个新增文件 = 409 个 tracked 文件`；
`385 个一致 + 19 个修改 = 404 个映射文件`。

## 1. 与上游完全一致的目录

下列目录的文件集合与上游对应目录完全相同，且每个文件都逐字节一致，合计
343 个文件。

| 本仓库路径 | 上游路径 | 文件数 |
|---|---|---:|
| `csrc/ops/` | `csrc/deepep/ops/` | 231 |
| `csrc/ops2/` | `csrc/deepep/ops2/` | 86 |
| `csrc/runtime/profiling/` | `csrc/deepep/profiling/` | 14 |
| `python/deep_ep/deep_ep/` | `python/deep_ep/deep_ep/` | 9 |
| `.github/workflows/scripts/wheel/` | `.github/workflows/scripts/wheel/` | 3 |

`csrc/ops/` 与 `csrc/ops2/` 是 AscendC 算子工程的原样拷贝。
`csrc/ops2/CMakePresets.json` 在上游就是 tracked 文件，这里原样保留；
`csrc/ops/` 的 preset 在上游同样未被跟踪，由
`scripts/prepare_opp_scaffold.sh` 在构建时生成。

## 2. 目录之外仍逐字节一致的文件

另有 42 个文件与上游逐字节一致：

| 文件数 | 本仓库路径 | 上游路径 |
|---|---|---|
| 8 | `csrc/runtime/*.{cpp,hpp}`（`config`、`deep_ep`、`event`、`exception`、`pybind_extension`、`pytorch_npu_helper`） | `csrc/deepep/` |
| 1 | `csrc/runtime/cmake/config_envs.cmake` | `cmake/config_envs.cmake` |
| 1 | `scripts/templates/opp_scaffold.json` | `csrc/deepep/AddCustom.json` |
| 1 | `python/deep_ep/setup.py` | 同路径 |
| 4 | `python/deep_ep/doc/{FUSED_DEEP_MOE,GET_DISPATCH_LAYOUT_API,LOW_LATENCY_API,NORMAL_API}.md` | 同路径 |
| 23 | `tests/*.py`、`tests/*.sh` | `tests/python/deepep/` |
| 1 | `scripts/npu_ci_install_dependency.sh` | 同路径 |
| 1 | `.github/workflows/release_deep_ep_wheel.yml` | 同路径 |
| 2 | `LICENSE`、`.clang-format` | `LICENSE`、`csrc/.clang-format` |

`scripts/templates/opp_scaffold.json` 属于**重定位**而非重写：它保留了上游
`AddCustom.json` 的 blob（`d4162b47`），用作两个算子工程的 `msopgen` 种子模板。

## 3. 有修改的文件（19 个）

所有差异都是构建/打包胶水或路径适配，没有改动任何 DeepEP kernel 或运行时逻辑。

### 仅路径适配

| 本仓库文件 | 上游文件 | ±行数 | 改动 |
|---|---|---:|---|
| `tests/k8s_multi.yaml.jinja2` | `tests/python/deepep/k8s_multi.yaml.jinja2` | +2/−2 | `tests/python/deepep` → `tests` |
| `tests/run_ascend_testcase.sh` | `tests/python/deepep/run_ascend_testcase.sh` | +6/−6 | `csrc/deepep/ops2` → `csrc/ops2` |
| `scripts/enumerate_test_intranode.sh` | 同路径 | +2/−1 | workspace 路径改为脚本相对 `../tests` |
| `scripts/enumerate_test_low_latency.sh` | 同路径 | +2/−1 | 同上 |
| `scripts/enumerate_test_low_latency_a2.sh` | 同路径 | +2/−1 | 同上 |
| `scripts/generalization_test_fused_deep_moe.sh` | 同路径 | +2/−4 | 同上 |
| `scripts/prepare_deepep_in_container.sh` | 同路径 | +6/−3 | 仓库根改为脚本相对、`ln -sf`、补 shebang |
| `python/deep_ep/doc/A2_DEEPEP.md` | 同路径 | +8/−8 | `tests/python/deepep` → `tests` |
| `.github/workflows/internode.yml` | 同路径 | +9/−11 | README 锚点、namespace/job/cache 名、测试路径 |

### 构建系统

| 本仓库文件 | 上游文件 | ±行数 | 改动 |
|---|---|---:|---|
| `csrc/runtime/CMakeLists.txt` | `csrc/deepep/CMakeLists.txt`（并入上游根 `CMakeLists.txt`） | +71/−3 | 现在是 host 顶层工程；编译选项与上游逐字一致；include path 增加 `${DEEPEP_REPO_ROOT}/csrc`；合并 project/install 配置 |
| `csrc/runtime/cmake/config_git_last_commit.cmake` | `cmake/config_git_last_commit.cmake` | +12/−1 | `git` 改在 `DEEPEP_REPO_ROOT` 执行；修正失败日志 |
| `scripts/prepare_opp_scaffold.sh` | `csrc/deepep/compile_ascend_proj.sh` | +72/−83 | 重写：改为仓库根相对、模板移到 `scripts/templates/`、输出到 `build/opp_gen/`，只拷贝 `CMakePresets.json`（CANN 提供时再拷 `cmake/`） |

### CI

| 本仓库文件 | 上游文件 | ±行数 | 改动 |
|---|---|---:|---|
| `.github/workflows/build_and_release.yml` | 同路径 | +20/−252 | 从 SGLang kernel + DeepEP 混合流水线裁剪为 DeepEP-only，矩阵改为 A2/A3/A5 |
| `.github/workflows/pr-test-deepep-npu.yml` | 同路径 | +169/−177 | 触发路径、change-detection globs、cache key、测试路径 |
| `.github/workflows/daily-build-test.yml` | 同路径 | +3/−4 | workflow/报告命名 |
| `.github/workflows/push_build_cache.yml` | 同路径 | +10/−21 | 路径列表、build hash、cache key |
| `.github/workflows/lint.yml` | 同路径 | +6/−10 | 去掉 SGLang kernel 单测步骤，增加 `compileall python/deep_ep tests` |
| `.pre-commit-config.yaml` | 同路径 | +0/−7 | 去掉只针对未迁移目录的 `ruff` hook |

### 文档

| 本仓库文件 | 上游文件 | ±行数 | 改动 |
|---|---|---:|---|
| `python/deep_ep/README.md` | 同路径 | +10/−621 | 正文上移为仓库根 `README.md`，本文件改为 15 行指针 |
| `README.md` | `python/deep_ep/README.md` | 新增 | 由上游 README 改写而来的仓库级 README |

## 4. 新增文件（5 个）

| 文件 | 用途 |
|---|---|
| `README.md` | 仓库级文档（独立仓库的根 README） |
| `build.sh` | 独立构建驱动，替代 monorepo 的模块 wrapper |
| `.gitignore` | 独立构建的忽略规则（`output/`、`build/`、生成的 preset 等） |
| `docs/MIGRATION.md` | 归属/迁移审计与上游移除清单 |
| `docs/UPSTREAM_DIFF.md` | 本报告 |

## 5. 未迁移（2 个）

| 上游文件 | 原因 |
|---|---|
| `csrc/deepep/README.md` | 上游即为 0 字节空文件 |
| `csrc/deepep/build.sh` | monorepo 的模块分发 wrapper（`all`/`deepep` 目标），已由 `build.sh` 取代 |

## 复现方式

```bash
UP=/path/to/sgl-kernel-npu          # 位于 a5c12d1
NEW=/path/to/deepep-separate

# 判断某个上游文件是否属于 DeepEP。
is_deepep() {
    case "$1" in
        csrc/deepep/*|python/deep_ep/*|tests/python/deepep/*) return 0 ;;
        .github/workflows/build_and_release.yml|.github/workflows/daily-build-test.yml) return 0 ;;
        .github/workflows/internode.yml|.github/workflows/lint.yml) return 0 ;;
        .github/workflows/pr-test-deepep-npu.yml|.github/workflows/push_build_cache.yml) return 0 ;;
        .github/workflows/release_deep_ep_wheel.yml|.github/workflows/scripts/wheel/*) return 0 ;;
        scripts/enumerate_test_intranode.sh|scripts/enumerate_test_low_latency.sh) return 0 ;;
        scripts/enumerate_test_low_latency_a2.sh|scripts/generalization_test_fused_deep_moe.sh) return 0 ;;
        scripts/npu_ci_install_dependency.sh|scripts/prepare_deepep_in_container.sh) return 0 ;;
        cmake/config_envs.cmake|cmake/config_git_last_commit.cmake) return 0 ;;
        csrc/.clang-format|.pre-commit-config.yaml|LICENSE) return 0 ;;
    esac
    return 1
}

# 把上游路径映射到本仓库路径（输出为空表示有意不迁移）。
map() {
    case "$1" in
        csrc/deepep/ops/*)          echo "csrc/ops/${1#csrc/deepep/ops/}" ;;
        csrc/deepep/ops2/*)         echo "csrc/ops2/${1#csrc/deepep/ops2/}" ;;
        csrc/deepep/profiling/*)    echo "csrc/runtime/profiling/${1#csrc/deepep/profiling/}" ;;
        csrc/deepep/AddCustom.json) echo "scripts/templates/opp_scaffold.json" ;;
        csrc/deepep/compile_ascend_proj.sh) echo "scripts/prepare_opp_scaffold.sh" ;;
        csrc/deepep/README.md|csrc/deepep/build.sh) echo "" ;;
        csrc/deepep/*)              echo "csrc/runtime/${1#csrc/deepep/}" ;;
        tests/python/deepep/*)      echo "tests/${1#tests/python/deepep/}" ;;
        cmake/*)                    echo "csrc/runtime/cmake/${1#cmake/}" ;;
        csrc/.clang-format)         echo ".clang-format" ;;
        *)                          echo "$1" ;;
    esac
}

# 逐个比较映射后文件的 blob。
git -C "$UP" ls-files | while read -r f; do
    is_deepep "$f" || continue
    t=$(map "$f")
    [ -z "$t" ] && { echo "DROPPED $f"; continue; }
    a=$(git -C "$UP" rev-parse "HEAD:$f") || continue
    b=$(git -C "$NEW" rev-parse "HEAD:$t" 2>/dev/null) || { echo "MISSING $f"; continue; }
    [ "$a" = "$b" ] || echo "DIFF $f -> $t"
done
```
