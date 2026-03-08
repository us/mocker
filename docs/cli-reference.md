---
title: CLI Reference
---

# CLI Reference

Complete reference for all Mocker commands and flags.

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

### `mocker run`

Create and start a new container.

```bash
mocker run [OPTIONS] IMAGE [COMMAND [ARG...]]
```

**Flags:**
```
-d, --detach          Run container in background
    --name            Assign a name to the container
-p, --publish         Publish a port (host:container[/proto])
-e, --env             Set environment variables
-v, --volume          Bind mount a volume (host:container[:ro])
-l, --label           Set metadata on a container
    --restart         Restart policy (no|always|on-failure|unless-stopped)
    --network         Connect to a network
    --rm              Remove the container when it exits
```

**Examples:**
```bash
# Detached with name and port
mocker run -d --name web -p 8080:80 nginx:latest

# With environment variables
mocker run -d -e DB_HOST=localhost -e DB_PORT=5432 myapp:latest

# With bind mount
mocker run -d -v /host/config:/app/config:ro myapp:latest

# With restart policy
mocker run -d --restart always --name db postgres:15
```

---

### `mocker ps`

List containers.

```bash
mocker ps [OPTIONS]
```

**Flags:**
```
-a, --all     Show all containers (default: only running)
-q, --quiet   Only display container IDs
```

**Examples:**
```bash
mocker ps
mocker ps -a
mocker ps -q

# Stop all running containers
mocker stop $(mocker ps -q)
```

---

### `mocker stop`

Stop one or more running containers.

```bash
mocker stop CONTAINER [CONTAINER...]
```

**Examples:**
```bash
mocker stop myapp
mocker stop container1 container2

# Stop all running containers
mocker stop $(mocker ps -q)
```

---

### `mocker rm`

Remove one or more containers.

```bash
mocker rm [OPTIONS] CONTAINER [CONTAINER...]
```

**Flags:**
```
-f, --force   Force remove a running container
```

**Examples:**
```bash
mocker rm myapp
mocker rm -f myapp
mocker rm $(mocker ps -aq)
```

---

### `mocker exec`

Execute a command in a running container.

```bash
mocker exec [OPTIONS] CONTAINER COMMAND [ARG...]
```

**Flags:**
```
-i, --interactive   Keep STDIN open
-t, --tty           Allocate a pseudo-TTY
```

**Examples:**
```bash
mocker exec myapp env
mocker exec -it myapp sh
```

---

### `mocker logs`

Fetch the logs of a container.

```bash
mocker logs [OPTIONS] CONTAINER
```

**Flags:**
```
-f, --follow       Follow log output
    --tail         Number of lines to show from the end
-t, --timestamps   Show timestamps
```

**Examples:**
```bash
mocker logs myapp
mocker logs -f myapp
mocker logs --tail 100 myapp
```

---

### `mocker inspect`

Return low-level information on containers or images.

```bash
mocker inspect TARGET [TARGET...]
```

Always returns a JSON array, even for a single target.

**Examples:**
```bash
mocker inspect myapp
mocker inspect alpine:latest
mocker inspect myapp | jq '.[0].state'
```

---

### `mocker stats`

Display resource usage statistics for containers.

```bash
mocker stats [OPTIONS] [CONTAINER...]
```

**Flags:**
```
--no-stream   Only pull the first result (no live stream)
```

**Examples:**
```bash
mocker stats
mocker stats --no-stream
mocker stats myapp mydb
```

---

## Image Commands

### `mocker pull`

Download an image from a registry.

```bash
mocker pull IMAGE[:TAG]
```

**Examples:**
```bash
mocker pull alpine
mocker pull nginx:1.25
mocker pull registry.example.com/myapp:v2.0
```

---

### `mocker push`

Upload an image to a registry.

```bash
mocker push IMAGE[:TAG]
```

**Examples:**
```bash
mocker push my-registry.io/myapp:latest
mocker push my-registry.io/myapp:v2.0
```

---

### `mocker images`

List local images.

```bash
mocker images [OPTIONS]
```

**Flags:**
```
-q, --quiet   Only show image IDs
```

**Examples:**
```bash
mocker images
mocker images -q
mocker rmi $(mocker images -q)
```

---

### `mocker build`

Build an image from a Dockerfile.

```bash
mocker build [OPTIONS] PATH
```

**Flags:**
```
-t, --tag    Name and tag (name:tag)
-f, --file   Dockerfile path (default: Dockerfile in build context)
```

