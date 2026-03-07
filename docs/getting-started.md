# Getting Started with Mocker

This guide walks you through installing Mocker and running your first containers.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Your First Container](#your-first-container)
- [Managing Images](#managing-images)
- [Working with Compose](#working-with-compose)
- [Next Steps](#next-steps)

## Prerequisites

Before installing Mocker, ensure you have:

| Requirement | Version | Notes |
|-------------|---------|-------|
| macOS | 26.0+ | Required for Apple Containerization framework |
| Swift | 6.0+ | [Download from swift.org](https://swift.org/download) |
| Xcode | 16.0+ | Or Command Line Tools only |

Check your Swift version:

```bash
swift --version
# Swift version 6.0.x (swift-6.0.x-RELEASE)
```

## Installation

### Option 1: Build from Source (Recommended)

```bash
# Clone the repository
git clone https://github.com/yourname/mocker.git
cd mocker

# Build in release mode
swift build -c release

# Install the binary
sudo cp .build/release/mocker /usr/local/bin/mocker

# Verify
mocker --version
# 0.1.0
```

### Option 2: Development Build

For development, use `swift run` directly — no installation needed:

```bash
swift run mocker --help
```

### Shell Completion

Generate completion scripts for your shell:

```bash
# Bash
mocker --generate-completion-script bash >> ~/.bashrc

# Zsh
mocker --generate-completion-script zsh >> ~/.zshrc

# Fish
mocker --generate-completion-script fish > ~/.config/fish/completions/mocker.fish
```

## Your First Container

### Step 1: Pull an Image

```bash
mocker pull alpine:latest
```

Output:
```
latest: Pulling from alpine
a1b2c3d4e5f6: Pull complete
b2c3d4e5f6a1: Pull complete
c3d4e5f6a1b2: Pull complete
Digest: sha256:...
Status: Downloaded newer image for alpine:latest
alpine:latest
```

### Step 2: Run a Container

Run a container in **detached mode** (background):

```bash
mocker run -d --name my-nginx -p 8080:80 nginx:latest
```

The command prints the full container ID:
```
b8482c2a83c8daa383292a1fcee6262b600b18d87bc84197db05b24c4c73dd69
```

### Step 3: Verify It's Running

```bash
mocker ps
```

```
CONTAINER ID   IMAGE          COMMAND   CREATED        STATUS                  PORTS          NAMES
b8482c2a83c8   nginx:latest             3 seconds ago  Up Less than a second   8080:80/tcp    my-nginx
```

### Step 4: View Logs

```bash
mocker logs my-nginx
```

### Step 5: Stop and Clean Up

```bash
mocker stop my-nginx
mocker rm my-nginx
```

## Managing Images

### Pull Images

```bash
# Latest tag (implicit)
mocker pull ubuntu

# Specific version
mocker pull node:20-alpine

# From a custom registry
mocker pull registry.example.com/myapp:v2.1.0
```

### List Images

```bash
mocker images
```

```
REPOSITORY   TAG        IMAGE ID       CREATED    SIZE
node         20-alpine  sha256:abc12   2 min ago  Zero KB
ubuntu       latest     sha256:def34   5 min ago  Zero KB
```

### Tag and Retag

```bash
# Tag for a private registry
mocker tag ubuntu:latest my-registry.io/ubuntu:22.04

# Verify
mocker images
```

### Remove Images

```bash
# Remove by reference
mocker rmi ubuntu:latest

# Output
# Untagged: ubuntu:latest
# Deleted: sha256:def34...
```

## Working with Compose

Compose lets you define and run multi-container applications.

### Create a Compose File

Save as `docker-compose.yml`:

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

### Start All Services

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

> **Tip:** Services start in dependency order automatically. `db` starts first, then `app`, then `web`.

### Check Status

```bash
mocker compose ps
```

```
NAME            IMAGE          SERVICE   CREATED        STATUS
myapp-db-1      postgres:15    db        5s ago         Up Less than a second
myapp-app-1     node:20-alpine app       5s ago         Up Less than a second
myapp-web-1     nginx:latest   web       5s ago         Up Less than a second
```

### View Logs

```bash
# All services
mocker compose logs

# Specific service
mocker compose logs app
```

### Tear Down

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

## Next Steps

- [CLI Reference](cli-reference.md) — Full documentation of every command and flag
- [Compose Guide](compose.md) — Advanced Compose features
- [Architecture](architecture.md) — How Mocker works internally
- [Contributing](contributing.md) — Help improve Mocker
