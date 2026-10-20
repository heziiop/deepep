# DeepEP extraction audit

This document records how the standalone DeepEP-Ascend repository was derived
from `sgl-project/sgl-kernel-npu` (commit
`a5c12d19fe12dc03aca474852f63cf49f5df8eb2`, dated 2026-10-19), what was kept,
what was intentionally left behind, and how to remove the module from the
upstream repository if desired.

The new repository starts with a fresh initial commit; the upstream provenance is
recorded here rather than carried over as a filtered history.

## Audit method

The audit covered all 1,178 tracked files in the upstream repository:

1. Enumerated every file outside the already-migrated DeepEP paths and searched
   for DeepEP names/symbols (`deep_ep`, `deepep`, `fused_deep_moe`,
   `moe_distribute*`, `dispatch_ffn_combine`, `dispatch_layout`, `notify_dispatch`,
   `cam_moe`, `low_latency_*`, `num_recv_tokens*`, `expert_scales`, ...).
2. Checked the include graph of every migrated C++ source to confirm it does not
   depend on headers outside the DeepEP tree.
3. Built A2/A3/A5 from the new repository without any non-DeepEP `csrc/` sources,
   which proves there is no hidden build-time dependency.
4. Checked for empty placeholder files, hidden config files (`.clang-format`),
   repo-level CI (`lint.yml`) and root configuration.
5. Compared every migrated file against upstream (byte-for-byte except the
   intentional path/build-glue changes listed below).

The resulting standalone repository tracks 409 files.

## Ownership audit

### Migrated (DeepEP-owned)

| Upstream path | New path | Rationale |
|---|---|---|
| `csrc/deepep/*.cpp`, `*.hpp` | `csrc/` | Host-side DeepEP buffer/communication implementation and pybind11 entry point (`deep_ep_cpp`). |
| `csrc/deepep/profiling/` | `csrc/profiling/` | Host-side profiling runtime and the `fused_deep_moe` A5 adapter. |
| `csrc/deepep/ops/` | `ops/` | AscendC operator project for A3/A5 (normal/low-latency dispatch/combine, fused MoE). |
| `csrc/deepep/ops2/` | `ops2/` | AscendC operator project for A2. |
| `csrc/deepep/AddCustom.json` | `ops/AddCustom.json` | `msopgen` template used to scaffold both operator projects. |
| `python/deep_ep/` | `python/deep_ep/` | Python package (`deep_ep`), strategies, API docs and `setup.py`. |
| `tests/python/deepep/` | `tests/` | DeepEP test suite, multi-node/k8s helpers and test runners. |
| `cmake/config_envs.cmake` | `cmake/config_envs.cmake` | Resolves torch/torch_npu/pybind11 paths and the C++ ABI for the host extension. |
| `cmake/config_git_last_commit.cmake` | `cmake/config_git_last_commit.cmake` | Supplies `GIT_LAST_COMMIT` used by the extension. |
| `scripts/enumerate_test_intranode.sh` | `scripts/enumerate_test_intranode.sh` | DeepEP test matrix. |
| `scripts/enumerate_test_low_latency*.sh` | `scripts/enumerate_test_low_latency*.sh` | DeepEP test matrices. |
| `scripts/generalization_test_fused_deep_moe.sh` | `scripts/generalization_test_fused_deep_moe.sh` | DeepEP `fused_deep_moe` generalization test. |
| `scripts/prepare_deepep_in_container.sh` | `scripts/prepare_deepep_in_container.sh` | Build/install helper used by DeepEP CI. |
| `scripts/npu_ci_install_dependency.sh` | `scripts/npu_ci_install_dependency.sh` | Shared CI dependency installer required by the DeepEP workflows. |
| `.github/workflows/pr-test-deepep-npu.yml` | `.github/workflows/pr-test-deepep-npu.yml` | Primary DeepEP PR test workflow (paths adapted). |
| `.github/workflows/internode.yml` | `.github/workflows/internode.yml` | Reusable A2 multi-node workflow (kept for manual validation/future restoration). |
| `.github/workflows/release_deep_ep_wheel.yml` | `.github/workflows/release_deep_ep_wheel.yml` | DeepEP wheel release workflow. |
| `.github/workflows/build_and_release.yml` (DeepEP job) | `.github/workflows/build_and_release.yml` | DeepEP-only A2/A3/A5 wheel build and release (matrix trimmed to DeepEP). |
| `.github/workflows/daily-build-test.yml` | `.github/workflows/daily-build-test.yml` | Daily DeepEP enumerate tests; the whole upstream workflow is DeepEP-specific. |
| `.github/workflows/push_build_cache.yml` | `.github/workflows/push_build_cache.yml` | DeepEP build-cache warmer; cache key aligned with the PR workflow. |
| `.github/workflows/lint.yml` | `.github/workflows/lint.yml` | Repo-wide pre-commit lint; the SGLang-kernel-only unit-test step was removed and a Python syntax check added. |
| `.github/workflows/scripts/wheel/` | `.github/workflows/scripts/wheel/` | Wheel-variant tooling used by the release workflow. |
| `csrc/.clang-format` | `.clang-format` | C++ formatting config consumed by the pre-commit clang-format hook; moved to the repo root so it also covers `ops/` and `ops2/`. |
| `LICENSE` | `LICENSE` | Repository license (MIT, sgl-project). |
| `.pre-commit-config.yaml` | `.pre-commit-config.yaml` | Formatting/lint hooks. |
| `build.sh` (DeepEP parts) | `build.sh` | Rewritten as a standalone, DeepEP-only build driver. |
| `python/deep_ep/README.md` | `README.md` | Full README promoted to the repository root; `python/deep_ep/README.md` keeps a short pointer stub. |

