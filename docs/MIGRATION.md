# DeepEP 拆分审计

本文件记录独立 DeepEP-Ascend 仓库是如何从 `sgl-project/sgl-kernel-npu`（commit
`a5c12d19fe12dc03aca474852f63cf49f5df8eb2`，2026-10-19）中拆分出来的：保留了
哪些内容、有意舍弃了哪些内容，以及如需在上游仓库中移除该模块应当怎么做。

新仓库从一次全新的 initial commit 开始；上游来源记录在此，而不是以过滤历史的
方式保留。

## 审计方法

审计覆盖上游仓库全部 1,178 个 tracked 文件：

1. 枚举已迁移 DeepEP 路径之外的所有文件，并搜索 DeepEP 相关名称/符号
   （`deep_ep`、`deepep`、`fused_deep_moe`、`moe_distribute*`、
   `dispatch_ffn_combine`、`dispatch_layout`、`notify_dispatch`、`cam_moe`、
   `low_latency_*`、`num_recv_tokens*`、`expert_scales` 等）。
2. 检查每个已迁移 C++ 源文件的 include 图，确认它不依赖 DeepEP 目录之外的
   任何头文件。
3. 在完全不包含非 DeepEP `csrc/` 源码的情况下，从新仓库构建 A2/A3/A5，
   以此证明不存在隐藏的构建期依赖。
4. 检查空占位文件、隐藏配置文件（`.clang-format`）、仓库级 CI（`lint.yml`）
   与根配置。
5. 把每个已迁移文件与上游逐一对比（除下文列出的路径/构建胶水改动外，逐字节
   相同）。

最终独立仓库跟踪 409 个文件。逐文件对比结果——哪些目录原样复制、哪些文件有
改动、哪些是新增——记录在 [UPSTREAM_DIFF.md](UPSTREAM_DIFF.md)。

## 归属审计

### 已迁移（属 DeepEP）

