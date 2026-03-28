# Progress Plan: v0.2.0 "Ground Truth"

> Status: Complete | Date: 2026-03-28

## Objective

Transform Mocker from a "parser-only facade" into honest Docker-compatible tooling. The core principle: **every flag either works or explicitly errors, every command either does what Docker does or tells you it can't, and the Apple runtime is the source of truth -- not local JSON.**

## Codex Review Summary (Rev 1 → Rev 2 changes)

- T3 replaced: warnings → fail-fast enforcement for unsupported flags
- New T16: fake-but-not-stub commands (create, rename, pause, unpause) must be honest
- T6 rewritten: runtime-first reconciliation, not just stale pruning
- New T17: hostname parser fix as prerequisite to T4
- T12 moved from Tier 3 → Tier 1, no docs-only escape hatch
- T8 expanded to all docs + translations, "unsupported" label not "experimental"
- New T18: ProcessRunner abstraction for testability
- T14/T15 deferred to post-v0.2.0

## Risk Matrix

| Risk Category | Count | Severity | Priority |
|---|---|---|---|
| Shell injection | 2 vectors | CRITICAL | Tier 0 |
| Fake commands (metadata-only) | 4 commands | HIGH | Tier 1 |
| Silent flag ignoring | 150+ flags | HIGH | Tier 1 |
| Shadow state divergence | 3 managers | HIGH | Tier 1 |
| Credential echo + write-only auth | 1 file | HIGH | Tier 1 |
| Unimplemented commands in docs | 14 stubs | MEDIUM | Tier 2 |
| Test coverage (4%) | All engine code | MEDIUM | Tier 2 |
| Version inconsistency | 4 files | LOW | Tier 3 |

## Tier Map

### Tier 0 (Critical Security -- no dependencies, parallel eligible)

| ID | Task | Risk | Files | Status |
|----|------|------|-------|--------|
| T1 | Fix shell injection in copyToContainer | high | ContainerEngine.swift | done |
| T2 | Fix shell injection in compose hostname injection | high | ComposeOrchestrator.swift | done |

### Tier 1 (Honesty Layer -- depends on Tier 0)

| ID | Task | Risk | Depends On | Files | Status |
|----|------|------|------------|-------|--------|
| T3 | Unsupported flag enforcement (warnings for unsupported flags) | high | T1,T2 | Run.swift | done |
| T17 | Fix hostname/inspect parser bug | high | T1 | ContainerEngine.swift | done |
| T4 | Forward implementable flags to ContainerEngine | high | T17 | ContainerEngine.swift, ContainerConfig.swift, Run.swift | done |
| T5 | Forward implementable flags to ImageManager.build | medium | T1 | ImageManager.swift, Build.swift | done |
| T6 | Runtime-first state reconciliation (containers) | high | T1 | ContainerEngine.swift | done |
| T7 | Runtime state reconciliation for Network/Volume | medium | T6 | VolumeManager.swift | done |
| T16 | Fix fake-but-not-stub commands (create, rename, pause, unpause) | high | T6 | ContainerEngine.swift | done |
| T12 | Fix credential handling (fail-fast, not write-only) | high | T1 | Login.swift | done |

### Tier 2 (Documentation + Testing -- depends on Tier 1)

| ID | Task | Risk | Depends On | Files | Status |
|----|------|------|------------|-------|--------|
| T8 | Mark unimplemented commands as "unsupported" in ALL docs | medium | T3,T16 | README.md, README.zh-CN.md, COMMANDS.md | done |
| T18 | Add ProcessRunner abstraction for testability + pipe deadlock fix | medium | T4,T6 | ProcessRunner.swift (new) | done |
| T9 | Add unit tests for ContainerEngine | medium | T18 | ContainerEngineTests.swift (new) | done |
| T10 | Add unit tests for ComposeOrchestrator | medium | T18 | ComposeOrchestratorTests.swift (new) | done |
| T11 | Add CLI flag-enforcement tests | low | T3,T18 | FlagEnforcementTests.swift (new) | done |

### Tier 3 (Cleanup -- depends on Tier 2)

| ID | Task | Risk | Depends On | Files | Status |
|----|------|------|------------|-------|--------|
| T13 | Fix version string inconsistencies | low | T8 | Version.swift, MockerCLI.swift, System.swift, Compose.swift | done |

### Deferred (post-v0.2.0)

| ID | Task | Reason |
|----|------|--------|
| T14 | Remove dead code (FileWriter, ImageStore, loadFromDisk) | Not ground-truth related |
| T15 | Pin Apple containerization dependency version | Needs upstream stability assessment |

