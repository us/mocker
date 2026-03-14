<div align="center">

# Mocker

**A Docker-compatible container management tool built on Apple's Containerization framework**

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2026%2B-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](Package.swift)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

Mocker is a **Docker-compatible CLI + Compose** tool that runs natively on macOS using Apple's [Containerization](https://developer.apple.com/documentation/containerization) framework (macOS 26+). It speaks the same language as Docker — same commands, same flags, same output format — so your existing scripts and muscle memory just work.

## Just replace `docker` with `mocker`

```bash
# Before
docker compose up -d
docker ps
docker logs my-app
docker exec -it my-app sh

# After — same commands, native Apple runtime, no Docker Desktop
mocker compose up -d
mocker ps
mocker logs my-app
mocker exec -it my-app sh
```

Your existing `docker-compose.yml` works as-is.

## What's New

### v0.1.9 — Full Docker CLI Flag Compatibility
- **111 commands/subcommands** with Docker-matching flags
- `run`/`create`: ~50 new flags (`--attach`, `--cpu-shares`, `--gpus`, `--init`, `--memory`, `--privileged`, `--restart`, `--shm-size`, `--ulimit`, etc.)
- `build`: ~25 BuildKit/Buildx flags (`--cache-from`, `--load`, `--push`, `--secret`, `--ssh`, etc.)
- `compose`: ~200+ flags across 22 subcommands
- New commands: `commit`, `container prune`, `container export`, `image rm/inspect/prune`
- Full [COMMANDS.md](COMMANDS.md) reference and [CHANGELOG.md](CHANGELOG.md) added

### v0.1.8 — `--env-file` support
- **`mocker run --env-file .env`** — load environment variables from file, just like Docker

### v0.1.7 — Compose improvements & `--rm` flag
- **`mocker run --rm`** — auto-remove container on exit
- `compose.yaml` / `compose.yml` recognized as default compose file
- Compose `${VAR:-default}` variable substitution fix

> See [CHANGELOG.md](CHANGELOG.md) for the full version history.

## Features

- **Full Docker CLI compatibility** — `run`, `ps`, `stop`, `rm`, `exec`, `logs`, `build`, `pull`, `push`, `images`, `tag`, `rmi`, `inspect`, `stats`
- **Network management** — `network create/ls/rm/inspect/connect/disconnect`
- **Volume management** — `volume create/ls/rm/inspect`
- **Docker Compose v2** — `compose up/down/ps/logs/restart` with dependency ordering
- **MenuBar GUI** — Native SwiftUI app *(coming soon)*
- **JSON state persistence** — All metadata stored in `~/.mocker/`
- **Swift 6 concurrency** — Full actor-based thread safety throughout

## Requirements

| Component | Version |
|-----------|---------|
| macOS | 26.0+ (Sequoia) |
| Swift | 6.0+ |
| Xcode | 16.0+ |

> **Note:** The Apple Containerization framework requires macOS 26 on Apple Silicon. Intel Macs are not supported.

## Installation

### Homebrew (Recommended)

```bash
brew tap us/tap
brew install mocker
```

### Build from Source

```bash
git clone https://github.com/us/mocker.git
cd mocker
swift build -c release
cp .build/release/mocker /usr/local/bin/mocker
```

## Quick Start

```bash
# Pull an image
mocker pull nginx:1.25

# Run a container
mocker run -d --name webserver -p 8080:80 nginx:1.25

# List running containers
mocker ps

# View logs
mocker logs webserver

# Stop and remove
mocker stop webserver
mocker rm webserver
```

## Usage

### Container Lifecycle

```bash
# Run with environment variables and volumes
mocker run -d \
  --name myapp \
  -p 8080:80 \
  -e APP_ENV=production \
  --env-file .env \
  -v /host/data:/app/data \
  myimage:latest

# Run interactively (foreground)
mocker run --name temp alpine:latest

# Force remove a running container
mocker rm -f myapp

# Execute a command inside a running container
mocker exec myapp env

# Follow logs
mocker logs -f myapp
```

### Images

```bash
# Pull specific tag
mocker pull postgres:15

# List images
mocker images

# List image IDs only
mocker images -q

# Tag an image
mocker tag alpine:latest my-registry.io/alpine:v1

# Remove an image
mocker rmi my-registry.io/alpine:v1

# Build from Dockerfile
mocker build -t myapp:latest .

# Push to registry
mocker push my-registry.io/myapp:latest
```

### Inspect & Stats

```bash
# Inspect container (JSON output)
mocker inspect myapp

# Inspect multiple targets
mocker inspect container1 container2 alpine:latest

# Resource usage stats
mocker stats --no-stream
```

### Networks

```bash
# Create a network
mocker network create mynet

# List networks
mocker network ls

# Connect a container
mocker network connect mynet myapp

# Disconnect
mocker network disconnect mynet myapp

# Inspect
mocker network inspect mynet

# Remove
mocker network rm mynet
```

### Volumes

```bash
# Create a named volume
mocker volume create pgdata

# List volumes
mocker volume ls

# Inspect (shows mountpoint)
mocker volume inspect pgdata

# Remove
mocker volume rm pgdata
```

### Docker Compose

```bash
# Start all services (detached)
mocker compose -f docker-compose.yml up -d

# List compose containers
mocker compose -f docker-compose.yml ps

# View logs for a service
mocker compose -f docker-compose.yml logs web

# Restart a service
mocker compose -f docker-compose.yml restart api

# Tear down
mocker compose -f docker-compose.yml down
```

Example `docker-compose.yml`:

```yaml
version: "3.8"

services:
  web:
    image: nginx:1.25
    ports:
      - "8080:80"
    depends_on:
      - api

  api:
    image: myapp:latest
    environment:
      - DB_HOST=db
      - DB_PORT=5432
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: myapp
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

### System

```bash
# System information
mocker system info

