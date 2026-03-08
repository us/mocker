---
title: Compose Guide
---

# Compose Guide

Mocker supports Docker Compose v2 syntax for defining and running multi-container applications.

---

## File Format

Mocker reads standard `docker-compose.yml` / `docker-compose.yaml` files.

```yaml
version: "3.8"   # optional

services:
  <name>:
    image: <image>      # use an existing image
    build: <path>       # or build from a Dockerfile

networks:
  <name>:
    driver: bridge

volumes:
  <name>:
    driver: local
```

---

## Services

Supported fields per service:

```yaml
services:
  myservice:
    image: nginx:latest
    build: ./app              # or build config (see below)
    command: ["sh", "-c", "..."]
    ports:
      - "8080:80"
      - "443:443/tcp"
    environment:
      - KEY=value             # list form
      KEY2: value2            # map form
      SECRET: ${MY_SECRET}    # interpolation from .env or shell
    volumes:
      - ./host/path:/container/path
      - ./config.yml:/app/config.yml:ro
    networks:
      - frontend
      - backend
    depends_on:
      - db
    restart: always
    labels:
      app: myservice
```

### Build configuration

```yaml
services:
  app:
    build:
      context: ./app
      dockerfile: Dockerfile.prod
```

Shorthand (uses `./app/Dockerfile`):

```yaml
services:
  app:
    build: ./app
```

---

## Environment Variables

### Interpolation

Reference variables from shell or `.env` file:

```yaml
environment:
  - DB_PASSWORD=${DB_PASSWORD:-secret}
  - API_KEY=${MY_API_KEY}
```

Mocker loads `.env` from the same directory as the compose file. Shell environment takes priority over `.env`.

---

## Networking

Services on the same network can reach each other by service name:

```yaml
services:
  api:
    environment:
      - DB_HOST=db     # resolves to the db service

networks:
  backend:
    driver: bridge
```

---

## Dependency Ordering

`depends_on` controls startup order. Mocker performs a topological sort:

```yaml
services:
  web:
    depends_on: [api]
  api:
    depends_on: [db, cache]
  db:
    image: postgres:15
  cache:
    image: redis:alpine
```

Startup order: `db` + `cache` → `api` → `web`

---

## Project Naming

Container and resource names follow Docker Compose v2 convention:

```
<project>-<service>-<index>
```

The project name defaults to the directory containing the compose file. Override with `-p`:

```bash
mocker compose -p staging up -d
```

| Resource | Name |
|----------|------|
| Container | `myapp-web-1` |
| Network | `myapp-frontend` |
| Volume | `myapp-pgdata` |

---

## Commands

### Start services

```bash
mocker compose up -d
mocker compose up -d postgres api     # specific services only
mocker compose -f staging.yml up -d
mocker compose -p myproject up -d
```

### Check status

```bash
mocker compose ps
```

### View logs

```bash
mocker compose logs
mocker compose logs api
mocker compose logs --follow api
```

### Restart

```bash
mocker compose restart
mocker compose restart api
```

### Force stop

```bash
mocker compose kill
mocker compose kill api
```

### Tear down

```bash
mocker compose down
```

---

## Example: Web + API + Database

```yaml
version: "3.8"

services:
  web:
    image: nginx:1.25
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on: [api]
    networks: [public]

  api:
    image: myapp:latest
    environment:
      - DATABASE_URL=postgres://user:pass@db:5432/myapp
      - REDIS_URL=redis://cache:6379
    depends_on: [db, cache]
    networks: [public, private]

  db:
    image: postgres:15
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: myapp
    networks: [private]

  cache:
    image: redis:alpine
    networks: [private]

networks:
  public:
  private:
```

```bash
mocker compose up -d
mocker compose ps
mocker compose down
```