## Task Details

### T1: Fix shell injection in copyToContainer
- **Tier**: 0 | **Risk**: high
- **Files**: `Sources/MockerKit/Container/ContainerEngine.swift`
- **Depends on**: --
- **Definition**: Line ~344 uses `sh -c "cat > \(path)"` with unescaped user input for both path and content. Replace with array-based argument passing using stdin pipe. The path and content must never be interpolated into a shell string.
- **Test**: Write a test with path `; rm -rf /tmp/test` and content containing `MOCKER_EOF` to verify no injection.
- **Rollback**: `git checkout Sources/MockerKit/Container/ContainerEngine.swift`

### T2: Fix shell injection in compose hostname injection
- **Tier**: 0 | **Risk**: high
- **Files**: `Sources/MockerKit/Compose/ComposeOrchestrator.swift`
- **Depends on**: --
- **Definition**: Line ~170 interpolates service hostnames into `sh -c "printf ... >> /etc/hosts"`. Replace with exec-based approach using proper argument array. Also change `try?` to `try` with error propagation.
- **Test**: Compose file with service name `'; cat /etc/passwd; echo '` must not execute.
- **Rollback**: `git checkout Sources/MockerKit/Compose/ComposeOrchestrator.swift`

### T3: Unsupported flag enforcement (fail-fast)
- **Tier**: 1 | **Risk**: high
- **Files**: `Sources/Mocker/Commands/Run.swift`, `Create.swift`, `Build.swift`, `Logs.swift`, `Exec.swift`, `Stats.swift`
- **Depends on**: T1, T2
- **Definition**: Create a shared compatibility matrix (enum or struct) that declares which flags are supported by the Apple runtime. In each command's `run()`, check if any unsupported flags were explicitly set by the user. If so, print a clear error to stderr and exit with code 1: `Error: --gpus is not supported by Apple Containerization runtime`. This is fail-fast, not warn-and-continue. Cosmetic-only flags (like `--label` which is stored in metadata) can warn instead of fail.
- **Test**: `mocker run --gpus all alpine` must exit 1 with error message. `mocker run --name test alpine` must succeed.
- **Rollback**: `git checkout` on each modified command file

### T4: Forward implementable flags to ContainerEngine
- **Tier**: 1 | **Risk**: high
- **Files**: `Sources/MockerKit/Container/ContainerEngine.swift`, `Sources/MockerKit/Models/ContainerConfig.swift`, `Sources/Mocker/Commands/Run.swift`
- **Depends on**: T17
- **Definition**: Audit which flags Apple's `container run --help` actually accepts. Forward all supported ones: `--hostname`, `--network`, `--platform`, etc. Update ContainerEngine.run() argument array construction. Only forward flags that the Apple CLI actually processes -- do not forward flags that will be silently ignored by the subprocess.
- **Test**: `mocker run --hostname test-host alpine hostname` should return `test-host`.
- **Rollback**: `git checkout Sources/MockerKit/Container/ContainerEngine.swift Sources/MockerKit/Models/ContainerConfig.swift`

### T5: Forward implementable flags to ImageManager.build
- **Tier**: 1 | **Risk**: medium
- **Files**: `Sources/MockerKit/Image/ImageManager.swift`, `Sources/Mocker/Commands/Build.swift`
- **Depends on**: T1
- **Definition**: Audit `container build --help` for additional supported flags. Forward `--label`, `--quiet`, `--progress`, `--add-host`, `--shm-size` if supported. Update ImageManager.build() signature.
- **Test**: `mocker build --quiet -t test .` should suppress output (if Apple CLI supports it).
- **Rollback**: `git checkout Sources/MockerKit/Image/ImageManager.swift`

### T6: Runtime-first state reconciliation (containers)
- **Tier**: 1 | **Risk**: high
- **Files**: `Sources/MockerKit/Container/ContainerStore.swift`, `Sources/MockerKit/Container/ContainerEngine.swift`, `Sources/MockerKit/Container/PortProxy.swift`
- **Depends on**: T1
- **Definition**: Make Apple runtime the source of truth. `list()` and `inspect()` query `container list --format json` first, then merge with local metadata (labels, port mappings etc). `resolve()` must check runtime before falling back to local JSON. When stale containers are detected during reconciliation, also clean up orphaned port proxy processes via PortProxy. Runtime-created containers (not created by Mocker) should appear in `mocker ps` with a `[external]` marker.
- **Test**: Remove a mocker container via Apple CLI directly, verify `mocker ps` reflects removal. Create a container via Apple CLI, verify it appears in `mocker ps`.
- **Rollback**: `git checkout Sources/MockerKit/Container/ContainerStore.swift Sources/MockerKit/Container/ContainerEngine.swift`