| 上游路径 | 新路径 | 依据 |
|---|---|---|
| `csrc/deepep/*.cpp`、`*.hpp` | `csrc/runtime/` | Host 侧 DeepEP buffer/通信实现与 pybind11 入口（`deep_ep_cpp`）。 |
| `csrc/deepep/profiling/` | `csrc/runtime/profiling/` | Host 侧 profiling runtime 与 `fused_deep_moe` A5 adapter。 |
| `csrc/deepep/ops/` | `csrc/ops/` | A3/A5 的 AscendC 算子工程（normal/low-latency dispatch/combine、fused MoE）。 |
| `csrc/deepep/ops2/` | `csrc/ops2/` | A2 的 AscendC 算子工程。 |
| `csrc/deepep/AddCustom.json` | `scripts/templates/opp_scaffold.json` | 用于生成两个算子工程脚手架的 `msopgen` 模板。 |
| `python/deep_ep/` | `python/deep_ep/` | Python 包（`deep_ep`）、策略、API 文档与 `setup.py`。 |
| `tests/python/deepep/` | `tests/` | DeepEP 测试套件、多机/k8s 辅助脚本与测试 runner。 |
| `cmake/config_envs.cmake` | `csrc/runtime/cmake/config_envs.cmake` | 解析 torch/torch_npu/pybind11 路径与 host 扩展的 C++ ABI。 |
| `cmake/config_git_last_commit.cmake` | `csrc/runtime/cmake/config_git_last_commit.cmake` | 提供扩展使用的 `GIT_LAST_COMMIT`。 |
| `scripts/enumerate_test_intranode.sh` | `scripts/enumerate_test_intranode.sh` | DeepEP 测试矩阵。 |
| `scripts/enumerate_test_low_latency*.sh` | `scripts/enumerate_test_low_latency*.sh` | DeepEP 测试矩阵。 |
| `scripts/generalization_test_fused_deep_moe.sh` | `scripts/generalization_test_fused_deep_moe.sh` | DeepEP `fused_deep_moe` 泛化测试。 |
| `scripts/prepare_deepep_in_container.sh` | `scripts/prepare_deepep_in_container.sh` | DeepEP CI 使用的构建/安装辅助脚本。 |
| `scripts/npu_ci_install_dependency.sh` | `scripts/npu_ci_install_dependency.sh` | DeepEP workflow 依赖的共享 CI 依赖安装脚本。 |
| `.github/workflows/pr-test-deepep-npu.yml` | `.github/workflows/pr-test-deepep-npu.yml` | 主要的 DeepEP PR 测试 workflow（路径已适配）。 |
| `.github/workflows/internode.yml` | `.github/workflows/internode.yml` | 可复用的 A2 多机 workflow（保留用于人工验证/后续恢复）。 |
| `.github/workflows/release_deep_ep_wheel.yml` | `.github/workflows/release_deep_ep_wheel.yml` | DeepEP wheel 发布 workflow。 |
| `.github/workflows/build_and_release.yml`（DeepEP 部分） | `.github/workflows/build_and_release.yml` | 仅保留 DeepEP 的 A2/A3/A5 wheel 构建与发布（矩阵裁剪为 DeepEP）。 |
| `.github/workflows/daily-build-test.yml` | `.github/workflows/daily-build-test.yml` | DeepEP 每日 enumerate 测试；上游该 workflow 整体就是 DeepEP 专用。 |
| `.github/workflows/push_build_cache.yml` | `.github/workflows/push_build_cache.yml` | DeepEP 构建缓存预热；cache key 与 PR workflow 对齐。 |
| `.github/workflows/lint.yml` | `.github/workflows/lint.yml` | 仓库级 pre-commit lint；去掉了仅针对 SGLang kernel 的单测步骤，增加了 Python 语法检查。 |
| `.github/workflows/scripts/wheel/` | `.github/workflows/scripts/wheel/` | release workflow 使用的 wheel 变体工具。 |
| `csrc/.clang-format` | `.clang-format` | pre-commit clang-format hook 使用的 C++ 格式配置；移到仓库根，以便同时覆盖 `csrc/ops/` 与 `csrc/ops2/`。 |
| `LICENSE` | `LICENSE` | 仓库许可证（MIT，sgl-project）。 |
| `.pre-commit-config.yaml` | `.pre-commit-config.yaml` | 格式化/lint hooks。 |
| `build.sh`（DeepEP 部分） | `build.sh` | 重写为独立的、仅构建 DeepEP 的构建驱动。 |
| `python/deep_ep/README.md` | `README.md` | 完整 README 提升为仓库根 README；`python/deep_ep/README.md` 保留简短指针。 |

### 有意不迁移