**Examples:**
```bash
mocker build -t myapp:latest .
mocker build -t myapp:latest -f ./docker/Dockerfile.prod .
mocker build -t my-registry.io/myapp:$(git rev-parse --short HEAD) .
```

---

### `mocker tag`

Create a tag pointing to a source image.

```bash
mocker tag SOURCE_IMAGE TARGET_IMAGE
```

**Examples:**
```bash
mocker tag nginx:latest my-registry.io/nginx:prod
mocker tag alpine:latest my-registry.io/base:latest
```

---

### `mocker rmi`

Remove one or more images.

```bash
mocker rmi IMAGE [IMAGE...]
```

**Examples:**
```bash
mocker rmi alpine:latest
mocker rmi nginx:1.24 nginx:1.25
```

---

## Network Commands

### `mocker network create`

Create a network.

```bash
mocker network create [OPTIONS] NETWORK
```

**Flags:**
```
--driver   Driver to manage the network (default: bridge)
```

**Examples:**
```bash
mocker network create mynet
mocker network create --driver bridge backend
```

---

### `mocker network ls`

List networks.

```bash
mocker network ls
```

---

### `mocker network rm`

Remove one or more networks.

```bash
mocker network rm NETWORK [NETWORK...]
```

**Examples:**
```bash
mocker network rm mynet
mocker network rm net1 net2
```

---

### `mocker network inspect`

Display detailed information on a network.

```bash
mocker network inspect NETWORK
```

---

### `mocker network connect`

Connect a container to a network.

```bash
mocker network connect NETWORK CONTAINER
```

---

### `mocker network disconnect`

Disconnect a container from a network.

```bash
mocker network disconnect NETWORK CONTAINER
```

---

## Volume Commands

### `mocker volume create`

Create a volume. Data is stored at `~/.mocker/volumes/<name>/_data`.

```bash
mocker volume create [VOLUME]
```

**Examples:**
```bash
mocker volume create pgdata
mocker volume create app-uploads
```

---

### `mocker volume ls`

List volumes.

```bash
mocker volume ls
```

---

### `mocker volume rm`

Remove one or more volumes.

```bash
mocker volume rm VOLUME [VOLUME...]
```

**Examples:**
```bash
mocker volume rm pgdata
mocker volume rm vol1 vol2
```

---

### `mocker volume inspect`

Display detailed information about a volume.

```bash
mocker volume inspect VOLUME
```

---

## Compose Commands

All compose subcommands share these options:

```
-f, --file           Compose file path (default: docker-compose.yml)
-p, --project-name   Project name (default: directory name)
```

### `mocker compose up`

Create and start containers defined in a Compose file.

```bash
mocker compose [OPTIONS] up [--detach] [SERVICE...]
```

**Flags:**
```
-d, --detach   Run containers in the background
```

**Examples:**
```bash
mocker compose up -d
mocker compose up -d postgres api
mocker compose -f staging.yml up -d
mocker compose -p myproject up -d
```

Services start in dependency order (`depends_on`). Networks and volumes are created automatically.

---

### `mocker compose down`

Stop and remove containers and networks.

```bash
mocker compose [OPTIONS] down
```

**Examples:**
```bash
mocker compose down
mocker compose -f staging.yml down
```

---

### `mocker compose ps`

List containers for the Compose project.

```bash
mocker compose [OPTIONS] ps
```

---

### `mocker compose logs`

View output from containers.

```bash
mocker compose [OPTIONS] logs [--follow] [SERVICE]
```

**Flags:**
```
--follow   Follow log output
```

**Examples:**
```bash
mocker compose logs
mocker compose logs api
mocker compose logs --follow api
```

---

### `mocker compose restart`

Restart service containers.

```bash
mocker compose [OPTIONS] restart [SERVICE]
```

**Examples:**
```bash
mocker compose restart
mocker compose restart api
```

---

### `mocker compose kill`

Force stop service containers.

```bash
mocker compose [OPTIONS] kill [SERVICE]
```

**Examples:**
```bash
mocker compose kill
mocker compose kill api
```

---

## System Commands

### `mocker system info`

Display system-wide information.

```bash
mocker system info
```

---

### `mocker system prune`

Remove stopped containers and unused resources.

```bash
mocker system prune [OPTIONS]
```

**Flags:**
```
-f, --force   Do not prompt for confirmation
```

**Examples:**
```bash
mocker system prune -f
```
