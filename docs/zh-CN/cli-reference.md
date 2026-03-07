# CLI 参考

Mocker 所有命令和参数的完整参考文档。

## 目录

- [全局选项](#全局选项)
- [容器命令](#容器命令)
  - [run](#run)
  - [ps](#ps)
  - [stop](#stop)
  - [rm](#rm)
  - [exec](#exec)
  - [logs](#logs)
  - [inspect](#inspect)
  - [stats](#stats)
- [镜像命令](#镜像命令)
  - [pull](#pull)
  - [push](#push)
  - [images](#images)
  - [build](#build)
  - [tag](#tag)
  - [rmi](#rmi)
- [网络命令](#网络命令)
  - [network create](#network-create)
  - [network ls](#network-ls)
  - [network rm](#network-rm)
  - [network inspect](#network-inspect)
  - [network connect](#network-connect)
  - [network disconnect](#network-disconnect)
- [卷命令](#卷命令)
  - [volume create](#volume-create)
  - [volume ls](#volume-ls)
  - [volume rm](#volume-rm)
  - [volume inspect](#volume-inspect)
- [Compose 命令](#compose-命令)
  - [compose up](#compose-up)
  - [compose down](#compose-down)
  - [compose ps](#compose-ps)
  - [compose logs](#compose-logs)
  - [compose restart](#compose-restart)
- [系统命令](#系统命令)
  - [system info](#system-info)
  - [system prune](#system-prune)

---

## 全局选项

```
mocker [选项] <命令>

选项：
  --version    显示版本并退出
  -h, --help   显示帮助信息
```

---

## 容器命令

### run

创建并启动新容器。

```
mocker run [选项] 镜像 [命令 [参数...]]
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--detach` | `-d` | 后台运行容器，打印容器 ID |
| `--name` | | 为容器指定名称 |
| `--publish` | `-p` | 将容器端口发布到主机（`主机端口:容器端口[/协议]`） |
| `--env` | `-e` | 设置环境变量 |
| `--volume` | `-v` | 挂载卷（`主机路径:容器路径[:ro]` 或命名卷 `卷名:容器路径`） |
| `--label` | `-l` | 设置容器元数据标签 |
| `--restart` | | 重启策略（`no`、`always`、`on-failure`、`unless-stopped`） |
| `--network` | | 将容器连接到网络 |
| `--rm` | | 容器退出后自动删除 |

**示例：**

```bash
# 简单运行
mocker run alpine:latest

# 后台运行，指定名称和端口
mocker run -d --name web -p 8080:80 nginx:latest

# 设置环境变量
mocker run -d -e DB_HOST=localhost -e DB_PORT=5432 myapp:latest

# 只读绑定挂载
mocker run -d -v /host/config:/app/config:ro myapp:latest

# 使用命名卷
mocker run -d -v pgdata:/var/lib/postgresql/data postgres:15

# 设置重启策略
mocker run -d --restart always --name db postgres:15

# 多端口映射
mocker run -d -p 80:80 -p 443:443 -p 8080:8080 nginx:latest
```

**端口格式：** `[主机IP:]主机端口:容器端口[/协议]`
- `8080:80` → 主机 8080 映射到容器 80（TCP）
- `8080:80/udp` → UDP 协议
- `127.0.0.1:8080:80` → 绑定到指定主机 IP

---

### ps

列出容器。

```
mocker ps [选项]
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--all` | `-a` | 显示所有容器（默认只显示运行中的） |
| `--quiet` | `-q` | 只显示容器 ID |

**输出列：**

```
CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES
```

**示例：**

```bash
# 只显示运行中的容器
mocker ps

# 显示所有容器（含已停止的）
mocker ps -a

# 只显示 ID（适合脚本使用）
mocker ps -q

# 停止所有运行中的容器
mocker stop $(mocker ps -q)
```

---

### stop

停止一个或多个运行中的容器。

```
mocker stop 容器 [容器...]
```

成功时回显每个容器标识符。

**示例：**

```bash
mocker stop myapp
mocker stop container1 container2 container3

# 停止所有运行中的容器
mocker stop $(mocker ps -q)
```

---

### rm

删除一个或多个容器。

```
mocker rm [选项] 容器 [容器...]
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--force` | `-f` | 强制删除运行中的容器 |

**示例：**

```bash
# 删除已停止的容器
mocker rm myapp

# 强制删除运行中的容器
mocker rm -f myapp

# 删除多个容器
mocker rm container1 container2

# 删除所有已停止的容器
mocker rm $(mocker ps -aq)
```

**错误情况：**
- 未使用 `-f` 删除运行中的容器：`Error response from daemon: You cannot remove a running container...`
- 容器不存在：`Error response from daemon: No such container: <名称>`

---

### exec

在运行中的容器内执行命令。

```
mocker exec [选项] 容器 命令 [参数...]
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--interactive` | `-i` | 保持 STDIN 开启 |
| `--tty` | `-t` | 分配伪终端 |

**示例：**

```bash
mocker exec myapp env
mocker exec myapp ps aux
mocker exec -it myapp sh
```

---

### logs

获取容器的日志。

```
mocker logs [选项] 容器
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--follow` | `-f` | 持续跟踪日志输出 |
| `--tail` | | 显示末尾指定行数 |
| `--timestamps` | `-t` | 显示时间戳 |

**示例：**

```bash
mocker logs myapp
mocker logs -f myapp
mocker logs --tail 100 myapp
```

---

### inspect

返回容器或镜像的底层详细信息。

```
mocker inspect 目标 [目标...]
```

返回 JSON 数组，自动识别目标是容器还是镜像。

**示例：**

```bash
# 检查容器
mocker inspect myapp

# 检查镜像
mocker inspect alpine:latest

# 同时检查多个目标
mocker inspect myapp postgres:15

# 配合 jq 使用
mocker inspect myapp | jq '.[0].state'
```

**输出格式：**

```json
[
  {
    "id": "b8482c2a83c8...",
    "name": "myapp",
    "image": "nginx:latest",
    "state": "running",
    "status": "Up 2 minutes",
    "created": "2026-03-07T14:00:00Z",
    "ports": [
      { "hostPort": 8080, "containerPort": 80, "portProtocol": "tcp" }
    ],
    "labels": {}
  }
]
```

---

### stats

显示容器资源使用统计信息。

```
mocker stats [选项] [容器...]
```

**选项：**

| 参数 | 说明 |
|------|------|
| `--no-stream` | 禁用流式输出，只获取第一次结果 |

**输出列：**

```
CONTAINER ID   NAME   CPU %   MEM USAGE / LIMIT   MEM %   NET I/O   BLOCK I/O   PIDS
```

**示例：**

```bash
# 所有容器（流式）
mocker stats

# 一次性快照
mocker stats --no-stream

# 指定容器
mocker stats myapp mydb
```

---

## 镜像命令

### pull

从镜像仓库下载镜像。

```
mocker pull 镜像[:标签]
```

幂等操作——重复拉取已存在的镜像时显示 "Image is up to date"，不会创建重复条目。

**示例：**

```bash
mocker pull alpine               # 使用 :latest 标签
mocker pull nginx:1.25
mocker pull registry.example.com/myapp:v2.0
```

---

### push

将镜像上传到镜像仓库。

```
mocker push 镜像[:标签]
```

**示例：**

```bash
mocker push my-registry.io/myapp:latest
mocker push my-registry.io/myapp:v2.0
```

---

### images

列出本地镜像。

```
mocker images [选项]
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--quiet` | `-q` | 只显示镜像 ID |

**输出列：**

```
REPOSITORY   TAG   IMAGE ID   CREATED   SIZE
```

**示例：**

```bash
mocker images
mocker images -q

# 删除所有镜像（谨慎使用）
mocker rmi $(mocker images -q)
```

---

### build

从 Dockerfile 构建镜像。

```
mocker build [选项] 路径
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--tag` | `-t` | 镜像名称和可选标签（`名称:标签`） |
| `--file` | `-f` | Dockerfile 路径（默认：`Dockerfile`） |

**示例：**

```bash
# 在当前目录构建
mocker build -t myapp:latest .

# 指定 Dockerfile 路径
mocker build -t myapp:latest -f ./docker/Dockerfile.prod .

# 使用 Git 短哈希作为标签
mocker build -t my-registry.io/myapp:$(git rev-parse --short HEAD) .
```

---

### tag

为源镜像创建新标签。

```
mocker tag 源镜像 目标镜像
```

**示例：**

```bash
mocker tag nginx:latest my-registry.io/nginx:prod
mocker tag alpine:latest my-registry.io/base:latest
```

---

### rmi

删除一个或多个镜像。

```
mocker rmi 镜像 [镜像...]
```

**示例：**

```bash
mocker rmi alpine:latest
mocker rmi nginx:1.24 nginx:1.25

# 输出
# Untagged: alpine:latest
# Deleted: sha256:d67dd0f7...
```

---

## 网络命令

### network create

创建网络。

```
mocker network create [选项] 网络名
```

**选项：**

| 参数 | 说明 |
|------|------|
| `--driver` | 网络驱动（默认：`bridge`） |

**示例：**

```bash
mocker network create mynet
mocker network create --driver bridge backend
```

成功时返回网络 ID。

---

### network ls

列出网络。

```
mocker network ls
```

**输出列：**

```
NETWORK ID   NAME   DRIVER   SCOPE
```

---

### network rm

删除一个或多个网络。

```
mocker network rm 网络 [网络...]
```

---

### network inspect

显示网络详细信息。

```
mocker network inspect 网络
```

**输出格式：**

```json
{
  "id": "a69bb9f3bb64...",
  "name": "mynet",
  "driver": "bridge",
  "created": "2026-03-07T14:00:00Z",
  "containers": ["myapp", "mydb"],
  "labels": {}
}
```

---

### network connect

将容器连接到网络。

```
mocker network connect 网络 容器
```

---

### network disconnect

将容器从网络断开。

```
mocker network disconnect 网络 容器
```

---

## 卷命令

### volume create

创建卷。

```
mocker volume create [卷名]
```

在 `~/.mocker/volumes/<名称>/_data` 创建卷目录。

---

### volume ls

列出所有卷。

```
mocker volume ls
```

**输出列：**

```
DRIVER   VOLUME NAME
```

---

### volume rm

删除一个或多个卷。

```
mocker volume rm 卷 [卷...]
```

---

### volume inspect

显示卷详细信息。

```
mocker volume inspect 卷
```

**输出格式：**

```json
{
  "name": "pgdata",
  "driver": "local",
  "mountpoint": "/Users/you/.mocker/volumes/pgdata/_data",
  "created": "2026-03-07T14:00:00Z",
  "labels": {}
}
```

---

## Compose 命令

所有 Compose 子命令支持以下共享选项：

| 参数 | 简写 | 说明 |
|------|------|------|
| `--file` | `-f` | Compose 文件路径（默认：`docker-compose.yml`） |
| `--project-name` | `-p` | 项目名称（默认：目录名） |

### compose up

创建并启动 Compose 文件中定义的容器。

```
mocker compose [选项] up [--detach]
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--detach` | `-d` | 后台运行容器 |

```bash
mocker compose up -d
mocker compose -f staging.yml up -d
mocker compose -p myproject up -d
```

---

### compose down

停止并删除容器和网络。

```
mocker compose [选项] down
```

---

### compose ps

列出 Compose 项目的容器。

```
mocker compose [选项] ps
```

---

### compose logs

查看容器输出。

```
mocker compose [选项] logs [--follow] [服务名]
```

**选项：**

| 参数 | 说明 |
|------|------|
| `--follow` | 持续跟踪日志（无 `-f` 简写，避免与 `--file` 冲突） |

```bash
# 所有服务的日志
mocker compose logs

# 指定服务
mocker compose logs api

# 持续跟踪
mocker compose logs --follow api
```

---

### compose restart

重启服务容器。

```
mocker compose [选项] restart [服务名]
```

```bash
# 重启所有服务
mocker compose restart

# 重启指定服务
mocker compose restart api
```

---

## 系统命令

### system info

显示系统级信息。

```
mocker system info
```

**输出示例：**

```
Client:
 Version:    0.1.0
 Context:    default

Server:
 Containers: 3
  Running:   2
  Paused:    0
  Stopped:   1
 Images:     5
 Server Version: 0.1.0
 Storage Driver: json-file
 Operating System: macOS Version 26.0
 Architecture: arm64
 CPUs: 12
 Total Memory: 24.00GiB
 Docker Root Dir: /Users/you/.mocker
```

---

### system prune

删除未使用的容器和资源。

```
mocker system prune [选项]
```

**选项：**

| 参数 | 简写 | 说明 |
|------|------|------|
| `--force` | `-f` | 不询问确认直接执行 |

```bash
mocker system prune -f
```
