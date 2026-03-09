# 📋 Progress Plan: Direct Containerization Framework Integration

> Created: 2026-03-07 | Status: ✅ Investigation Complete | Completed: 12/12

## 🎯 Objective
`container` CLI subprocess yaklaşımını tamamen kaldırıp Apple'ın `Containerization` framework'ünü direkt kullanmak.
`LinuxContainer` / `ContainerManager` API'si ile native container lifecycle yönetimi.

## Neden Mümkün?
- `com.apple.security.virtualization` entitlement'ı ad-hoc sign ile macOS 26'da ÇALIŞIYOR (Apple'ın kendi Makefile'ı da bunu yapıyor)
- `ghcr.io/apple/containerization/vminit:0.1.0` public registry'de mevcut
- Kernel: `~/Library/Application Support/com.apple.container/kernels/default.kernel-arm64`

## 📊 Progress Overview
- Total tasks: 12
- Completed: 0
- In Progress: 0
- Remaining: 12

---

## Tasks

### Phase 1: Foundation

- [ ] **Task 1.1**: Pull `vminit:0.1.0` into OCI store
  - Files: `Sources/MockerKit/Image/ImageManager.swift`
  - Details: `mocker pull ghcr.io/apple/containerization/vminit:0.1.0` — ensure it's in `~/.mocker/oci-store/`

- [ ] **Task 1.2**: Update `MockerConfig` with kernel path & vminit ref
  - Files: `Sources/MockerKit/Config/MockerConfig.swift`
  - Details: `kernelURL`, `vminitReference`, `logsPath` properties ekle

- [ ] **Task 1.3**: Implement `FileWriter: Writer` for container logs
  - Files: New `Sources/MockerKit/Container/FileWriter.swift`
  - Details: `Containerization.Writer` protocol'ü implement eden, stdout/stderr'i log dosyasına yazan type

### Phase 2: ContainerEngine Rewrite

- [ ] **Task 2.1**: `ContainerEngine` actor'ını `ContainerManager` kullanacak şekilde yeniden yaz
  - Files: `Sources/MockerKit/Container/ContainerEngine.swift`
  - Details: `var manager: ContainerManager`, `var live: [String: LinuxContainer]` in-memory map

- [ ] **Task 2.2**: `run()` — `ContainerManager.create()` + `container.start()`
  - Files: `Sources/MockerKit/Container/ContainerEngine.swift`
  - Details: env vars, volumes, workdir, hostname, hosts injection for compose

- [ ] **Task 2.3**: `stop()` — `container.stop()`
  - Files: `Sources/MockerKit/Container/ContainerEngine.swift`
  - Details: live container'ı bul, stop et, store'u güncelle

- [ ] **Task 2.4**: `remove()` — `manager.delete()` + `store.delete()`
  - Files: `Sources/MockerKit/Container/ContainerEngine.swift`
  - Details: force flag ile running container durdur ve sil

- [ ] **Task 2.5**: `exec()` — `container.exec()`
  - Files: `Sources/MockerKit/Container/ContainerEngine.swift`
  - Details: LinuxProcess oluştur, stdout/stderr'i terminale bağla

- [ ] **Task 2.6**: `logs()` — log dosyasını oku
  - Files: `Sources/MockerKit/Container/ContainerEngine.swift`
  - Details: `~/.mocker/logs/<id>.log` dosyasını oku

- [ ] **Task 2.7**: `list()` — live containers + store sync
  - Files: `Sources/MockerKit/Container/ContainerEngine.swift`
  - Details: in-memory map'ten canlı container durumlarını al

- [ ] **Task 2.8**: `stats()` — `container.statistics()`
  - Files: `Sources/MockerKit/Container/ContainerEngine.swift`
  - Details: Native CPU/memory stats

### Phase 3: Build, Sign & Test

- [ ] **Task 3.1**: `swift build` + `codesign` ile derleme
  - Details: `codesign --force --sign - --timestamp=none --entitlements Entitlements.plist .build/debug/mocker`

- [ ] **Task 3.2**: End-to-end test
  - Details: `mocker pull alpine`, `mocker run -d alpine sleep 60`, `mocker ps`, `mocker stop`, `mocker rm`

---

## 📝 Notes & Decisions
| # | Note | Date |
|---|------|------|
| 1 | Ad-hoc sign + VM entitlement works on macOS 26 (Apple's own Makefile does this) | 2026-03-07 |
| 2 | vminit image at ghcr.io/apple/containerization/vminit:0.1.0 (from state.json) | 2026-03-07 |
| 3 | ContainerManager stores rootfs.ext4 per container in imageStorePath/containers/<id>/ | 2026-03-07 |
| 4 | LinuxContainer.Configuration.hosts allows injecting /etc/hosts at creation time (better than exec hack) | 2026-03-07 |
| 5 | ContainerManager.create() is mutating — OK as actor var | 2026-03-07 |
| 6 | vminit:0.1.0 (Apple CLI) uses DIFFERENT gRPC protocol than framework main branch (0.26.x) | 2026-03-07 |
| 7 | Direct integration requires building vminitd from source OR pinning framework to match CLI | 2026-03-07 |
| 8 | CLI subprocess approach is most reliable until Apple publishes compatible vminit for 0.26.x | 2026-03-07 |

## 🐛 Issues Encountered
| # | Issue | Status | Resolution |
|---|-------|--------|------------|
| - | - | - | - |

## ➕ Added Tasks (discovered during execution)
- [x] **Task 4.1**: Implement `--env-file` support in `mocker run`
  - Details: Parse `.env` files, ignore comments/empty lines, and ensure `-e` overrides take precedence.
