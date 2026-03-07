# Docker Compose 指南

Mocker 支持 Docker Compose v2 语法，让您通过单个 YAML 文件定义和运行多容器应用。

## 目录

- [Compose 文件格式](#compose-文件格式)
- [服务定义](#服务定义)
- [网络配置](#网络配置)
- [卷配置](#卷配置)
- [依赖顺序](#依赖顺序)
- [环境变量](#环境变量)
- [端口映射](#端口映射)
- [构建配置](#构建配置)
- [命令参考](#命令参考)
- [项目命名规则](#项目命名规则)
- [完整示例](#完整示例)

## Compose 文件格式

Mocker 读取标准的 `docker-compose.yml` / `docker-compose.yaml` 文件。

```yaml
version: "3.8"   # 可选，仅作说明用途

services:
  <服务名>:
    image: <镜像引用>
    # 或
    build: <构建上下文路径>
    # ... 其他服务配置

networks:
  <网络名>:
    driver: bridge    # 可选

volumes:
  <卷名>:
    driver: local     # 可选
```

## 服务定义

每个服务定义一种容器类型，支持以下字段：

```yaml
services:
  myservice:
    image: nginx:latest           # 使用的镜像
    build: ./app                  # 或从 Dockerfile 构建
    command: ["sh", "-c", "..."]  # 覆盖 CMD（数组或字符串）
    ports:
      - "8080:80"
    environment:
      - KEY=value                 # 列表形式
      KEY2: value2                # 映射形式
    volumes:
      - named-vol:/data
      - ./host/path:/container/path
      - ./config.yml:/app/config.yml:ro
    networks:
      - frontend
      - backend
    depends_on:
      - db                        # 列表形式
    restart: always               # no | always | on-failure | unless-stopped
    labels:
      app: myservice
      env: production
```

### 构建配置

```yaml
services:
  app:
    build:
      context: ./app
      dockerfile: Dockerfile.prod
```

简写形式：

```yaml
services:
  app:
    build: ./app   # 使用 ./app/Dockerfile
```

## 网络配置

定义自定义网络用于容器间通信：

```yaml
networks:
  frontend:
    driver: bridge

  backend:
    driver: bridge

  # 最简形式（使用默认值）
  internal:
```

处于同一网络的服务可以通过服务名互相访问。

## 卷配置

定义命名卷用于持久化数据：

```yaml
volumes:
  db-data:
    driver: local

  app-uploads:
```

在服务中引用：

```yaml
services:
  db:
    volumes:
      - db-data:/var/lib/postgresql/data
```

卷数据存储于 `~/.mocker/volumes/<项目>-<卷名>/_data`。

## 依赖顺序

使用 `depends_on` 控制启动顺序。Mocker 执行拓扑排序，按依赖顺序启动服务：

```yaml
services:
  web:
    depends_on:
      - api

  api:
    depends_on:
      - db
      - cache

  db:
    image: postgres:15

  cache:
    image: redis:alpine
```

启动顺序：`db` + `cache`（并行） → `api` → `web`

### 扩展 depends_on 语法（条件）

```yaml
services:
  api:
    depends_on:
      db:
        condition: service_started
```

## 环境变量

### 列表形式

```yaml
environment:
  - NODE_ENV=production
  - PORT=3000
  - DB_HOST=db
```

### 映射形式

```yaml
environment:
  NODE_ENV: production
  PORT: "3000"
  DB_HOST: db
```

### 变量插值

引用 Shell 环境变量：

```yaml
environment:
  - API_KEY=${MY_API_KEY}
```

## 端口映射

```yaml
ports:
  - "8080:80"               # 主机:容器（TCP）
  - "8443:443/tcp"          # 显式 TCP
  - "5353:53/udp"           # UDP
  - "127.0.0.1:6379:6379"   # 绑定到指定主机 IP
```

## 构建配置

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    image: myapp:latest   # 为构建的镜像打标签
```

## 命令参考

### 启动服务

```bash
# 后台启动所有服务
mocker compose up -d

# 使用非默认文件
mocker compose -f docker-compose.prod.yml up -d

# 指定项目名称
mocker compose -p myproject up -d
```

### 查看状态

```bash
mocker compose ps
```

```
NAME              IMAGE         SERVICE   STATUS
myapp-db-1        postgres:15   db        Up 2 minutes
myapp-api-1       node:20       api       Up 2 minutes
myapp-web-1       nginx:1.25    web       Up 2 minutes
```

### 查看日志

```bash
# 所有服务的日志
mocker compose logs

# 指定服务的日志
mocker compose logs api

# 持续跟踪日志
mocker compose logs --follow api
```

### 重启服务

```bash
# 重启所有服务
mocker compose restart

# 重启指定服务
mocker compose restart api
```

### 停止并清理

```bash
mocker compose down
```

```
[+] Running 6/6
 ✔ Container myapp-web-1    Stopped
 ✔ Container myapp-web-1    Removed
 ✔ Container myapp-api-1    Stopped
 ✔ Container myapp-api-1    Removed
 ✔ Container myapp-db-1     Stopped
 ✔ Container myapp-db-1     Removed
 ✔ Network myapp-frontend   Removed
 ✔ Network myapp-backend    Removed
```

> 命名卷在 `compose down` 时**不会**被删除。如需删除，请使用 `volume rm` 命令。

## 项目命名规则

容器和资源名称遵循 Docker Compose v2 规范：

```
<项目名>-<服务名>-<编号>
```

示例：
- 项目 `myapp`，服务 `web` → 容器 `myapp-web-1`
- 项目 `myapp`，网络 `frontend` → `myapp-frontend`
- 项目 `myapp`，卷 `pgdata` → `myapp-pgdata`

项目名默认为 Compose 文件所在目录名：

```bash
# 文件位于 /home/user/myapp/docker-compose.yml
# 项目名：myapp
mocker compose up -d

# 覆盖项目名
mocker compose -p staging up -d
```

## 完整示例

### Web + API + 数据库

```yaml
version: "3.8"

services:
  web:
    image: nginx:1.25
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api
    networks:
      - public

  api:
    image: myapp:latest
    environment:
      - DATABASE_URL=postgres://user:pass@db:5432/myapp
      - REDIS_URL=redis://cache:6379
    depends_on:
      - db
      - cache
    networks:
      - public
      - private

  db:
    image: postgres:15
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: myapp
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - private

  cache:
    image: redis:alpine
    networks:
      - private

networks:
  public:
  private:

volumes:
  pgdata:
```

### 最简单服务配置

```yaml
version: "3.8"
services:
  app:
    image: myapp:latest
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
```

```bash
mocker compose up -d
mocker compose logs --follow app
mocker compose down
```
