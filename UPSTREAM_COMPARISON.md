# DeepEP-Ascend 与 sgl-kernel-npu 对比报告

> 注：本报告记录的是 **csrc 重构前** 的目录布局（2026-10-21）。
> 当前仓库已按 `CSRC_REFACTOR_PLAN.md` 将 host 代码移到 `csrc/runtime/`，
> `ops/ops2` 移到 `csrc/ops/`、`csrc/ops2/`。文件内容与差异数量不变，仅路径映射变化。

> 对比基准：
>
> - 上游仓库：`/home/heziiop/project/sgl-kernel-npu`
> - 上游 HEAD：`a5c12d1`（与 [MIGRATION.md](docs/MIGRATION.md) 记录一致）
> - 新仓库：`/home/heziiop/project/deepep`
> - 方法：读取两边 `git ls-files`，按迁移路径映射后逐个比较 SHA-256 / git blob，并检查文件模式。

---

## 0. 对比结论

| 指标 | 数量 |
|---|---:|
| 上游跟踪文件 | 1178 |
| 新仓库跟踪文件 | 409 |
| 能映射到新仓库的上游文件 | 407 |
| 其中逐字节完全相同 | **385**（94.6%） |
| 其中有修改 | **22**（5.4%） |
| 新仓库新增文件 | **2** |
| DeepEP 范围内明确未迁移 | **2** |
| 上游非 DeepEP 文件 | 769 |

> 409（新仓库）= 407（映射文件）+ 2（新增文件）。

核心结论：

1. **迁移保真度很高**：385/407 逐字节一致；所有 AscendC 算子、C++ host 代码、Python 包、测试 `.py` 均无功能改动。
2. **改动集中在“独立仓库化”**：根 `build.sh`、根 `CMakeLists.txt`、CI、路径解析、文档；这些文件不能用上游同名文件直接覆盖。
3. **上游同步成本低**：`ops/`、`ops2/`、`csrc/`（除 CMakeLists）、`python/deep_ep/`（除 doc）、`tests/*.py` 都可直接按映射 cherry-pick；`build.sh`、CI、README 需要手工合并。

---

## 1. 路径映射关系

| 上游路径 | 新仓库路径 | 方式 |
|---|---|---|
| `csrc/deepep/*.cpp`、`*.hpp` | [csrc/](csrc) | 移动，内容基本原样 |
| `csrc/deepep/profiling/` | [csrc/profiling/](csrc/profiling) | 移动，原样 |
| `csrc/deepep/ops/` | [ops/](ops) | 移出为顶层目录，原样 |
| `csrc/deepep/ops2/` | [ops2/](ops2) | 移出为顶层目录，原样 |
| `csrc/deepep/AddCustom.json` | [ops/AddCustom.json](ops/AddCustom.json) | 移动，原样 |
| `csrc/deepep/CMakeLists.txt` | [csrc/CMakeLists.txt](csrc/CMakeLists.txt) | 移动，+4 行修改 |
| `csrc/deepep/compile_ascend_proj.sh` | [scripts/compile_ascend_proj.sh](scripts/compile_ascend_proj.sh) | 移动并重写 |
| `python/deep_ep/` | [python/deep_ep/](python/deep_ep) | 同路径，代码原样 |
| `python/deep_ep/README.md` | [README.md](README.md) | 提升为仓库根 README 并扩写 |
| `tests/python/deepep/` | [tests/](tests) | 移动，Python 文件原样 |
| `csrc/.clang-format` | [.clang-format](.clang-format) | 移动，原样 |
| `cmake/config_envs.cmake` | 同路径 | 原样 |
| `cmake/config_git_last_commit.cmake` | 同路径 | 小改 |
| `scripts/` 下 5 个 DeepEP 测试脚本 | 同路径 | 路径适配 |
| `.github/workflows/` 下 7 条 DeepEP 相关 workflow | 同路径 | 适配 |
| `.github/workflows/scripts/wheel/` | 同路径 | 原样 |

---

## 2. 逐目录统计

| 新仓库目录 | 来源 | 完全相同 | 有修改 | 说明 |
|---|---|---:|---:|---|
| [ops/](ops) | `csrc/deepep/ops/` | 232 | 0 | **整目录原样搬移** |
| [ops2/](ops2) | `csrc/deepep/ops2/` | 86 | 0 | **整目录原样搬移** |
| [csrc/](csrc) | `csrc/deepep/` + `profiling/` | 22 | 1 | 只有 `CMakeLists.txt` 有 4 行改动 |
| [python/deep_ep/](python/deep_ep) | 同路径 | 14 | 1 | 只有 `A2_DEEPEP.md` 更新了测试路径 |
| [tests/](tests) | `tests/python/deepep/` | 23 | 2 | 所有 `test_*.py` 均原样；只改 k8s 模板和运行脚本 |
| [scripts/](scripts) | `scripts/` + `compile_ascend_proj.sh` | 1 | 6 | 只有 `npu_ci_install_dependency.sh` 原样 |
| [.github/](.github) | 同路径 | 4 | 6 | release workflow 和 3 个 wheel 脚本原样 |
| [cmake/](cmake) | 同路径 | 1 | 1 | `config_envs.cmake` 原样 |
| 根目录 | 上游根目录 + `csrc/.clang-format` | 2 | 5 | `LICENSE`、`.clang-format` 原样 |
| **合计** | | **385** | **22** | |

