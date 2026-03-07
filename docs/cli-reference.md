# CLI Reference

Complete reference for all Mocker commands and flags.

## Table of Contents

- [Global Options](#global-options)
- [Container Commands](#container-commands)
  - [run](#run)
  - [ps](#ps)
  - [stop](#stop)
  - [rm](#rm)
  - [exec](#exec)
  - [logs](#logs)
  - [inspect](#inspect)
  - [stats](#stats)
- [Image Commands](#image-commands)
  - [pull](#pull)
  - [push](#push)
  - [images](#images)
  - [build](#build)
  - [tag](#tag)
  - [rmi](#rmi)
- [Network Commands](#network-commands)
  - [network create](#network-create)
  - [network ls](#network-ls)
  - [network rm](#network-rm)
  - [network inspect](#network-inspect)
  - [network connect](#network-connect)
  - [network disconnect](#network-disconnect)
- [Volume Commands](#volume-commands)
  - [volume create](#volume-create)
  - [volume ls](#volume-ls)
  - [volume rm](#volume-rm)
  - [volume inspect](#volume-inspect)
- [Compose Commands](#compose-commands)
  - [compose up](#compose-up)
  - [compose down](#compose-down)
  - [compose ps](#compose-ps)
  - [compose logs](#compose-logs)
  - [compose restart](#compose-restart)
- [System Commands](#system-commands)
  - [system info](#system-info)
  - [system prune](#system-prune)

---

## Global Options

```
mocker [OPTIONS] <COMMAND>

Options:
  --version    Show the version and exit
  -h, --help   Show help information
```

---

## Container Commands

### run

Create and start a new container.

```
mocker run [OPTIONS] IMAGE [COMMAND [ARG...]]
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--detach` | `-d` | Run container in background, print container ID |
| `--name` | | Assign a name to the container |
| `--publish` | `-p` | Publish a container's port(s) to the host (`host:container[/proto]`) |
| `--env` | `-e` | Set environment variables |
| `--volume` | `-v` | Bind mount a volume (`host:container[:ro]` or named `vol:container`) |
| `--label` | `-l` | Set metadata on a container |
| `--restart` | | Restart policy (`no`, `always`, `on-failure`, `unless-stopped`) |
| `--network` | | Connect a container to a network |
| `--rm` | | Automatically remove the container when it exits |

**Examples:**

```bash
# Simple run
mocker run alpine:latest

# Detached with name and port
mocker run -d --name web -p 8080:80 nginx:latest

# With environment variables
mocker run -d -e DB_HOST=localhost -e DB_PORT=5432 myapp:latest

# With bind mount (read-only)
mocker run -d -v /host/config:/app/config:ro myapp:latest

# With named volume
mocker run -d -v pgdata:/var/lib/postgresql/data postgres:15

# With restart policy
mocker run -d --restart always --name db postgres:15

# Multiple ports
mocker run -d -p 80:80 -p 443:443 -p 8080:8080 nginx:latest
```

**Port format:** `[hostIP:]hostPort:containerPort[/protocol]`
- `8080:80` → host port 8080 maps to container port 80 (TCP)
- `8080:80/udp` → UDP protocol
- `127.0.0.1:8080:80` → bind to specific host IP

---

### ps

List containers.

```
mocker ps [OPTIONS]
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all containers (default shows only running) |
| `--quiet` | `-q` | Only display container IDs |

**Output columns:**

```
CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES
```

**Examples:**

```bash
# Running containers only
mocker ps

# All containers (including stopped)
mocker ps -a

# IDs only (useful for scripting)
mocker ps -q

# Stop all running containers
mocker stop $(mocker ps -q)
```

---

### stop

Stop one or more running containers.

```
mocker stop CONTAINER [CONTAINER...]
```

Echoes back each container identifier on success.

**Examples:**

```bash
mocker stop myapp
mocker stop container1 container2 container3

# Stop all running containers
mocker stop $(mocker ps -q)
```

---

### rm

Remove one or more containers.

```
mocker rm [OPTIONS] CONTAINER [CONTAINER...]
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Force the removal of a running container |

**Examples:**

```bash
# Remove a stopped container
mocker rm myapp

# Force remove a running container
mocker rm -f myapp

# Remove multiple
mocker rm container1 container2

# Remove all stopped containers
mocker rm $(mocker ps -aq)
```

**Error cases:**
- Removing a running container without `-f`: `Error response from daemon: You cannot remove a running container...`
- Container not found: `Error response from daemon: No such container: <name>`

---

### exec

Execute a command in a running container.

```
mocker exec [OPTIONS] CONTAINER COMMAND [ARG...]
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--interactive` | `-i` | Keep STDIN open |
| `--tty` | `-t` | Allocate a pseudo-TTY |

**Examples:**

```bash
mocker exec myapp env
mocker exec myapp ps aux
mocker exec -it myapp sh
```

---

### logs

Fetch the logs of a container.

```
mocker logs [OPTIONS] CONTAINER
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--follow` | `-f` | Follow log output |
| `--tail` | | Number of lines to show from the end |
| `--timestamps` | `-t` | Show timestamps |

**Examples:**

```bash
mocker logs myapp
mocker logs -f myapp
mocker logs --tail 100 myapp
```

---

### inspect

Return low-level information on containers or images.

```
mocker inspect TARGET [TARGET...]
```

Returns a JSON array. Automatically detects whether the target is a container or image.

**Examples:**

```bash
# Inspect a container
mocker inspect myapp

# Inspect an image
mocker inspect alpine:latest

# Inspect multiple targets
mocker inspect myapp postgres:15

# Pretty-print with jq
mocker inspect myapp | jq '.[0].state'
```

**Output format:**

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

Display a live stream of container resource usage statistics.

```
mocker stats [OPTIONS] [CONTAINER...]
```

**Options:**

| Flag | Description |
|------|-------------|
| `--no-stream` | Disable streaming stats and only pull the first result |

**Output columns:**

```
CONTAINER ID   NAME   CPU %   MEM USAGE / LIMIT   MEM %   NET I/O   BLOCK I/O   PIDS
```

**Examples:**

```bash
# All containers (streaming)
mocker stats

# One-shot snapshot
mocker stats --no-stream

# Specific containers
mocker stats myapp mydb
```

---

## Image Commands

### pull

Download an image from a registry.

```
mocker pull IMAGE[:TAG]
```

Idempotent — re-pulling an existing image shows "Image is up to date" without creating duplicates.

**Examples:**

```bash
mocker pull alpine               # Uses :latest tag
mocker pull nginx:1.25
mocker pull registry.example.com/myapp:v2.0
```

**Output:**

```
1.25: Pulling from nginx
a1b2c3d4e5f6: Pull complete
Digest: sha256:...
Status: Downloaded newer image for nginx:1.25
nginx:1.25
```

---

### push

Upload an image to a registry.

```
mocker push IMAGE[:TAG]
```

**Examples:**

```bash
mocker push my-registry.io/myapp:latest
mocker push my-registry.io/myapp:v2.0
```

---

### images

List local images.

```
mocker images [OPTIONS]
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--quiet` | `-q` | Only show image IDs |

**Output columns:**

```
REPOSITORY   TAG   IMAGE ID   CREATED   SIZE
```

**Examples:**

```bash
mocker images
mocker images -q

# Remove all images (use with caution)
mocker rmi $(mocker images -q)
```

---

### build

Build an image from a Dockerfile.

```
mocker build [OPTIONS] PATH
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--tag` | `-t` | Name and optionally a tag (`name:tag`) |
| `--file` | `-f` | Name of the Dockerfile (default: `Dockerfile`) |

**Examples:**

```bash
# Build in current directory
mocker build -t myapp:latest .

# Specify Dockerfile path
mocker build -t myapp:latest -f ./docker/Dockerfile.prod .

# Build with version tag
mocker build -t my-registry.io/myapp:$(git rev-parse --short HEAD) .
```

---

### tag

Create a tag that refers to a source image.

```
mocker tag SOURCE_IMAGE TARGET_IMAGE
```

**Examples:**

```bash
mocker tag nginx:latest my-registry.io/nginx:prod
mocker tag alpine:latest my-registry.io/base:latest
```

---

### rmi

Remove one or more images.

```
mocker rmi IMAGE [IMAGE...]
```

**Examples:**

```bash
mocker rmi alpine:latest
mocker rmi nginx:1.24 nginx:1.25

# Output
# Untagged: alpine:latest
# Deleted: sha256:d67dd0f7...
```

---

## Network Commands

### network create

Create a network.

```
mocker network create [OPTIONS] NETWORK
```

**Options:**

| Flag | Description |
|------|-------------|
| `--driver` | Driver to manage the network (default: `bridge`) |

**Examples:**

```bash
mocker network create mynet
mocker network create --driver bridge backend
```

Returns the network ID on success.

---

### network ls

List networks.

```
mocker network ls
```

**Output columns:**

```
NETWORK ID   NAME   DRIVER   SCOPE
```

---

### network rm

Remove one or more networks.

```
mocker network rm NETWORK [NETWORK...]
```

```bash
mocker network rm mynet
mocker network rm net1 net2
```

---

### network inspect

Display detailed information on a network.

```
mocker network inspect NETWORK
```

**Output format:**

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

Connect a container to a network.

```
mocker network connect NETWORK CONTAINER
```

```bash
mocker network connect mynet myapp
```

---

### network disconnect

Disconnect a container from a network.

```
mocker network disconnect NETWORK CONTAINER
```

```bash
mocker network disconnect mynet myapp
```

---

## Volume Commands

### volume create

Create a volume.

```
mocker volume create [VOLUME]
```

Creates the volume directory at `~/.mocker/volumes/<name>/_data`.

```bash
mocker volume create pgdata
mocker volume create app-uploads
```

---

### volume ls

List volumes.

```
mocker volume ls
```

**Output columns:**

```
DRIVER   VOLUME NAME
```

---

### volume rm

Remove one or more volumes.

```
mocker volume rm VOLUME [VOLUME...]
```

```bash
mocker volume rm pgdata
mocker volume rm vol1 vol2
```

---

### volume inspect

Display detailed information about a volume.

```
mocker volume inspect VOLUME
```

**Output format:**

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

## Compose Commands

All compose subcommands accept these shared options:

| Flag | Short | Description |
|------|-------|-------------|
| `--file` | `-f` | Compose file path (default: `docker-compose.yml`) |
| `--project-name` | `-p` | Project name (default: directory name) |

### compose up

Create and start containers defined in a Compose file.

```
mocker compose [OPTIONS] up [--detach]
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--detach` | `-d` | Run containers in the background |

```bash
mocker compose up -d
mocker compose -f staging.yml up -d
mocker compose -p myproject up -d
```

Services start in dependency order (respects `depends_on`). Named networks and volumes are created automatically.

---

### compose down

Stop and remove containers and networks.

```
mocker compose [OPTIONS] down
```

```bash
mocker compose down
mocker compose -f staging.yml down
```

---

### compose ps

List containers for the Compose project.

```
mocker compose [OPTIONS] ps
```

**Output columns:**

```
NAME   IMAGE   COMMAND   SERVICE   CREATED   STATUS   PORTS
```

---

### compose logs

View output from containers.

```
mocker compose [OPTIONS] logs [--follow] [SERVICE]
```

**Options:**

| Flag | Description |
|------|-------------|
| `--follow` | Follow log output (no `-f` shorthand to avoid conflict with `--file`) |

```bash
# All services
mocker compose logs

# Specific service
mocker compose logs api

# Follow a specific service
mocker compose logs --follow api
```

---

### compose restart

Restart service containers.

```
mocker compose [OPTIONS] restart [SERVICE]
```

```bash
# Restart all services
mocker compose restart

# Restart a specific service
mocker compose restart api
```

---

## System Commands

### system info

Display system-wide information.

```
mocker system info
```

**Output:**

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

Remove unused containers and resources.

```
mocker system prune [OPTIONS]
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Do not prompt for confirmation |

```bash
mocker system prune -f
```
