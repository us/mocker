---
title: Getting Started
---

# Getting Started

This guide walks you through installing Mocker and running your first containers.

---

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

---

## Installation

### Build from Source (Recommended)

```bash
git clone https://github.com/us/mocker.git
cd mocker

# Build in release mode
swift build -c release

# Install the binary
sudo cp .build/release/mocker /usr/local/bin/mocker

# Sign with required virtualization entitlement
codesign --force --sign - --timestamp=none \
  --entitlements Entitlements.plist \
  /usr/local/bin/mocker

# Verify
mocker --version
# 0.1.0
```

### Development Build

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

---

## Your First Container

### Step 1: Pull an image

```bash
mocker pull alpine:latest
```

Output:
```
latest: Pulling from alpine
a1b2c3d4e5f6: Pull complete
Digest: sha256:...
Status: Downloaded newer image for alpine:latest
alpine:latest
```

### Step 2: Run a container

Run in detached mode (background):

```bash
mocker run -d --name my-nginx -p 8080:80 nginx:latest
```

The command prints the full container ID:
```
b8482c2a83c8daa383292a1fcee6262b600b18d87bc84197db05b24c4c73dd69
```

### Step 3: Verify it's running

```bash
mocker ps
```

```
CONTAINER ID   IMAGE          COMMAND   CREATED        STATUS                  PORTS          NAMES
b8482c2a83c8   nginx:latest             3 seconds ago  Up Less than a second   8080:80/tcp    my-nginx
```

### Step 4: View logs

```bash
mocker logs my-nginx
```

### Step 5: Stop and clean up

```bash
mocker stop my-nginx
mocker rm my-nginx
```

---

## Managing Images

### Pull images

```bash
# Latest tag (implicit)
mocker pull ubuntu

# Specific version
mocker pull node:20-alpine

# From a custom registry
mocker pull registry.example.com/myapp:v2.1.0
```

### List images

```bash
mocker images
```

```
REPOSITORY   TAG        IMAGE ID       CREATED    SIZE
node         20-alpine  sha256:abc12   2 min ago  Zero KB
ubuntu       latest     sha256:def34   5 min ago  Zero KB
```

### Tag and retag

```bash
mocker tag ubuntu:latest my-registry.io/ubuntu:22.04
mocker images
```

### Remove images

```bash
mocker rmi ubuntu:latest
# Untagged: ubuntu:latest
# Deleted: sha256:def34...
```

---

## Working with Compose

Compose lets you define and run multi-container applications from a single YAML file.

### Create a Compose file

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

### Start all services

```bash
mocker compose up -d
```

```
[+] Running 3/3
 ✔ Container myapp-db-1    Started
 ✔ Container myapp-app-1   Started
 ✔ Container myapp-web-1   Started
```

> Services start in dependency order automatically. `db` starts first, then `app`, then `web`.

### Check status

```bash
mocker compose ps
```

```
NAME            IMAGE          SERVICE   CREATED        STATUS
myapp-db-1      postgres:15    db        5s ago         Up Less than a second
myapp-app-1     node:20-alpine app       5s ago         Up Less than a second
myapp-web-1     nginx:latest   web       5s ago         Up Less than a second
```

### View logs

```bash
# All services
mocker compose logs

# Specific service
mocker compose logs app
```

### Tear down

```bash
mocker compose down
```

---

## Next Steps

- [CLI Reference](cli-reference.md) — full documentation of every command and flag
- [Compose Guide](compose.md) — advanced Compose features
- [Architecture](architecture.md) — how Mocker works internally
- [Contributing](contributing.md) — help improve Mocker