| 上游路径 | 原因 |
|---|---|
| 其他 `csrc/<kernel>/` 目录（attentions、alloc_extend、lora 等） | 属于 SGLang kernel 库（`sgl_kernel_npu`），与 DeepEP 无关。上游 `csrc/CMakeLists.txt` 未原样复制，改用 DeepEP 专用的 `csrc/runtime/CMakeLists.txt`。 |
| `csrc/deepep_cmake_build.sh`、`csrc/deepep/build.sh` | monorepo 的模块分发 wrapper（`all`/`deepep` 选择、失效的 pybind/UT 分支）。独立 `build.sh` 直接调用所需步骤。 |
| `csrc/deepep/README.md` | 上游为 0 字节空文件，无内容可迁。 |
| `cmake/config_ascend.cmake` | 仅用于通过 monorepo 顶层 CMake 工程构建 AscendC kernel。`csrc/ops/` 与 `csrc/ops2/` 的算子工程直接使用 CANN 的 OPP CMake。 |
| `third_party/catlass`、`third_party/pto-isa` | SGLang kernel 使用的 git submodule。DeepEP 的 `csrc/ops/build.sh` 在构建时拉取所需的 Catlass 版本（A3/A5）。 |
| `include/`、`config.ini`、`contrib/torch_memory_saver/` | SGLang kernel / memory-saver 组件。 |
| `python/sgl_kernel_npu/`、`python/attentions/` | SGLang kernel 与 attention Python 包。 |
| `tests/csrc/`、`tests/python/sgl_kernel_npu/` | SGLang kernel 测试。`test_build_targets.py` 验证的是 monorepo `build.sh` 的目标（含 `deepep`），不是 DeepEP 运行时代码。 |
| `.github/workflows/pr-test-kernels.yml`、`daily-test-kernels.yml` | SGLang kernel CI（`pr-test-kernels.yml` 只在 path exclusion 中提到 `csrc/deepep/**`）。 |
| `scripts/prepare_kernel_tests.sh`、`run_kernel_tests.sh`、`scripts/sparsity_driven_kv_offload/` | SGLang kernel / KV-offload 测试工具。 |
| `benchmark/bench_deepep.py` | 自上游 initial commit 起就是 0 字节占位文件，未被任何构建、测试或文档引用。空文件对独立仓库没有价值。 |
| `benchmark/sparsity_driven_kv_offload/` | SGLang kernel benchmark。 |
| `docs/developer_guide/`、`docs/README.md` | monorepo 的贡献/文档流程；DeepEP 的构建与测试说明在 `README.md` 与 `python/deep_ep/doc/` 中。 |
| `.opencode/` | agent/工具元数据，不含任何 DeepEP 代码或文档。 |
| `config.ini` | 版本文件，被 `python/sgl_kernel_npu/setup.py` 使用，`deep_ep` 不使用。 |

## 独立仓库相对上游的改动

只改了构建/打包胶水，DeepEP 源码其余部分保持原样。

1. **Host 扩展**：`csrc/runtime/CMakeLists.txt` 把 `${DEEPEP_REPO_ROOT}/csrc`
   加入 include path，因为 host profiling 头文件以
   `"ops/profiling/common/profile_protocol_common_core.h"` 的形式引用，该路径
   现在解析到 `csrc/ops/` 下。
2. **Host CMake 工程**：`csrc/runtime/CMakeLists.txt` 现在是 host 顶层工程，
   原来根 `CMakeLists.txt` 的配置已并入其中。它构建 `deep_ep_cpp` 并安装到
   `output/lib`。
3. **`build.sh`**：独立驱动脚本。默认目标为 `deepep`（自动识别 A2/A3/A5）；
   `-a deepep2` 保留为 A2 别名。执行顺序为：
   `prepare_opp_scaffold.sh` → host CMake 构建/安装（`csrc/runtime`）→
   `csrc/ops/` 或 `csrc/ops2/` 算子包构建/安装 → wheel 打包。
4. **`scripts/prepare_opp_scaffold.sh`**：`csrc/deepep/compile_ascend_proj.sh`
   的仓库根相对版本。它用 `msopgen` 把 OPP 脚手架生成到 `build/opp_gen/`，
   再把 `CMakePresets.json`（以及 CANN 会输出时的 `cmake/`）拷入
   `csrc/ops/` 或 `csrc/ops2/`。msopgen 种子模板移到
   `scripts/templates/opp_scaffold.json`。
5. **测试**：从 `tests/python/deepep/` 移到 `tests/`；runner 与 k8s 模板改用新
   路径。测试自身未改动。
6. **CI**：workflow 路径、change-detection 分组、cache key 与 runner
   namespace 按独立仓库布局更新。
7. **构建卫生**：`csrc/runtime/cmake/config_git_last_commit.cmake` 改在
   `DEEPEP_REPO_ROOT` 中执行 `git`；`build.sh` 在 host 构建前清理
   `output/lib` 中残留的 `deep_ep_cpp*.so`，并在打包前清理源码目录中的同名
   文件，避免 wheel 里出现多个 Python ABI 的模块；删除 pre-commit 的
   `ruff` hook，因为它只针对未迁移的 `benchmark/`、`docs/` 与 `examples/` 目录。
