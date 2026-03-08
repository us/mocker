---
title: Architecture
---

# Architecture

This document explains how Mocker is structured, the design decisions behind it, and how the components interact.

---

## Overview

Mocker is composed of three Swift Package Manager targets:

```
┌─────────────────────────────────────────────────────────────┐
│                        MockerApp                            │
│         SwiftUI MenuBar GUI (macOS 26+) — coming soon       │
└──────────────────────┬──────────────────────────────────────┘
                       │ imports
┌──────────────────────▼──────────────────────────────────────┐
│                        Mocker                               │
│         CLI executable (swift-argument-parser)              │
└──────────────────────┬──────────────────────────────────────┘
                       │ imports
┌──────────────────────▼──────────────────────────────────────┐
│                      MockerKit                              │
│              Shared core library (actor-based)              │
└─────────────────────────────────────────────────────────────┘
```

Both `Mocker` (CLI) and `MockerApp` (GUI) depend on `MockerKit`. The core library never imports UI frameworks, keeping it independently testable.

---

## Module Structure

```
Sources/
├── MockerKit/
│   ├── Models/
│   │   ├── ContainerConfig.swift    # PortMapping, VolumeMount, RestartPolicy
│   │   ├── ContainerInfo.swift      # Runtime container state
│   │   ├── ContainerState.swift     # Enum: created/running/paused/stopped/exited/dead
│   │   ├── ImageInfo.swift          # Image metadata + ImageReference parser
│   │   ├── NetworkInfo.swift        # Network metadata
│   │   ├── VolumeInfo.swift         # Volume metadata
│   │   └── MockerError.swift        # Docker-compatible error messages
│   ├── Config/
│   │   └── MockerConfig.swift       # Paths, ensureDirectories()
│   ├── Container/
│   │   ├── ContainerEngine.swift    # actor: run/stop/rm/logs/exec/inspect
│   │   └── ContainerStore.swift     # actor: JSON persistence
│   ├── Image/
│   │   ├── ImageManager.swift       # actor: pull/push/build/tag/rmi
│   │   └── ImageStore.swift         # actor: JSON persistence
│   ├── Network/
│   │   └── NetworkManager.swift     # actor: create/list/remove/connect
│   ├── Volume/
│   │   └── VolumeManager.swift      # actor: create/list/remove
│   └── Compose/
│       ├── ComposeFile.swift        # Yams-based YAML parser + variable substitution
│       └── ComposeOrchestrator.swift # actor: up/down/ps/restart
│
├── Mocker/
│   ├── MockerCLI.swift              # @main entry point, command registration
│   ├── Commands/
│   │   ├── Run.swift
│   │   ├── PS.swift
│   │   ├── Stop.swift
│   │   ├── Remove.swift
│   │   ├── Exec.swift
│   │   ├── Logs.swift
│   │   ├── Build.swift
│   │   ├── Pull.swift
│   │   ├── Push.swift
│   │   ├── Images.swift
│   │   ├── Tag.swift
│   │   ├── Rmi.swift
│   │   ├── Inspect.swift
│   │   ├── Stats.swift
│   │   ├── Network.swift
│   │   ├── Volume.swift
│   │   ├── Compose.swift
│   │   └── System.swift
│   └── Formatters/
│       └── TableFormatter.swift     # Table + JSON output helpers
│
└── MockerApp/
    ├── MockerApp.swift              # App entry point + MenuBarExtra
    ├── MenuBar/
    │   └── MenuBarView.swift        # Top-level menu
    ├── ViewModels/
    │   └── AppViewModel.swift       # @MainActor observable state
    └── Views/
        ├── ContainerListView.swift
        ├── ImageListView.swift
        └── ComposeProjectsView.swift
```

---

## MockerKit — Core Library

### Engines and Managers

Every stateful subsystem is an `actor`:

```swift
public actor ContainerEngine {
    private let config: MockerConfig
    private let store: ContainerStore

    public func run(_ config: ContainerConfig) async throws -> ContainerInfo { ... }
    public func stop(_ id: String) async throws { ... }
    public func list(all: Bool) async throws -> [ContainerInfo] { ... }
}
```

`actor` isolation guarantees that state mutations are serialized — no locks, no data races.

### Models

`ContainerConfig` captures everything needed to create a container:

```swift
public struct ContainerConfig: Codable {
    public var image: String
    public var name: String?
    public var command: [String]
    public var ports: [PortMapping]
    public var volumes: [VolumeMount]
    public var environment: [String: String]
    public var labels: [String: String]
    public var restartPolicy: RestartPolicy
    public var network: String?
}
```

### ImageReference Parser

`ImageReference.parse()` handles all Docker image reference formats:

| Input | Repository | Tag | Registry |
|-------|-----------|-----|----------|
| `alpine` | `alpine` | `latest` | (none) |
| `nginx:1.25` | `nginx` | `1.25` | (none) |
| `registry.io/app:v1` | `registry.io/app` | `v1` | `registry.io` |
| `gcr.io/project/app:sha` | `gcr.io/project/app` | `sha` | `gcr.io` |

### Error Handling

All errors use Docker-compatible messages via `MockerError`:

```swift
public enum MockerError: LocalizedError {
    case containerNotFound(String)
    case containerAlreadyExists(String)
    case imageNotFound(String)
    case operationFailed(String)
    // ...
}
```

Example output:
```
Error response from daemon: No such container: myapp
Error response from daemon: Conflict. The container name "/myapp" is already in use...
```

