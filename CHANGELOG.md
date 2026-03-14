# Changelog

All notable changes to Mocker are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