> 文件模式差异只有 1 处：`scripts/prepare_deepep_in_container.sh` 从上游的 `100644` 变为新仓库的 `100755`。

关键结论：**DeepEP 的运行时代码没有任何功能改动**。所有 C++/AscendC/Python 包/测试 `.py` 文件都逐字节一致，变化全部集中在构建、CI、文档和路径胶水。

---

## 3. 22 个有修改的文件

### A. 构建与仓库配置（7 个）

| 文件 | 上游对应 | 差异 | 修改内容 |
|---|---|---|---|
| [build.sh](build.sh) | `build.sh` | +104/−299 | 重写为 standalone：删除 kernels/attention/memory-saver 目标，默认 target 改为 `deepep` |
| [CMakeLists.txt](CMakeLists.txt) | `CMakeLists.txt` | +25/−41 | 裁剪为 DeepEP-only，去掉 kernels/catlass 选项，新增 `ASCEND_HOME_PATH` 校验，精简编译/链接选项 |
| [csrc/CMakeLists.txt](csrc/CMakeLists.txt#L42-L46) | `csrc/deepep/CMakeLists.txt` | +4/−0 | 把仓库根加入 include path，供 profiling 头文件使用 |
| [.gitignore](.gitignore#L54-L68) | `.gitignore` | +12/−4 | `csrc/deepep/ops*` 改为 `ops*`，新增 `ops/third_party/` 等忽略项 |
| [.pre-commit-config.yaml](.pre-commit-config.yaml) | 同路径 | +0/−7 | 删除只针对 monorepo `benchmark/docs/examples` 的 ruff hook |
| [cmake/config_git_last_commit.cmake](cmake/config_git_last_commit.cmake#L1-L20) | 同路径 | +2/−1 | 指定 `WORKING_DIRECTORY`，并修正日志变量 |
| [scripts/compile_ascend_proj.sh](scripts/compile_ascend_proj.sh) | `csrc/deepep/compile_ascend_proj.sh` | +71/−83 | 移到 `scripts/`，重写项目根、ops/ops2 选择和 msopgen 逻辑 |

### B. CI workflow（6 个）

| 文件 | 差异 | 修改内容 |
|---|---|---|
| [pr-test-deepep-npu.yml](.github/workflows/pr-test-deepep-npu.yml) | +177/−175 | 路径改为 `ops/`、`ops2/`、`tests/`；缓存 key 改为 `deep-ep-build-v1`；去掉 submodules |
| [build_and_release.yml](.github/workflows/build_and_release.yml) | +26/−252 | 删除 SGLang kernels 构建 job，矩阵裁剪为 DeepEP-only |
| [push_build_cache.yml](.github/workflows/push_build_cache.yml) | +12/−17 | 路径和缓存 key 对齐 PR 流程 |
| [daily-build-test.yml](.github/workflows/daily-build-test.yml) | +3/−4 | 名称和报告文案改为 DeepEP |
| [internode.yml](.github/workflows/internode.yml) | +9/−11 | namespace、缓存目录、测试路径改为 deepep |
| [lint.yml](.github/workflows/lint.yml) | +5/−10 | 删除 monorepo 的 build-target pytest，改为 `compileall` 语法检查 |

### C. 文档（2 个）

| 文件 | 上游对应 | 差异 | 修改内容 |
|---|---|---|---|
| [README.md](README.md) | `python/deep_ep/README.md` | +102/−45 | 提升为根 README，增加独立仓库布局、构建说明、CI 状态；文档链接改根路径 |
| [python/deep_ep/doc/A2_DEEPEP.md](python/deep_ep/doc/A2_DEEPEP.md#L128-L140) | 同路径 | +8/−8 | `tests/python/deepep/` 改为 `tests/` |

### D. 测试/脚本路径适配（7 个）

| 文件 | 差异 | 修改内容 |
|---|---|---|
| [scripts/enumerate_test_intranode.sh](scripts/enumerate_test_intranode.sh) | +2/−1 | `GITHUB_WORKSPACE/tests/python/deepep` → 脚本相对路径 `../tests` |
| [scripts/enumerate_test_low_latency.sh](scripts/enumerate_test_low_latency.sh) | +2/−1 | 同上 |
| [scripts/enumerate_test_low_latency_a2.sh](scripts/enumerate_test_low_latency_a2.sh) | +2/−1 | 同上 |
| [scripts/generalization_test_fused_deep_moe.sh](scripts/generalization_test_fused_deep_moe.sh) | +2/−4 | 同上 |
| [scripts/prepare_deepep_in_container.sh](scripts/prepare_deepep_in_container.sh) | +6/−3 | 增加 shebang、按脚本位置解析项目根、修正 pip/ln 路径；文件模式 644→755 |
| [tests/k8s_multi.yaml.jinja2](tests/k8s_multi.yaml.jinja2#L128-L138) | +2/−2 | 容器内测试脚本路径 `tests/python/deepep` → `tests` |
| [tests/run_ascend_testcase.sh](tests/run_ascend_testcase.sh#L78-L112) | +6/−6 | `csrc/deepep/ops2/build_out` → `ops2/build_out` |

---

## 4. 新增的文件/目录

严格意义上只有 2 个文件是全新内容：

| 文件 | 说明 |
|---|---|
| [docs/MIGRATION.md](docs/MIGRATION.md) | 新增的迁移审计、所有权说明、上游删除清单、构建验证记录 |
| [python/deep_ep/README.md](python/deep_ep/README.md) | 新增的简短指针桩，指向根 README 和 API 文档 |

目录层面的“新增”：

- [ops/](ops)、[ops2/](ops2)：从 `csrc/deepep/` 下提升为顶层目录，内容原样。
- [docs/](docs)：新顶层目录，目前只有 `MIGRATION.md`。
- [scripts/compile_ascend_proj.sh](scripts/compile_ascend_proj.sh)：新路径，内容由上游同名脚本重写而来。
- 根 [README.md](README.md)：虽然不是“从零新增”，但内容由 `python/deep_ep/README.md` 提升并大量扩写。

---

## 5. 未迁移的文件

### DeepEP 目录内明确未迁移（2 个）

| 上游文件 | 原因 |
|---|---|
| `csrc/deepep/README.md` | 0 字节空文件，无内容可迁 |
| `csrc/deepep/build.sh` | monorepo 的模块分发 wrapper，已被新根 `build.sh` 取代 |

### DeepEP 相关、但留在上游的文件

| 上游文件 | 原因 |
|---|---|
| `csrc/deepep_cmake_build.sh` | monorepo CMake wrapper |
| `benchmark/bench_deepep.py` | 0 字节占位文件 |
| `tests/python/sgl_kernel_npu/test_build_targets.py` | 测试的是 monorepo `build.sh` target 分发，不是 DeepEP 运行时代码 |
| `.github/workflows/pr-test-kernels.yml` | 只在 path exclusion 中提到 `csrc/deepep/**` |
| `csrc/CMakeLists.txt` | monorepo 的 csrc 总 CMake；新仓库改用 DeepEP-only 版本 |
| 根 `README.md` | monorepo README；新 README 来自 `python/deep_ep/README.md` |
| `cmake/config_ascend.cmake`、`config.ini`、`include/`、`third_party/`、`contrib/`、`python/sgl_kernel_npu/` 等 | 非 DeepEP 模块或未使用 |

其余 **769 个**上游文件属于 SGLang kernels、attention、memory saver、contrib、benchmark 等非 DeepEP 范围。

---

## 6. 与 `docs/MIGRATION.md` 数字的差异

[MIGRATION.md](docs/MIGRATION.md#L149) 写的是：

- 383 个映射文件
- 378 个完全一致
- 5 个有差异
- 0 个缺失

本次全量逐文件比对结果是：

- **407 个映射文件**
- **385 个完全一致**
- **22 个有差异**
- 0 个必需文件缺失

差异来源是文档的 parity 统计口径更窄：它只覆盖“源码/测试/文档主体”，没有把仓库级 build、CI、脚本胶水全部计入。文档点名的 5 个差异文件本次全部确认有差异；其余 17 个差异属于构建/CI/脚本适配，另有 7 个原样文件同样不在文档的窄口径里。24 个文件正好解释了 `383→407`、`378→385`、`5→22`。

另外，从逐文件结果可以补充文档中比较概括的地方：

- [csrc/CMakeLists.txt](csrc/CMakeLists.txt) 实际对应 `csrc/deepep/CMakeLists.txt`，只加了 4 行 include path，不是从上游根 `csrc/CMakeLists.txt` 改写。
- `compile_ascend_proj.sh` 不在文档的迁移表里，但实际被移到 `scripts/` 并重写。
- 根 README 不是从上游根 README 改写，而是从 `python/deep_ep/README.md` 提升。

---

## 7. 值得复核的构建变化

1. 新根 [CMakeLists.txt](CMakeLists.txt) 相比上游精简了编译/链接选项，上游的 `-Wl,-z,noexecstack`、`-Wl,-z,relro`、`-Wl,-z,now`、`-ftrapv` 等 hardening flags 没有保留。
2. `.pre-commit` 删除了 ruff hook，Python 静态检查强度有所下降。
3. 上游 HEAD 就是迁移记录中的 commit，因此这次对比可复现；后续上游前进后，可以按同一映射重新生成差异清单。

---

## 8. 后续同步建议

| 范围 | 建议 |
|---|---|
| `ops/`、`ops2/` | 可直接按上游路径映射同步，当前无差异 |
| `csrc/`（除 `CMakeLists.txt`） | 可直接同步 |
| `python/deep_ep/`（除 `doc/A2_DEEPEP.md`） | 可直接同步 |
| `tests/*.py` | 可直接同步 |
| 根 `build.sh`、`CMakeLists.txt` | 必须手工合并，不能覆盖 |
| `.github/workflows/` | 必须手工合并路径和缓存 key |
| `README.md`、`docs/` | 手工维护 |