### Compose Orchestrator

`ComposeOrchestrator` coordinates all resources for a project:

1. Parse `docker-compose.yml` via `ComposeFile` (including `.env` variable substitution)
2. Topological sort of services (respects `depends_on`)
3. Create networks → create volumes → start services in order
4. Skip builds when image already exists (like `docker compose up` without `--build`)
5. Emit `ComposeEvent` values for progress reporting

```swift
public enum ComposeEvent {
    case networkCreated(String)
    case volumeCreated(String)
    case containerCreated(String)
    case containerStarted(String)
    case containerStopped(String)
    case containerRemoved(String)
    case networkRemoved(String)
}
```

---

## Mocker — CLI

### Entry Point

```swift
@main
struct MockerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mocker",
        subcommands: [Run.self, PS.self, Stop.self, ...]
    )
}
```

### Command Pattern

```swift
struct Run: AsyncParsableCommand {
    @Flag(name: .shortAndLong) var detach = false
    @Option(name: .shortAndLong) var name: String?
    @Argument var image: String

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)
        // ... build ContainerConfig, call engine.run()
    }
}
```

### Output Formatting

`TableFormatter` handles two output styles:

```swift
// Tabular output (ps, images, network ls, etc.)
TableFormatter.print(headers: ["CONTAINER ID", "IMAGE", ...], rows: rows)

// JSON output (inspect)
TableFormatter.printJSONArray(value)   // → [{...}]
TableFormatter.printJSON(value)        // → {...}
```

---

## MockerApp — MenuBar GUI

> Currently a skeleton. Full implementation coming soon.

```
MenuBarExtra (SwiftUI)
    └── MenuBarView
            ├── ContainerListView   (shows running containers)
            ├── ImageListView       (shows local images)
            └── ComposeProjectsView (shows active projects)
```

The `AppViewModel` is `@MainActor`-isolated and polls MockerKit actors for live updates.

---

## Data Flow

### `mocker run -d --name web nginx:latest`

```
CLI Run.run()
  │
  ├─ ContainerConfig (name="web", image="nginx:latest", detach=true)
  │
  └─ ContainerEngine.run(config)
        │
        ├─ ContainerStore.findByName("web")  → nil (no conflict)
        │
        ├─ Apple container CLI → start container VM
        │
        ├─ ContainerInfo(id: assignedID, name: "web", state: .running, ...)
        │
        └─ ContainerStore.save(info)  → ~/.mocker/containers/<id>.json
```

### `mocker compose up -d`

```
ComposeUp.run()
  │
  ├─ ComposeFile.load("docker-compose.yml")
  │     └─ loadDotEnv(".env") + substituteVariables()
  │
  └─ ComposeOrchestrator.up(composeFile, detach: true)
        │
        ├─ serviceOrder()  → topological sort → [db, api, web]
        │
        ├─ NetworkManager.create("project-backend")   → ComposeEvent.networkCreated
        ├─ VolumeManager.create("project-pgdata")     → ComposeEvent.volumeCreated
        │
        ├─ ContainerEngine.run(dbConfig)   → ComposeEvent.containerStarted("project-db-1")
        ├─ ContainerEngine.run(apiConfig)  → ComposeEvent.containerStarted("project-api-1")
        └─ ContainerEngine.run(webConfig)  → ComposeEvent.containerStarted("project-web-1")
```

---

## Concurrency Model

Mocker uses Swift 6 strict concurrency throughout:

| Component | Isolation |
|-----------|-----------|
| `ContainerEngine` | `actor` |
| `ContainerStore` | `actor` |
| `ImageManager` | `actor` |
| `ImageStore` | `actor` |
| `NetworkManager` | `actor` |
| `VolumeManager` | `actor` |
| `ComposeOrchestrator` | `actor` |
| CLI commands | `async` functions (cooperative thread pool) |
| `AppViewModel` | `@MainActor` |

All cross-actor calls use `await`. No shared mutable state outside actors.

---

## Persistence

State is stored as JSON files under `~/.mocker/`:

```
~/.mocker/
├── containers/
│   ├── b8482c2a83c8...json    # ContainerInfo
│   └── 0ca840cf0885...json
├── images/
│   ├── sha256:d67dd0f7...json  # ImageInfo
│   └── sha256:9551aa56...json
├── networks/
│   └── a69bb9f3bb64.json      # NetworkInfo
└── volumes/
    ├── pgdata.json             # VolumeInfo
    └── pgdata/
        └── _data/              # Actual volume data (bind-mounted)
```

Stores load all JSON files from their directory on init. No database, no daemon — just files.

---

## Apple Containerization Integration

Container lifecycle delegates to Apple's `container` CLI subprocess. Image operations use `Containerization.ImageStore` directly.

| Operation | Backend |
|-----------|---------|
| `run`, `stop`, `exec`, `logs` | `/usr/local/bin/container` subprocess |
| `build` | `container build` with live streaming output |
| `pull`, `push`, `tag`, `rmi` | `Containerization.ImageStore` (direct framework) |
| `images` | Apple CLI image store (shows all pulled + built images) |
| `stats` | VM process RSS/CPU via `ps` (VirtualMachine.xpc matching) |
| Port mapping `-p` | Persistent `mocker __proxy` subprocess per port |

This hybrid approach gives a fully working Docker-compatible tool on macOS 26 today, with the option to deepen framework integration over time.
