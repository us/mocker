# Mocker

<div align="center">

**基于 Apple Containerization 框架构建的 Docker 兼容容器管理工具**

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![平台](https://img.shields.io/badge/平台-macOS%2026%2B-blue.svg)](https://developer.apple.com/macos/)
[![许可证](https://img.shields.io/badge/许可证-MIT-green.svg)](LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/SPM-兼容-brightgreen.svg)](Package.swift)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

Mocker 是一款 **Docker 兼容的 CLI + Compose + MenuBar GUI** 工具，使用 Apple 的 [Containerization](https://developer.apple.com/documentation/containerization) 框架（macOS 26+）在 macOS 上原生运行。它与 Docker 使用相同的命令、相同的参数和相同的输出格式，让您现有的脚本和操作习惯无缝迁移。

## 功能特性

- **完整 Docker CLI 兼容** — `run`、`ps`、`stop`、`rm`、`exec`、`logs`、`build`、`pull`、`push`、`images`、`tag`、`rmi`、`inspect`、`stats`
- **网络管理** — `network create/ls/rm/inspect/connect/disconnect`
- **卷管理** — `volume create/ls/rm/inspect`
- **Docker Compose v2** — `compose up/down/ps/logs/restart`，支持依赖顺序启动
- **MenuBar GUI** — 原生 SwiftUI 应用，一目了然管理容器
- **JSON 状态持久化** — 所有元数据存储于 `~/.mocker/`
- **Swift 6 并发** — 全程基于 actor 的线程安全设计

## 系统要求

| 组件 | 版本 |
|------|------|
| macOS | 26.0+（Sequoia） |
| Swift | 6.0+ |
| Xcode | 16.0+ |

> **注意：** Apple Containerization 框架需要 macOS 26 及 Apple Silicon 芯片。不支持 Intel Mac。

## 安装

### Homebrew（推荐）

```bash
brew tap us/tap
brew install mocker
```

### 从源码构建

```bash
git clone https://github.com/us/mocker.git
cd mocker
swift build -c release
cp .build/release/mocker /usr/local/bin/mocker
```

## 快速开始

```bash
# 拉取镜像
mocker pull nginx:1.25

# 运行容器
mocker run -d --name webserver -p 8080:80 nginx:1.25

# 查看运行中的容器
mocker ps

# 查看日志
mocker logs webserver

# 停止并删除
mocker stop webserver
mocker rm webserver
```

## 使用说明

### 容器生命周期

```bash
# 带环境变量和挂载卷运行
mocker run -d \
  --name myapp \
  -p 8080:80 \
  -e APP_ENV=production \
  -v /host/data:/app/data \
  myimage:latest

# 前台交互运行
mocker run --name temp alpine:latest

# 强制删除运行中的容器
mocker rm -f myapp

# 在运行中的容器内执行命令
mocker exec myapp env

# 持续跟踪日志
mocker logs -f myapp
```

### 镜像管理

```bash
# 拉取指定标签
mocker pull postgres:15

# 列出所有镜像
mocker images

# 仅列出镜像 ID
mocker images -q

# 为镜像打标签
mocker tag alpine:latest my-registry.io/alpine:v1

# 删除镜像
mocker rmi my-registry.io/alpine:v1

# 从 Dockerfile 构建
mocker build -t myapp:latest .

# 推送到镜像仓库
mocker push my-registry.io/myapp:latest
```

### 检查与统计

```bash
# 检查容器（JSON 输出）
mocker inspect myapp

# 同时检查多个对象
mocker inspect container1 container2 alpine:latest

# 资源使用统计
mocker stats --no-stream
```

### 网络管理

```bash
# 创建网络
mocker network create mynet

# 列出网络
mocker network ls

# 将容器连接到网络
mocker network connect mynet myapp

# 断开连接
mocker network disconnect mynet myapp

# 检查网络详情
mocker network inspect mynet

# 删除网络
mocker network rm mynet
```

### 卷管理

```bash
# 创建命名卷
mocker volume create pgdata

# 列出卷
mocker volume ls

# 检查卷（显示挂载点）
mocker volume inspect pgdata

# 删除卷
mocker volume rm pgdata
```

### Docker Compose

```bash
# 后台启动所有服务
mocker compose -f docker-compose.yml up -d

# 列出 Compose 容器
mocker compose -f docker-compose.yml ps

# 查看指定服务的日志
mocker compose -f docker-compose.yml logs web

# 重启某个服务
mocker compose -f docker-compose.yml restart api

# 停止并清理
mocker compose -f docker-compose.yml down
```

示例 `docker-compose.yml`：

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

### 系统管理

```bash
# 查看系统信息
mocker system info

# 清理已停止的容器和未使用的资源
mocker system prune -f
```

## 架构设计

```
mocker/
├── Sources/
│   ├── MockerKit/          # 共享核心库
│   │   ├── Models/         # 数据类型（ContainerInfo、ImageInfo 等）
│   │   ├── Config/         # MockerConfig（~/.mocker/ 路径）
│   │   ├── Container/      # ContainerEngine + ContainerStore（actor）
│   │   ├── Image/          # ImageManager + ImageStore（actor）
│   │   ├── Network/        # NetworkManager（actor）
│   │   ├── Volume/         # VolumeManager（actor）
│   │   └── Compose/        # ComposeFile 解析器 + ComposeOrchestrator
│   ├── Mocker/             # CLI 可执行文件
│   │   ├── Commands/       # 每个命令组一个文件
│   │   └── Formatters/     # TableFormatter、JSON 输出
│   └── MockerApp/          # SwiftUI MenuBar 应用（macOS 26+）
│       ├── MenuBar/
│       ├── ViewModels/
│       └── Views/
└── Tests/
    ├── MockerKitTests/     # 核心库单元测试
    └── MockerTests/        # CLI 集成测试
```

### 核心设计决策

| 关注点 | 方案 |
|--------|------|
| 线程安全 | 所有引擎/管理器均为 `actor` 类型 |
| 状态持久化 | JSON 文件存储于 `~/.mocker/{containers,images,networks,volumes}/` |
| CLI 解析 | `swift-argument-parser` + `AsyncParsableCommand` |
| YAML 解析 | `Yams` 库 |
| Compose 命名 | Docker v2 规范：`项目名-服务名-1`（连字符分隔） |
| JSON 输出 | 始终包装为数组 `[{...}]`，与 Docker `inspect` 格式一致 |

## 数据目录

Mocker 将所有状态存储在 `~/.mocker/`：

```
~/.mocker/
├── containers/   # 容器元数据（每个容器一个 JSON 文件）
├── images/       # 镜像元数据
├── networks/     # 网络元数据
└── volumes/      # 卷元数据 + 实际数据目录
    └── pgdata/
        └── _data/
```

## Docker 兼容性

Mocker 致力于与 Docker CLI 完全兼容，已匹配的关键行为：

- 错误消息格式：`Error response from daemon: ...`
- `inspect` 始终返回 JSON 数组，即使是单个对象
- `pull` 幂等性：重复拉取已存在的镜像时显示 "Image is up to date"
- Compose 容器命名：`project-service-1`（连字符，非下划线）
- `stop` 和 `rm` 回显用户提供的标识符
- 短 ID 为 12 个字符（完整 64 位十六进制 ID 的前 12 位）

## 构建与测试

```bash
# 构建所有目标
swift build

# 运行所有测试
swift test

# 运行指定测试套件
swift test --filter MockerKitTests

# 直接运行 CLI
swift run mocker --help
```

## 工作原理

Mocker 将容器生命周期（run、stop、exec、logs、build）委托给 Apple 的 `container` CLI 处理。
镜像操作（pull、list、tag、rmi）直接使用 `Containerization.ImageStore` 框架。这种混合架构
让你在 macOS 26 上立刻获得完整的 Docker 兼容体验：

| 操作 | 后端实现 |
|------|---------|
| `run`、`stop`、`exec`、`logs` | `/usr/local/bin/container` 子进程 |
| `build` | `container build`，实时流式输出 |
| `pull`、`push`、`tag`、`rmi` | `Containerization.ImageStore`（直接调用框架） |
| `images` | Apple CLI 镜像仓库（显示所有拉取和构建的镜像） |
| `stats` | 通过 `ps` 读取 VirtualMachine.xpc 进程的 RSS/CPU |
| 端口映射 `-p` | 每个端口启动一个持久化 `mocker __proxy` 子进程 |

## 路线图

- [x] 完整 Docker CLI 命令集
- [x] Docker Compose v2 支持
- [x] 网络与卷管理
- [x] MenuBar GUI 骨架
- [x] macOS 26 上的真实容器运行（通过 Apple `container` CLI）
- [x] `mocker build` — 委托 `container build`，支持实时输出
- [x] `mocker stats` — 从 VM 进程读取真实 CPU% 和内存数据
- [x] 端口映射（`-p`）— 用户态 TCP 代理子进程
- [ ] 镜像仓库认证（`mocker login`）
- [ ] `mocker compose --scale`
- [ ] MenuBar 实时容器指标
- [ ] 镜像层大小报告
- [ ] 直接集成 Containerization 框架（待 vminit 版本兼容性解决）

## 贡献指南

欢迎贡献！请阅读 [docs/zh-CN/contributing.md](docs/zh-CN/contributing.md) 了解详情。

```bash
# Fork 并克隆
git clone https://github.com/yourname/mocker.git

# 创建功能分支
git checkout -b feat/my-feature

# 修改并测试
swift test

# 使用约定式提交
git commit -m "feat: 添加新功能"
```

## 许可证

MIT 许可证 — 详见 [LICENSE](LICENSE)。

---

<div align="center">
使用 Swift 在 macOS 上构建 · 由 Apple Containerization 驱动
</div>