### Deliberately not migrated

| Upstream path | Reason |
|---|---|
| All other `csrc/<kernel>/` directories (attentions, alloc_extend, lora, ...) | SGLang kernel library (`sgl_kernel_npu`), unrelated to DeepEP. The upstream `csrc/CMakeLists.txt` is not copied as-is; a DeepEP-only `csrc/CMakeLists.txt` is provided instead. |
| `csrc/deepep_cmake_build.sh`, `csrc/deepep/build.sh` | Module-dispatch wrappers for the monorepo (`all`/`deepep` selection, dead pybind/UT branches). The standalone `build.sh` invokes the required steps directly. |
| `csrc/deepep/README.md` | Empty (0-byte) upstream file; no content to migrate. |
| `cmake/config_ascend.cmake` | Only needed to build AscendC kernels through the monorepo's top-level CMake project. The operator projects in `ops/` and `ops2/` use CANN's OPP CMake directly. |
| `third_party/catlass`, `third_party/pto-isa` | Git submodules used by SGLang kernels. DeepEP's `ops/build.sh` fetches the Catlass version it needs (A3/A5) at build time. |
| `include/`, `config.ini`, `contrib/torch_memory_saver/` | SGLang-kernel / memory-saver components. |
| `python/sgl_kernel_npu/`, `python/attentions/` | SGLang kernel and attention Python packages. |
| `tests/csrc/`, `tests/python/sgl_kernel_npu/` | SGLang kernel tests. `test_build_targets.py` exercises the monorepo `build.sh` targets (including `deepep`), not DeepEP runtime code. |
| `.github/workflows/pr-test-kernels.yml`, `daily-test-kernels.yml` | SGLang kernel CI (`pr-test-kernels.yml` only mentions `csrc/deepep/**` in a path exclusion). |
| `scripts/prepare_kernel_tests.sh`, `run_kernel_tests.sh`, `scripts/sparsity_driven_kv_offload/` | SGLang kernel / KV-offload test tooling. |
| `benchmark/bench_deepep.py` | Zero-byte placeholder since the initial upstream commit, not referenced by any build, test or doc. An empty file adds no value to the standalone repo. |
| `benchmark/sparsity_driven_kv_offload/` | SGLang kernel benchmarks. |
| `docs/developer_guide/`, `docs/README.md` | Monorepo contribution/documentation workflow; the DeepEP build and test instructions live in `README.md` and `python/deep_ep/doc/`. |
| `.opencode/` | Agent/tooling metadata; contains no DeepEP code or documentation. |
| `config.ini` | Version file consumed by `python/sgl_kernel_npu/setup.py`, not by `deep_ep`. |

## Standalone changes

Only build/packaging glue was changed; DeepEP source code is otherwise kept as-is.

1. **Host extension**: `csrc/CMakeLists.txt` now adds `${PROJECT_SOURCE_DIR}` to its
   include path because host profiling headers include
   `ops/profiling/common/profile_protocol_common_core.h`, which used to resolve
   through the `csrc/deepep/` directory layout.
2. **Root CMake project**: replaces the monorepo top-level project with a
   DeepEP-only project that builds `deep_ep_cpp` and installs it to `output/lib`.
3. **`build.sh`**: standalone driver. Default target is `deepep` (auto-detects
   A2/A3/A5); `-a deepep2` remains as the A2 alias. It performs:
   `compile_ascend_proj.sh` → host CMake build/install → `ops/` or `ops2/`
   package build/install → wheel build.
