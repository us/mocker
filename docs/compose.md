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
name: <project>  # optional, sets the project name

include:         # optional, pulls in other compose files
  - <path>

services:
  <name>:
    image: <image>      # use an existing image
    build: <path>       # or build from a Dockerfile

networks:
  <name>:
    driver: bridge
    external: true      # declared elsewhere: joined, never created or removed
    name: <real-name>   # explicit name, used verbatim without the project prefix

volumes:
  <name>:
    driver: local
    external: true      # declared elsewhere: never created or removed by mocker
    name: <real-name>   # explicit name, used verbatim without the project prefix
```

### include

Split a project across files with the Compose `include` element, in short or long form:

```yaml
include:
  - services/database.yml
  - path: services/api.yml
    project_directory: .
    env_file: .env.api
```

Relative paths inside an included file resolve against that entry's
`project_directory`, which defaults to the directory of the included file. Each
included file interpolates variables from its own `env_file` (default: `.env`
beside it). The including file's own definitions win over anything it includes.

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

Mocker loads `.env` from the project directory (`--project-directory`, otherwise the
directory of the first `-f` file). Shell environment takes priority over `.env`.

---

## Networking

Networks declared in the file are created in the container runtime and services are
attached to them. A service joins one network — the runtime attaches a container to a
single network, so a service listing several joins the first and says so.

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

The project name is resolved in this order, first match wins:

1. `-p` / `--project-name`
2. `COMPOSE_PROJECT_NAME` in the environment
3. `COMPOSE_PROJECT_NAME` in the project directory's `.env`
4. top-level `name:` in the compose file
5. the project directory's name

The resolved name is lowercased, and any character outside `[a-z0-9_-]` becomes a dash.
`mocker compose config` prints the name it resolved.

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

# also remove the project's named volumes
mocker compose down -v
```

`-v` removes the volumes declared in the top-level `volumes:` section. Volumes marked
`external: true` are never removed.

```bash
# also remove the services' images
mocker compose down --rmi local   # only images compose built
mocker compose down --rmi all     # pulled images too
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
