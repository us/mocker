# Docker Compose Guide

Mocker supports Docker Compose v2 syntax, letting you define and run multi-container applications from a single YAML file.

## Table of Contents

- [Compose File Format](#compose-file-format)
- [Services](#services)
- [Networks](#networks)
- [Volumes](#volumes)
- [Dependency Ordering](#dependency-ordering)
- [Environment Variables](#environment-variables)
- [Port Mappings](#port-mappings)
- [Build Configuration](#build-configuration)
- [Commands Reference](#commands-reference)
- [Project Naming](#project-naming)
- [Examples](#examples)

## Compose File Format

Mocker reads standard `docker-compose.yml` / `docker-compose.yaml` files.

```yaml
version: "3.8"   # Optional, informational

services:
  <service-name>:
    image: <image-reference>
    # or
    build: <context-path>
    # ... service options

networks:
  <network-name>:
    driver: bridge    # optional

volumes:
  <volume-name>:
    driver: local     # optional
```

## Services

Each service defines one container type. Supported fields:

```yaml
services:
  myservice:
    image: nginx:latest           # Image to use
    build: ./app                  # Or build from Dockerfile
    command: ["sh", "-c", "..."]  # Override CMD (array or string)
    ports:
      - "8080:80"
    environment:
      - KEY=value                 # List form
      KEY2: value2                # Map form
    volumes:
      - named-vol:/data
      - ./host/path:/container/path
      - ./config.yml:/app/config.yml:ro
    networks:
      - frontend
      - backend
    depends_on:
      - db                        # List form
    restart: always               # no | always | on-failure | unless-stopped
    labels:
      app: myservice
      env: production
```

### Build Configuration

```yaml
services:
  app:
    build:
      context: ./app
      dockerfile: Dockerfile.prod
```

Or shorthand:

```yaml
services:
  app:
    build: ./app   # Uses ./app/Dockerfile
```

## Networks

Define custom networks for container communication:

```yaml
networks:
  frontend:
    driver: bridge

  backend:
    driver: bridge

  # Minimal (uses defaults)
  internal:
```

Services on the same network can reach each other by service name.

## Volumes

Define named volumes for persistent data:

```yaml
volumes:
  db-data:
    driver: local

  app-uploads:
```

Reference in services:

```yaml
services:
  db:
    volumes:
      - db-data:/var/lib/postgresql/data
```

Volume data is stored at `~/.mocker/volumes/<project>-<name>/_data`.

## Dependency Ordering

Use `depends_on` to control startup order. Mocker performs a topological sort and starts services in dependency order:

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

Startup order: `db` + `cache` (parallel) → `api` → `web`

### Extended depends_on (condition)

```yaml
services:
  api:
    depends_on:
      db:
        condition: service_started
```

## Environment Variables

### List Form

```yaml
environment:
  - NODE_ENV=production
  - PORT=3000
  - DB_HOST=db
```

### Map Form

```yaml
environment:
  NODE_ENV: production
  PORT: "3000"
  DB_HOST: db
```

### Interpolation

Reference shell environment variables:

```yaml
environment:
  - API_KEY=${MY_API_KEY}
```

## Port Mappings

```yaml
ports:
  - "8080:80"           # host:container (TCP)
  - "8443:443/tcp"      # explicit TCP
  - "5353:53/udp"       # UDP
  - "127.0.0.1:6379:6379"  # bind to specific host IP
```

## Build Configuration

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    image: myapp:latest   # Tag the built image
```

## Commands Reference

### Starting Services

```bash
# Start all services detached
mocker compose up -d

# Start specific services only
# (not yet supported, starts all)
mocker compose up -d

# Use a non-default file
mocker compose -f docker-compose.prod.yml up -d

# Use a custom project name
mocker compose -p myproject up -d
```

### Viewing Status

```bash
mocker compose ps
```

```
NAME              IMAGE         SERVICE   STATUS
myapp-db-1        postgres:15   db        Up 2 minutes
myapp-api-1       node:20       api       Up 2 minutes
myapp-web-1       nginx:1.25    web       Up 2 minutes
```

### Viewing Logs

```bash
# All services
mocker compose logs

# Single service
mocker compose logs api

# Follow logs (streaming)
mocker compose logs --follow api
```

### Restarting Services

```bash
# Restart all
mocker compose restart

# Restart one service
mocker compose restart api
```

### Tearing Down

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

> Named volumes are **not** removed by `compose down`. Use `volume rm` explicitly.

## Project Naming

Container and resource names follow Docker Compose v2 convention:

```
<project>-<service>-<index>
```

Examples:
- Project `myapp`, service `web` → container `myapp-web-1`
- Project `myapp`, network `frontend` → `myapp-frontend`
- Project `myapp`, volume `pgdata` → `myapp-pgdata`

The project name defaults to the directory containing the compose file:

```bash
# File at /home/user/myapp/docker-compose.yml
# Project name: "myapp"
mocker compose up -d

# Override project name
mocker compose -p staging up -d
```

## Examples

### Web + API + Database

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

### Development Override

Use multiple compose files for environment-specific config:

```bash
# Base config
mocker compose -f docker-compose.yml up -d

# Override for staging
mocker compose -f docker-compose.yml -f docker-compose.staging.yml up -d
```

> **Note:** Multiple `-f` flags (file merging) are not yet supported. Use a single file per environment.

### Minimal Single-Service

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