# Remove stopped containers and unused resources
mocker system prune -f
```

## Architecture

```
mocker/
├── Sources/
│   ├── MockerKit/          # Shared core library
│   │   ├── Models/         # Data types (ContainerInfo, ImageInfo, ...)
│   │   ├── Config/         # MockerConfig (~/.mocker/ paths)
│   │   ├── Container/      # ContainerEngine + ContainerStore (actor)
│   │   ├── Image/          # ImageManager + ImageStore (actor)
│   │   ├── Network/        # NetworkManager (actor)
│   │   ├── Volume/         # VolumeManager (actor)
│   │   └── Compose/        # ComposeFile parser + ComposeOrchestrator
│   ├── Mocker/             # CLI executable
│   │   ├── Commands/       # One file per command group
│   │   └── Formatters/     # TableFormatter, JSON output
│   └── MockerApp/          # SwiftUI MenuBar app (macOS 26+)
│       ├── MenuBar/
│       ├── ViewModels/
│       └── Views/
└── Tests/
    ├── MockerKitTests/     # Unit tests for core library
    └── MockerTests/        # CLI integration tests
```

### Key Design Decisions

| Concern | Approach |
|---------|----------|
| Thread safety | All engines/managers are `actor` types |
| Persistence | JSON files in `~/.mocker/{containers,images,networks,volumes}/` |
| CLI parsing | `swift-argument-parser` with `AsyncParsableCommand` |
| YAML parsing | `Yams` library |
| Compose naming | Docker v2 convention: `projectName-serviceName-1` (hyphen separator) |
| JSON output | Always wrapped in array `[{...}]`, matching Docker's `inspect` format |

## Data Directory

Mocker stores all state in `~/.mocker/`:

```
~/.mocker/
├── containers/   # Container metadata (one JSON file per container)
├── images/       # Image metadata
├── networks/     # Network metadata
└── volumes/      # Volume metadata + actual data directories
    └── pgdata/
        └── _data/
```

## Docker Compatibility

Mocker aims for full CLI compatibility with Docker. Key behaviors matched:

- Error messages: `Error response from daemon: ...`
- `inspect` always returns a JSON array, even for a single object
- `pull` idempotency: re-pulling an existing image shows "Image is up to date"
- Compose container naming: `project-service-1` (hyphen, not underscore)
- `stop` and `rm` echo back the identifier provided by the user
- Short IDs are 12 characters (first 12 of full 64-char hex ID)

## Building & Testing

```bash
# Build all targets
swift build

# Run all tests
swift test

# Run specific test suite
swift test --filter MockerKitTests

# Run CLI directly
swift run mocker --help
```

## Performance

Benchmarks run on Apple M-series, macOS 26 (`hyperfine --warmup 5 --runs 15`):

| Tool | Container startup | vs Docker |
|------|:-----------------:|:---------:|
| Docker Desktop | 320 ms | baseline |
| Apple `container` CLI | 1,030 ms | 3.2× slower |
| **Mocker** | **1,153 ms** | **3.6× slower** |

Apple's VM-per-container model trades startup time for stronger isolation — every container gets its own lightweight Linux VM. Mocker adds only ~120 ms of management overhead on top of Apple's runtime.

**CPU & Memory throughput** (sysbench inside container, 30s run):

| Metric | Docker | Apple Container |
|--------|:------:|:---------------:|
| CPU events/s | 7,958 | 7,894 |
| Memory throughput | 13,340 MiB/s | 13,119 MiB/s |

Raw compute performance is equivalent — the VM boundary has negligible overhead for CPU and memory workloads.

## How It Works

Mocker delegates to Apple's `container` CLI for container lifecycle (run, stop, exec, logs, build).
Image operations (pull, list, tag, rmi) use `Containerization.ImageStore` directly. This hybrid
approach gives you a fully working Docker-compatible tool on macOS 26 today:

| Operation | Backend |
|-----------|---------|
| `run`, `stop`, `exec`, `logs` | `/usr/local/bin/container` subprocess |
| `build` | `container build` with live streaming output |
| `pull`, `push`, `tag`, `rmi` | `Containerization.ImageStore` (direct framework) |
| `images` | Apple CLI image store (shows all pulled + built images) |
| `stats` | VM process RSS/CPU via `ps` (VirtualMachine.xpc matching) |
| Port mapping `-p` | Persistent `mocker __proxy` subprocess per port |

## Roadmap

- [x] Full Docker CLI flag compatibility (111 commands)
- [x] Docker Compose v2 support
- [x] Network & Volume management
- [ ] MenuBar GUI
- [x] Real container execution on macOS 26 (via Apple `container` CLI)
- [x] `mocker build` — delegates to `container build` with live output
- [x] `mocker stats` — real CPU% and memory from VM process
- [x] Port mapping (`-p`) — userspace TCP proxy subprocess
- [ ] Registry authentication (`mocker login`)
- [ ] `mocker compose --scale`
- [ ] MenuBar live container metrics (CPU, memory, logs)
- [ ] Image layer size reporting
- [ ] Direct Containerization framework integration (pending vminit compatibility)

## Contributing

Contributions are welcome! Please read [docs/contributing.md](docs/contributing.md) for guidelines.

```bash
# Fork and clone
git clone https://github.com/yourname/mocker.git

# Create a feature branch
git checkout -b feat/my-feature

# Make changes and test
swift test

# Commit with Conventional Commits
git commit -m "feat: add my feature"
```

## License

AGPL-3.0 — see [LICENSE](LICENSE) for details.

---

<div align="center">
Built with Swift on macOS · Powered by Apple Containerization
</div>