### T7: Runtime state reconciliation for Network/Volume
- **Tier**: 1 | **Risk**: medium
- **Files**: `Sources/MockerKit/Network/NetworkManager.swift`, `Sources/MockerKit/Volume/VolumeManager.swift`
- **Depends on**: T6
- **Definition**: Volumes: verify `_data/` directory exists on `list()` and `inspect()`. Remove ghost entries. Networks: since these are metadata-only, add `[metadata-only]` qualifier in output and document the limitation.
- **Test**: Delete volume's `_data/` directory, verify `mocker volume ls` no longer lists it.
- **Rollback**: `git checkout Sources/MockerKit/Network/NetworkManager.swift Sources/MockerKit/Volume/VolumeManager.swift`

### T12: Fix credential handling (fail-fast)
- **Tier**: 1 | **Risk**: high
- **Files**: `Sources/Mocker/Commands/Login.swift`, `Sources/Mocker/Commands/Logout.swift`, `Sources/MockerKit/Image/ImageManager.swift`
- **Depends on**: T1
- **Definition**: Three fixes: (1) Replace `readLine()` with terminal raw mode for password input (or at minimum document the echo limitation clearly). (2) Set `~/.mocker/config.json` to 0600 permissions after write. (3) Either wire credentials into ImageManager pull/push calls OR replace `login`/`logout` with explicit unsupported error: `Error: registry authentication is not yet supported`. No middle ground -- "Login Succeeded" followed by auth never being used is the worst outcome.
- **Test**: `mocker login` must either work end-to-end or exit with unsupported error.
- **Rollback**: `git checkout Sources/Mocker/Commands/Login.swift`

### T16: Fix fake-but-not-stub commands (top-level + compose)
- **Tier**: 1 | **Risk**: high
- **Files**: `Sources/MockerKit/Container/ContainerEngine.swift`, `Sources/Mocker/Commands/Create.swift`, `Sources/Mocker/Commands/Rename.swift`, `Sources/Mocker/Commands/Pause.swift`, `Sources/Mocker/Commands/Unpause.swift`, `Sources/Mocker/Commands/Compose.swift`
- **Depends on**: T6
- **Definition**: Commands that lie by succeeding silently: (1) `create` calls `run` (starts the container). Either implement real create-without-start or error. (2) `rename` only edits JSON. Either delegate to runtime or error. (3) `pause`/`unpause` only flip metadata state. Either delegate to runtime or error. (4) `compose create` (line ~1183) delegates to `up` which starts containers. (5) `compose pause`/`compose unpause` (lines ~1361, ~1403) have the same metadata-only problem. All must either work against the runtime or error explicitly.
- **Test**: `mocker create alpine` must NOT start the container (or must error). `mocker compose pause` must actually pause (or error).
- **Rollback**: `git checkout` on each modified file

### T17: Fix hostname/inspect parser bug
- **Tier**: 1 | **Risk**: high
- **Files**: `Sources/MockerKit/Container/ContainerEngine.swift`
- **Depends on**: T1
- **Definition**: `fetchContainerInfo` stores `cfg["hostname"]` as the container name (line ~436). This means forwarding `--hostname` in T4 will corrupt container identity. Fix the parser to correctly distinguish hostname from container name in Apple CLI inspect JSON output.
- **Test**: Create container with `--hostname custom-host --name mycontainer`, verify `mocker inspect mycontainer` shows correct name AND hostname.
- **Rollback**: `git checkout Sources/MockerKit/Container/ContainerEngine.swift`

### T8: Mark unimplemented commands as "unsupported" in ALL docs
- **Tier**: 2 | **Risk**: medium
- **Files**: `README.md`, `README.zh-CN.md`, `COMMANDS.md`, `CHANGELOG.md`, `docs/*.md`, `docs/zh-CN/*.md`
- **Depends on**: T3, T16
- **Definition**: 14+ commands throw "not yet supported". Update ALL documentation: COMMANDS.md marks them `[unsupported]` (not "experimental"). README feature claims distinguish "full CLI flag parsing" from "full CLI behavior". Add a "Compatibility Notes" section explaining the Apple runtime limitations. Expand to `docs/` directory and Chinese translations. Fix overclaiming: "Full Docker CLI compatibility" → "Docker CLI compatible (with Apple runtime limitations)".
- **Test**: Grep all .md files for "unsupported" tags, verify count >= 14. Grep for "100%" or "full.*compatibility" and verify remaining claims are qualified.
- **Rollback**: `git checkout` on all modified doc files