4. **`scripts/compile_ascend_proj.sh`**: repo-root-relative replacement for
   `csrc/deepep/compile_ascend_proj.sh`. It generates the OPP scaffolding with
   `msopgen` into `build/opp_gen/` and copies `CMakePresets.json` (and `cmake/`
   when the CANN release emits it) into `ops/` or `ops2/`.
5. **Tests**: moved from `tests/python/deepep/` to `tests/`; runners and k8s
   templates use the new paths. Tests themselves are unchanged.
6. **CI**: workflow paths, change-detection groups, cache keys and runner
   namespace names were updated for the standalone layout.
7. **Build hygiene**: `cmake/config_git_last_commit.cmake` now runs `git` in
   `${PROJECT_SOURCE_DIR}`; `build.sh` removes stale `deep_ep_cpp*.so` files
   before packaging; the pre-commit `ruff` hook was dropped because it only
   targeted the non-migrated `benchmark/`, `docs/` and `examples/` trees.
8. **CMake flags**: the root project keeps the release flags needed by the
   extension (`-O3`, visibility, stack protector, `-fPIC`). The monorepo-wide
   warning/linker hardening flags from the old top-level project were not
   carried over; they are not required by `deep_ep_cpp`.

## Removing DeepEP from `sgl-kernel-npu` (not applied here)

The source repository was left untouched. To complete the split there:

1. Delete `csrc/deepep/`, `csrc/deepep_cmake_build.sh`, `python/deep_ep/`,
   `tests/python/deepep/`, the DeepEP test scripts under `scripts/`, and
   `.github/workflows/pr-test-deepep-npu.yml`, `internode.yml`,
   `release_deep_ep_wheel.yml`, `daily-build-test.yml`, `push_build_cache.yml`,
   `.github/workflows/scripts/wheel/`. In the mixed `build_and_release.yml`,
   delete only the DeepEP build steps.
2. In `CMakeLists.txt`, remove `BUILD_DEEPEP_MODULE` and
   `add_subdirectory(csrc/deepep)`.
3. In `csrc/CMakeLists.txt`, drop the two `csrc/deepep/ops/op_kernel` include
   directories passed to `no_workspace_kernel` (no SGLang kernel source includes
   those headers).
4. In `build.sh`, remove the `deepep`/`deepep2` targets, `prepare_deepep_build`,
   `build_deepep_kernels`, `make_deepep_package`, and the DeepEP branches of
   `configure_soc_version`.
5. Remove DeepEP entries from `.gitignore` and DeepEP references from `README.md`
   and `docs/`.

## Verification performed

Environment used: x86_64, CANN 9.1.0, Python 3.12, torch 2.10 / torch_npu 2.10,
no NPU device present (`npu-smi` unavailable), so device execution was not run.

| Check | Result |
|---|---|
| `bash build.sh -a deepep Ascend910_9382` (A3 end-to-end) | Passed; produced `output/deep_ep-*.whl`. |
| `bash build.sh -a deepep2` (A2 end-to-end) | Passed; wheel contains `ascend910b` operator kernels. |
| `bash build.sh -a deepep Ascend950` (A5 end-to-end) | Passed; wheel contains `ascend950` operator kernels. |
| `import deep_ep` from the installed A3 wheel | Passed; `Buffer`, `Config`, `EventOverlap`, strategies load. |
| `import deep_ep_cpp` smoke test | Passed; `get_low_latency_rdma_size_hint` callable. |
| Source parity vs upstream | 383 mapped DeepEP files present; 378 byte-identical, 5 differ only in path/build glue (`csrc/CMakeLists.txt`, `python/deep_ep/README.md`, `python/deep_ep/doc/A2_DEEPEP.md`, `tests/k8s_multi.yaml.jinja2`, `tests/run_ascend_testcase.sh`); 0 missing. |
| Test migration | All 25 files from `tests/python/deepep/` present under `tests/`. |
| Workflow YAML syntax | All seven migrated workflows parse successfully. |

Notes:

- `ops2/CMakePresets.json` is a tracked default preset. `scripts/compile_ascend_proj.sh`
  regenerates it for the target SoC during every build, so a local build may show
  it as modified (this matches the previous monorepo behaviour).
- `ops2/op_kernel/moe_distribute_comm_ctx.h` is copied from CANN at configure time
  and is git-ignored.
- Device tests (`tests/test_*.py`) require an actual A2/A3/A5 NPU and were not run
  here; their code is unchanged apart from path references in the wrappers.
