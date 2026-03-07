# Mocker 入门指南

本指南将引导您完成 Mocker 的安装，并运行您的第一批容器。

## 目录

- [前置条件](#前置条件)
- [安装](#安装)
- [运行第一个容器](#运行第一个容器)
- [管理镜像](#管理镜像)
- [使用 Compose](#使用-compose)
- [下一步](#下一步)

## 前置条件

安装 Mocker 前，请确保您已满足以下要求：

| 需求 | 版本 | 备注 |
|------|------|------|
| macOS | 26.0+ | Apple Containerization 框架所需 |
| Swift | 6.0+ | [从 swift.org 下载](https://swift.org/download) |
| Xcode | 16.0+ | 或仅安装命令行工具 |

验证 Swift 版本：

```bash
swift --version
# Swift version 6.0.x (swift-6.0.x-RELEASE)
```

## 安装

### 方式一：从源码构建（推荐）

```bash
# 克隆仓库
git clone https://github.com/yourname/mocker.git
cd mocker

# 以 release 模式构建
swift build -c release

# 安装二进制文件
sudo cp .build/release/mocker /usr/local/bin/mocker

# 验证安装
mocker --version
# 0.1.0
```

### 方式二：开发模式构建

开发时可直接使用 `swift run`，无需安装：

```bash
swift run mocker --help
```

### Shell 补全

为您的 Shell 生成补全脚本：

```bash
# Bash
mocker --generate-completion-script bash >> ~/.bashrc

# Zsh
mocker --generate-completion-script zsh >> ~/.zshrc

# Fish
mocker --generate-completion-script fish > ~/.config/fish/completions/mocker.fish
```

## 运行第一个容器

### 第一步：拉取镜像

```bash
mocker pull alpine:latest
```

输出：
```
latest: Pulling from alpine
a1b2c3d4e5f6: Pull complete
b2c3d4e5f6a1: Pull complete
c3d4e5f6a1b2: Pull complete
Digest: sha256:...
Status: Downloaded newer image for alpine:latest
alpine:latest
```

再次拉取同一镜像时，Mocker 会识别已存在的镜像：
```
Digest: sha256:...
Status: Image is up to date for alpine:latest
```

### 第二步：运行容器

以**后台模式（detached）**运行容器：

```bash
mocker run -d --name my-nginx -p 8080:80 nginx:latest
```

命令输出完整容器 ID：
```
b8482c2a83c8daa383292a1fcee6262b600b18d87bc84197db05b24c4c73dd69
```

### 第三步：验证运行状态

```bash
mocker ps
```

```
CONTAINER ID   IMAGE          COMMAND   CREATED        STATUS                  PORTS          NAMES
b8482c2a83c8   nginx:latest             3秒前          Up Less than a second   8080:80/tcp    my-nginx
```

### 第四步：查看日志

```bash
mocker logs my-nginx
```

### 第五步：停止并清理

```bash
mocker stop my-nginx
mocker rm my-nginx
```

## 管理镜像

### 拉取镜像

```bash
# 默认使用 latest 标签
mocker pull ubuntu

# 指定版本
mocker pull node:20-alpine

# 从自定义镜像仓库拉取
mocker pull registry.example.com/myapp:v2.1.0
```

### 列出镜像

```bash
mocker images
```

```
REPOSITORY   TAG        IMAGE ID       CREATED    SIZE
node         20-alpine  sha256:abc12   2分钟前    Zero KB
ubuntu       latest     sha256:def34   5分钟前    Zero KB
```

### 打标签与重命名

```bash
# 为私有仓库打标签
mocker tag ubuntu:latest my-registry.io/ubuntu:22.04

# 验证结果
mocker images
```

### 删除镜像

```bash
# 按引用删除
mocker rmi ubuntu:latest

# 输出
# Untagged: ubuntu:latest
# Deleted: sha256:def34...
```

## 使用 Compose

Compose 让您通过单个 YAML 文件定义和运行多容器应用。

### 创建 Compose 文件

保存为 `docker-compose.yml`：

```yaml
version: "3.8"

services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
    depends_on:
      - app

  app:
    image: node:20-alpine
    environment:
      - NODE_ENV=production
      - DB_HOST=db
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: myapp
    volumes:
      - db-data:/var/lib/postgresql/data

volumes:
  db-data:
```

### 启动所有服务

```bash
mocker compose up -d
```

```
[+] Running 4/4
 ✔ Volume myapp-db-data    Created
 ✔ Container myapp-db-1    Started
 ✔ Container myapp-app-1   Started
 ✔ Container myapp-web-1   Started
```

> **提示：** 服务按依赖顺序自动启动。`db` 先启动，然后是 `app`，最后是 `web`。

### 查看状态

```bash
mocker compose ps
```

```
NAME            IMAGE          SERVICE   CREATED   STATUS
myapp-db-1      postgres:15    db        5秒前     Up Less than a second
myapp-app-1     node:20-alpine app       5秒前     Up Less than a second
myapp-web-1     nginx:latest   web       5秒前     Up Less than a second
```

### 查看日志

```bash
# 所有服务
mocker compose logs

# 指定服务
mocker compose logs app
```

### 停止并清理

```bash
mocker compose down
```

```
[+] Running 6/6
 ✔ Container myapp-web-1   Stopped
 ✔ Container myapp-web-1   Removed
 ✔ Container myapp-app-1   Stopped
 ✔ Container myapp-app-1   Removed
 ✔ Container myapp-db-1    Stopped
 ✔ Container myapp-db-1    Removed
```

## 下一步

- [CLI 参考](cli-reference.md) — 所有命令和参数的完整文档
- [Compose 指南](compose.md) — Docker Compose 高级功能
- [架构设计](architecture.md) — Mocker 内部工作原理
- [贡献指南](contributing.md) — 参与 Mocker 的开发