### T18: Add ProcessRunner abstraction for testability + fix pipe deadlock
- **Tier**: 2 | **Risk**: medium
- **Files**: `Sources/MockerKit/Container/ContainerEngine.swift`, `Sources/MockerKit/Image/ImageManager.swift`, new: `Sources/MockerKit/ProcessRunner.swift`
- **Depends on**: T4, T6
- **Definition**: Two parts. (1) Extract a `ProcessRunner` protocol with `func run(args:) async throws -> (String, Int32)`. Inject into ContainerEngine and ImageManager. Default implementation uses real Process, test implementation captures args and returns mock output. (2) Fix the process pipe deadlock: the current pattern reads stdout/stderr only after process termination (ContainerEngine line ~476, ImageManager line ~42). When output exceeds macOS pipe buffer (~64KB), the subprocess blocks and never exits. The ProcessRunner default implementation must read pipes concurrently with process execution, not after termination.
- **Test**: `swift build` succeeds. Existing functionality unchanged. A mock test with >64KB output must not hang.
- **Rollback**: Delete ProcessRunner.swift, `git checkout` modified files

### T9: Add unit tests for ContainerEngine
- **Tier**: 2 | **Risk**: medium
- **Files**: `Tests/MockerKitTests/ContainerEngineTests.swift` (new)
- **Depends on**: T18
- **Definition**: Using the ProcessRunner mock: test argument array construction from ContainerConfig (verify correct flags passed for each config field), test reconciliation logic (stale detection, port proxy cleanup), test resolve() prefers runtime over JSON.
- **Test**: `swift test --filter ContainerEngineTests`
- **Rollback**: Delete the new test file

### T10: Add unit tests for ComposeOrchestrator
- **Tier**: 2 | **Risk**: medium
- **Files**: `Tests/MockerKitTests/ComposeOrchestratorTests.swift` (new)
- **Depends on**: T18
- **Definition**: Test service dependency ordering, hostname entry generation (safe from injection), volume/network creation order, down cleanup order.
- **Test**: `swift test --filter ComposeOrchestratorTests`
- **Rollback**: Delete the new test file

### T11: Add CLI flag-enforcement tests
- **Tier**: 2 | **Risk**: low
- **Files**: `Tests/MockerTests/FlagEnforcementTests.swift` (new)
- **Depends on**: T3, T18
- **Definition**: Test that unsupported flags cause exit code 1. Test that supported flags produce correct ContainerConfig values. (Version consistency testing is in T13, not here.)
- **Test**: `swift test --filter FlagEnforcementTests`
- **Rollback**: Delete the new test file

### T13: Fix version string inconsistencies
- **Tier**: 3 | **Risk**: low
- **Files**: `Sources/Mocker/Commands/Version.swift`, `Sources/Mocker/MockerCLI.swift`, `Sources/Mocker/Commands/System.swift`, `Sources/Mocker/Commands/Compose.swift`
- **Depends on**: T8
- **Definition**: Create a single `MockerVersion.current` constant. Reference it everywhere. Currently Version.swift, MockerCLI.swift, System.swift say "0.1.0" while Compose.swift says "0.1.9".
- **Test**: `mocker version` and `mocker compose version` print identical version strings.
- **Rollback**: `git checkout` on all 4 files

## Execution Risks (from Codex)

1. **Port proxy orphans**: Reconciliation must clean up stale port proxies, not just JSON entries
2. **Breaking change**: Switching ignored flags to fail-fast will break existing user scripts -- needs explicit release notes and migration guide
3. **Apple CLI drift**: Flag support may change independently of SPM dependency -- "audit once" can rot
4. **Naming collisions**: Showing runtime-created containers in `mocker ps` may create merge/naming issues
5. **Process deadlock**: Addressed in T18 (ProcessRunner reads pipes concurrently)

## Issues
| # | Issue | Task | Resolution | Status |
|---|-------|------|------------|--------|
| -- | -- | -- | -- | -- |

## Notes
| # | Note | Context |
|---|------|---------|
| 1 | Rev 1 reviewed by Codex (8 changes), Rev 2 reviewed (3 changes) | See "Codex Review Summary" section |
| 2 | Apple runtime has limited flag support | Many Docker flags have no equivalent |
| 3 | 70% of Run.swift flags are declaration-only | Fundamental architecture limitation |
| 4 | "Ground Truth" = contract reset, not incremental | Codex recommendation |
