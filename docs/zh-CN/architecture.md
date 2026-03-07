# 架构设计

本文档介绍 Mocker 的结构、背后的设计决策以及各组件之间的交互方式。

## 目录

- [概述](#概述)
- [模块结构](#模块结构)
- [MockerKit — 核心库](#mockerkit--核心库)
- [Mocker — CLI](#mocker--cli)
- [MockerApp — MenuBar GUI](#mockerapp--menubar-gui)
- [数据流](#数据流)
- [并发模型](#并发模型)
- [持久化存储](#持久化存储)
- [Apple Containerization 集成](#apple-containerization-集成)

## 概述

Mocker 由三个 Swift Package Manager 目标组成：

```
┌─────────────────────────────────────────────────────────────┐
│                        MockerApp                            │
│              SwiftUI MenuBar GUI（macOS 26+）               │
└──────────────────────┬──────────────────────────────────────┘
                       │ 依赖
┌──────────────────────▼──────────────────────────────────────┐
│                        Mocker                               │
│         CLI 可执行文件（swift-argument-parser）              │
└──────────────────────┬──────────────────────────────────────┘
                       │ 依赖
┌──────────────────────▼──────────────────────────────────────┐
│                      MockerKit                              │
│              共享核心库（基于 actor）                         │
└─────────────────────────────────────────────────────────────┘
```

`Mocker`（CLI）和 `MockerApp`（GUI）都依赖 `MockerKit`。核心库不引入任何 UI 框架，保持独立可测性。

## 模块结构

```
Sources/
├── MockerKit/
│   ├── Models/
│   │   ├── ContainerConfig.swift    # PortMapping、VolumeMount、RestartPolicy
│   │   ├── ContainerInfo.swift      # 运行时容器状态
│   │   ├── ContainerState.swift     # 枚举：created/running/paused/stopped/exited/dead
│   │   ├── ImageInfo.swift          # 镜像元数据 + ImageReference 解析器
│   │   ├── NetworkInfo.swift        # 网络元数据
│   │   ├── VolumeInfo.swift         # 卷元数据
│   │   └── MockerError.swift        # Docker 兼容的错误消息
│   ├── Config/
│   │   └── MockerConfig.swift       # 路径配置、ensureDirectories()
│   ├── Container/
│   │   ├── ContainerEngine.swift    # actor：run/stop/rm/logs/exec/inspect
│   │   └── ContainerStore.swift     # actor：JSON 持久化
│   ├── Image/
│   │   ├── ImageManager.swift       # actor：pull/push/build/tag/rmi
│   │   └── ImageStore.swift         # actor：JSON 持久化
│   ├── Network/
│   │   └── NetworkManager.swift     # actor：create/list/remove/connect
│   ├── Volume/
│   │   └── VolumeManager.swift      # actor：create/list/remove
│   └── Compose/
│       ├── ComposeFile.swift        # 基于 Yams 的 YAML 解析器
│       └── ComposeOrchestrator.swift # actor：up/down/ps/restart
│
├── Mocker/
│   ├── MockerCLI.swift              # @main 入口点，命令注册
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
│       └── TableFormatter.swift     # 表格输出 + JSON 输出工具
│
└── MockerApp/
    ├── MockerApp.swift              # 应用入口 + MenuBarExtra
    ├── MenuBar/
    │   └── MenuBarView.swift        # 顶层菜单视图
    ├── ViewModels/
    │   └── AppViewModel.swift       # @MainActor 可观察状态
    └── Views/
        ├── ContainerListView.swift
        ├── ImageListView.swift
        └── ComposeProjectsView.swift
```

## MockerKit — 核心库

### 引擎与管理器

每个有状态的子系统都是一个 `actor`：

```swift
public actor ContainerEngine {
    private let config: MockerConfig
    private let store: ContainerStore

    public func run(_ config: ContainerConfig) async throws -> ContainerInfo { ... }
    public func stop(_ id: String) async throws { ... }
    public func list(all: Bool) async throws -> [ContainerInfo] { ... }
}
```

`actor` 隔离保证状态变更是串行化的——无需锁，无数据竞争。

### 数据模型

`ContainerConfig` 包含创建容器所需的一切信息：

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
    public var autoRemove: Bool
}
```

### ImageReference 解析器

`ImageReference.parse()` 处理所有 Docker 镜像引用格式：

| 输入 | 仓库 | 标签 | 镜像仓库 |
|------|------|------|----------|
| `alpine` | `alpine` | `latest` | （无） |
| `nginx:1.25` | `nginx` | `1.25` | （无） |
| `registry.io/app:v1` | `registry.io/app` | `v1` | `registry.io` |
| `gcr.io/project/app:sha` | `gcr.io/project/app` | `sha` | `gcr.io` |

### 错误处理

所有错误通过 `MockerError` 使用 Docker 兼容的消息格式：

```swift
public enum MockerError: LocalizedError {
    case containerNotFound(String)
    case containerAlreadyExists(String)
    case imageNotFound(String)
    case operationFailed(String)
}
```

输出示例：
```
Error response from daemon: No such container: myapp
Error response from daemon: Conflict. The container name "/myapp" is already in use...
```

### Compose 编排器

`ComposeOrchestrator` 协调项目中所有资源：

1. 通过 `ComposeFile` 解析 `docker-compose.yml`
2. 对服务进行拓扑排序（遵循 `depends_on`）
3. 创建网络 → 创建卷 → 按顺序启动服务
4. 发出 `[ComposeEvent]` 用于进度报告

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

## Mocker — CLI

### 入口点

```swift
@main
struct MockerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mocker",
        subcommands: [Run.self, PS.self, Stop.self, ...]
    )
}
```

### 命令模式

每个命令遵循以下模式：

```swift
struct Run: AsyncParsableCommand {
    @Flag(name: .shortAndLong) var detach = false
    @Option(name: .shortAndLong) var name: String?
    @Argument var image: String

    func run() async throws {
        let config = MockerConfig()
        try config.ensureDirectories()
        let engine = try ContainerEngine(config: config)
        // ... 构建 ContainerConfig，调用 engine.run()
    }
}
```

### 输出格式化

`TableFormatter` 处理两种输出风格：

```swift
// 表格输出（ps、images、network ls 等）
TableFormatter.print(headers: ["CONTAINER ID", "IMAGE", ...], rows: rows)

// JSON 输出（inspect）
TableFormatter.printJSONArray(value)   // → [{...}]
TableFormatter.printJSON(value)        // → {...}
```

## MockerApp — MenuBar GUI

> 目前为骨架实现，完整功能需要 macOS 26 + Apple Containerization 框架。

```
MenuBarExtra (SwiftUI)
    └── MenuBarView
            ├── ContainerListView   （显示运行中的容器）
            ├── ImageListView       （显示本地镜像）
            └── ComposeProjectsView （显示活跃的 Compose 项目）
```

`AppViewModel` 使用 `@MainActor` 隔离，定期轮询 MockerKit actor 以获取实时更新。

## 数据流

### `mocker run -d --name web nginx:latest`

```
CLI Run.run()
  │
  ├─ 解析参数：name="web"，image="nginx:latest"，detach=true
  │
  └─ ContainerEngine.run(config)
        │
        ├─ ContainerStore.findByName("web")  → nil（无冲突）
        │
        ├─ TODO：Apple Containerization → 启动真实容器进程
        │
        ├─ ContainerInfo(id: 随机ID, name: "web", state: .running, ...)
        │
        └─ ContainerStore.save(info)  → ~/.mocker/containers/<id>.json
              │
              └─ print(info.id)  → "b8482c2a83c8..."
```

### `mocker compose up -d`

```
ComposeUp.run()
  │
  ├─ ComposeFile.load("docker-compose.yml")  → ComposeFile
  │
  ├─ ComposeOrchestrator.up(composeFile, detach: true)
  │     │
  │     ├─ serviceOrder()  → 拓扑排序 → [db, api, web]
  │     │
  │     ├─ NetworkManager.create("项目-backend")  → ComposeEvent.networkCreated
  │     ├─ VolumeManager.create("项目-pgdata")    → ComposeEvent.volumeCreated
  │     │
  │     ├─ ContainerEngine.run(dbConfig)   → ComposeEvent.containerStarted("项目-db-1")
  │     ├─ ContainerEngine.run(apiConfig)  → ComposeEvent.containerStarted("项目-api-1")
  │     └─ ContainerEngine.run(webConfig)  → ComposeEvent.containerStarted("项目-web-1")
  │
  └─ ComposeFormatter.printEvents(events, total: 5)
```

## 并发模型

Mocker 全程使用 Swift 6 严格并发模型：

| 组件 | 隔离方式 |
|------|----------|
| `ContainerEngine` | `actor` |
| `ContainerStore` | `actor` |
| `ImageManager` | `actor` |
| `ImageStore` | `actor` |
| `NetworkManager` | `actor` |
| `VolumeManager` | `actor` |
| `ComposeOrchestrator` | `actor` |
| CLI 命令 | `async` 函数（在协作线程池上运行） |
| `AppViewModel` | `@MainActor` |

所有跨 actor 调用均使用 `await`，actor 外无共享可变状态。

## 持久化存储

状态以 JSON 文件形式存储在 `~/.mocker/`：

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
        └── _data/              # 实际卷数据（绑定挂载）
```

存储层在初始化时从目录读取所有 JSON 文件。无数据库，无守护进程——只有文件。

## Apple Containerization 集成

所有实际的容器操作都标注了 `// TODO:` 注释，目前使用占位符实现。在 macOS 26 上，这些将被替换为对 Apple Containerization 框架的调用：

```swift
// TODO: 使用 Containerization 框架实际拉取镜像
// 替换为：try await Container.Image.pull(reference)

// TODO: 使用 Containerization 框架启动容器
// 替换为：let container = try await Container(config: ...)
//          try await container.start()
```

占位层的存在意味着 CLI 在 macOS 26 之前已完全可用于测试和开发，所有状态管理、错误处理和输出格式化均正确运行。
