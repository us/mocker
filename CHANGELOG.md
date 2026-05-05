# Changelog

All notable changes to Mocker are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1](https://github.com/us/mocker/compare/v0.3.0...v0.3.1) (2026-05-05)


### Bug Fixes

* **manifest:** orphan blob safety, CLI UX, and version sync ([a27f94d](https://github.com/us/mocker/commit/a27f94da31745a732396ad11d4450862056b9702))

## [0.3.0](https://github.com/us/mocker/compare/v0.2.1...v0.3.0) (2026-05-05)


### ⚠ BREAKING CHANGES

* **build:** MockerKit consumers calling `ImageManager.build(platform:)` must migrate to `platforms:`.

### Features

* **build:** support multi-platform builds via repeated --platform ([685979b](https://github.com/us/mocker/commit/685979bc442561b424b18e56a887df86dc181d44))
* **config:** auto-detect Apple container CLI store ([941ea6b](https://github.com/us/mocker/commit/941ea6bf4a839cce84f0e0ee4a3669422c95314a))
* **manifest:** add 'manifest add', 'rm', and 'push' subcommands ([b6fa46a](https://github.com/us/mocker/commit/b6fa46a3b3e1fa418f7727cc6ee66000fb197866))
* **manifest:** add 'mocker manifest annotate' for platform metadata overrides ([3d7f7a9](https://github.com/us/mocker/commit/3d7f7a93c63177effcc3b9f6fb080d7a6030eab5))
* **manifest:** add 'mocker manifest create' to assemble OCI image indexes ([a62312d](https://github.com/us/mocker/commit/a62312dd981eed62ebb5555443d854f52f13e129))
* **manifest:** add 'mocker manifest inspect' for OCI image indexes ([d051edb](https://github.com/us/mocker/commit/d051edb2c3c1370de0b30b71d28ded84869689c5))


### Bug Fixes

* **image:** wire --platform through pull/push and drop hardcoded arm64 ([148d045](https://github.com/us/mocker/commit/148d0453f4d271c88dbd46c7fd9de4cee29952d6))

## [0.2.1](https://github.com/us/mocker/compare/v0.2.0...v0.2.1) (2026-04-25)


### Features

* add nested virtualization support for run/create ([85362fa](https://github.com/us/mocker/commit/85362fa5599707550a671d07f40a24fe0b1c30a5)), closes [#4](https://github.com/us/mocker/issues/4)

## [0.2.0] - 2026-03-28

### Added
- Forward Apple CLI flags in `mocker run`: `-i`, `-t`, `-c`, `-m`, `--label`, `--cidfile`, `--rm`, `--tmpfs`, `--dns-search`, `--dns-option`, `--platform`
- Forward Apple CLI flags in `mocker build`: `--label`, `--quiet`, `--progress`, `--output`
- `ProcessRunner` protocol and `MockProcessRunner` actor for testability
- 16 new tests (42 total, was 26): `ContainerEngine`, `ComposeOrchestrator`, and flag enforcement coverage

### Changed
- **BREAKING:** `mocker create`, `rename`, `pause`, `unpause` now return explicit unsupported errors instead of silently mutating local metadata
- **BREAKING:** `mocker login` / `logout` now return unsupported error (credentials were never consumed by pull/push)
- Unsupported flags in `mocker run` now produce stderr warnings
- Hostname parser now uses the assigned name instead of the inspect hostname field
- All version strings unified via `Version.currentVersion`
- Volume list prunes stale entries where `_data/` directory no longer exists
- Feature claims qualified across READMEs ("Docker CLI compatible" not "full compatibility")
- 12 commands marked `[unsupported]` in COMMANDS.md

### Security
- Fix shell injection in `copyToContainer` — replaced `sh -c` with stdin pipe to `tee`
- Fix shell injection in compose hostname injection — same pattern
- Fix pipe-buffer deadlock in both paths (async `terminationHandler` instead of blocking `waitUntilExit`)

## [0.1.9] - 2026-03-14

### Added
- **Full Docker CLI flag compatibility** across all 111 commands/subcommands
- `mocker commit` command with `--author`, `--change`, `--message`, `--no-pause`
- `mocker container prune` command with `--filter`, `--force`
- `mocker container export` (moved under `container` subcommand group)
- `mocker image rm` command with `--force`, `--no-prune`, `--platform`
- `mocker image inspect` command with `--format`, `--platform` and JSON output
- `mocker image prune` command with `--all`, `--filter`, `--force`
- `mocker run` / `mocker create`: added ~50 Docker-compatible flags including `--attach`, `--cpu-shares`, `--publish-all`, `--quiet`, `--sig-proxy`, `--oom-kill-disable`, `--annotation`, `--blkio-weight`, `--cap-add/drop`, `--cgroup-parent`, `--cgroupns`, `--cidfile`, `--cpus`, `--device`, `--dns`, `--entrypoint`, `--gpus`, `--health-cmd`, `--init`, `--ipc`, `--link`, `--log-driver`, `--mac-address`, `--memory`, `--network-alias`, `--pid`, `--platform`, `--privileged`, `--read-only`, `--restart`, `--runtime`, `--security-opt`, `--shm-size`, `--stop-signal`, `--stop-timeout`, `--storage-opt`, `--sysctl`, `--tmpfs`, `--ulimit`, `--userns`, `--volumes-from`, `--workdir`
- `mocker build`: added ~25 BuildKit/Buildx flags including `--add-host`, `--allow`, `--annotation`, `--attest`, `--build-context`, `--builder`, `--cache-from`, `--cache-to`, `--call`, `--cgroup-parent`, `--check`, `--iidfile`, `--load`, `--metadata-file`, `--no-cache-filter`, `--output`, `--progress`, `--provenance`, `--push`, `--sbom`, `--secret`, `--shm-size`, `--ssh`, `--ulimit`
- `mocker update`: added `--blkio-weight`, `--cpu-period`, `--cpu-quota`, `--cpu-rt-period`, `--cpu-rt-runtime`, `--cpuset-cpus`, `--cpuset-mems`, `--memory-reservation`, `--memory-swap`
- `mocker history` / `mocker save` / `mocker load` / `mocker import`: added `--platform`
- `mocker images`: added `--tree`
- Network commands: added `--alias`, `--driver-opt`, `--gw-priority`, `--ip`, `--ip6`, `--link`, `--link-local-ip` to `network connect`; added `--attachable`, `--aux-address`, `--config-from`, `--config-only`, `--ingress`, `--internal`, `--ip-range`, `--ipam-driver`, `--ipam-opt`, `--ipv4`, `--ipv6`, `--label`, `--opt`, `--scope` to `network create`; added `--force` to `network disconnect/rm`; added `--format`, `--verbose` to `network inspect`
- Volume commands: added `--label`, `--opt` to `volume create`; added `--format` to `volume inspect`; added `--force` to `volume rm`
- System commands: added `--format` to `system info`; added `--filter` to `system prune`
- Compose: added ~200+ flags across 22 subcommands for full Docker Compose CLI compatibility
- `COMMANDS.md` — comprehensive reference of all 111 supported commands and flags

## [0.1.8] - 2026-03-09

### Added
- `--env-file` flag support for `mocker run` — load environment variables from file

### Fixed
- Homebrew tap commit author and runner configuration (macOS 26)

### CI
- Added PR test workflow with macOS 26 runner

## [0.1.7] - 2026-03-08

### Added
- AGPL-3.0 license
- "Replace docker with mocker" quick-start section in README
- `--rm` flag for `mocker run` — auto-remove container on exit
- MenuBar GUI marked as "coming soon" in docs

### Fixed
- `compose.yaml` and `compose.yml` now recognized as default compose file names (in addition to `docker-compose.yml`)
- Compose variable substitution (`${VAR:-default}`) now resolves correctly
- Named volumes now skip virtiofs bind mount for compatibility
- Container remove stop timeout fixed for faster cleanup

### Changed
- Documentation redesigned with den-style frontmatter and clean formatting

## [0.1.6] - 2026-03-08

### Fixed
- Named volumes now resolve to correct host paths for compose services

## [0.1.5] - 2026-03-08

### Fixed
- Relative build context paths now resolve against CWD correctly

## [0.1.4] - 2026-03-08

### Fixed
- `container build` now always passes `-f` flag to use correct Dockerfile from build context directory

## [0.1.3] - 2026-03-08

### Added
- `compose kill` subcommand
- `--timeout` / `-t` flag for `compose down`

## [0.1.2] - 2026-03-08

### Added
- `compose up` now accepts service names to start specific services
- `compose down` now supports `--remove-orphans` and `--volumes` flags

## [0.1.1] - 2026-03-08

### Added
- Homebrew installation support (`brew tap us/tap && brew install mocker`)
- Release workflow — automated binary builds and homebrew formula updates

### Changed
- Centered header in README

## [0.1.0] - 2026-03-07

### Added
- Initial release of Mocker
- **Container lifecycle**: `run`, `create`, `start`, `stop`, `restart`, `rm`, `kill`, `pause`, `unpause`, `rename`, `wait`, `attach`
- **Container inspection**: `ps`, `inspect`, `logs`, `stats`, `top`, `port`, `diff`, `export`
- **Image management**: `pull`, `push`, `build`, `images`, `tag`, `rmi`, `save`, `load`, `import`, `history`, `search`
- **Network management**: `network create/ls/rm/inspect/connect/disconnect`
- **Volume management**: `volume create/ls/rm/inspect`
- **System**: `system info`, `system prune`, `version`, `events`
- **Docker Compose v2**: `up`, `down`, `ps`, `logs`, `restart`, `build`, `pull`, `push`, `config`, `exec`, `run`, `stop`, `start`, `kill`, `rm`, `pause`, `unpause`, `top`, `events`, `images`, `port`, `cp`
- Real container execution via Apple Containerization framework
- `mocker build` with live streaming output via `container build`
- `mocker stats` — real CPU/memory from VirtualMachine.xpc process
- Port mapping (`-p`) via userspace TCP proxy subprocess
- Inter-service hostname injection for compose networking
- Docker-style short image reference normalization
- JSON state persistence in `~/.mocker/`
- Swift 6 actor-based concurrency throughout

[0.1.9]: https://github.com/us/mocker/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/us/mocker/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/us/mocker/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/us/mocker/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/us/mocker/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/us/mocker/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/us/mocker/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/us/mocker/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/us/mocker/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/us/mocker/releases/tag/v0.1.0