8. **CMake flags**：`csrc/runtime/CMakeLists.txt` 逐字保留上游顶层工程的编译
   选项（`-O3`、符号可见性、stack protector、`-fPIC`/`-fPIE`、`-ftrapv`、`-s`
   以及告警 flags），使 host 扩展的编译命令行与上游一致；差异只在 CMake 工程
   结构（原顶层工程并入 `csrc/runtime`）。

## 从 `sgl-kernel-npu` 中移除 DeepEP（未在本仓库执行）

上游源码仓库未被改动。若要在上游完成拆分，需要：

1. 删除 `csrc/deepep/`、`csrc/deepep_cmake_build.sh`、`python/deep_ep/`、
   `tests/python/deepep/`、`scripts/` 下的 DeepEP 测试脚本，以及
   `.github/workflows/pr-test-deepep-npu.yml`、`internode.yml`、
   `release_deep_ep_wheel.yml`、`daily-build-test.yml`、`push_build_cache.yml`、
   `.github/workflows/scripts/wheel/`。在混合的 `build_and_release.yml` 中只
   删除 DeepEP 相关步骤。
2. 在 `CMakeLists.txt` 中删除 `BUILD_DEEPEP_MODULE` 与
   `add_subdirectory(csrc/deepep)`。
3. 在 `csrc/CMakeLists.txt` 中删除传给 `no_workspace_kernel` 的两个
   `csrc/deepep/ops/op_kernel` include 目录（没有 SGLang kernel 源文件引用
   这些头文件）。
4. 在 `build.sh` 中删除 `deepep`/`deepep2` 目标、`prepare_deepep_build`、
   `build_deepep_kernels`、`make_deepep_package`，以及 `configure_soc_version`
   中的 DeepEP 分支。
5. 从 `.gitignore` 中删除 DeepEP 条目，并从 `README.md` 与 `docs/` 中删除
   DeepEP 相关内容。

## 已执行的验证

验证环境：x86_64、CANN 9.1.0、Python 3.12、torch 2.10 / torch_npu 2.10；机器上
没有 NPU 设备（`npu-smi` 不可用），因此未做设备端执行。

| 检查项 | 结果 |
|---|---|
| `bash build.sh -a deepep Ascend910_9382`（A3 端到端） | 通过；产出 `output/deep_ep-*.whl`。 |
| `bash build.sh -a deepep2`（A2 端到端） | 通过；wheel 含 `ascend910b` 算子。 |
| `bash build.sh -a deepep Ascend950`（A5 端到端） | 通过；wheel 含 `ascend950` 算子。 |
| 从已安装的 A3 wheel 执行 `import deep_ep` | 通过；`Buffer`、`Config`、`EventOverlap`、策略均可加载。 |
| `import deep_ep_cpp` 冒烟测试 | 通过；`get_low_latency_rdma_size_hint` 可调用。 |
| 与上游的源码一致性 | 404 个映射文件全部存在；385 个逐字节一致，19 个仅因路径/构建胶水与 CI 适配而不同；0 缺失（2 个上游文件有意不迁移）。详见 [UPSTREAM_DIFF.md](UPSTREAM_DIFF.md)。 |
| 测试迁移 | `tests/python/deepep/` 下 25 个文件全部出现在 `tests/` 中。 |
| workflow YAML 语法 | 迁移的 7 个 workflow 全部解析成功。 |

说明：

- `csrc/ops2/CMakePresets.json` 是 tracked 的默认 preset。
  `scripts/prepare_opp_scaffold.sh` 在每次构建时按目标 SoC 重新生成它，因此本地
  构建后可能显示为已修改（这与原 monorepo 的行为一致）。
- `csrc/ops2/op_kernel/moe_distribute_comm_ctx.h` 在 configure 阶段从 CANN
  复制而来，已被 git 忽略。
- 设备测试（`tests/test_*.py`）需要实际 A2/A3/A5 NPU，此处未运行；除 wrapper
  中的路径引用外，测试代码未改动。
