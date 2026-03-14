# Mocker CLI — Complete Command Reference

Docker-compatible container management tool built on Apple Containerization framework (macOS 26+).

> **111 commands & subcommands** — full flag compatibility with Docker CLI.

---

## Table of Contents

- [Container Lifecycle](#container-lifecycle)
- [Container Management](#container-management)
- [Image Management](#image-management)
- [Registry & Authentication](#registry--authentication)
- [Network Management](#network-management)
- [Volume Management](#volume-management)
- [System](#system)
- [Compose](#compose)
- [Other](#other)

---

## Container Lifecycle

### `mocker run`

Create and run a new container.

```
mocker run [OPTIONS] IMAGE [COMMAND...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--name` | | Assign a name to the container |
| `--detach` | `-d` | Run container in background |
| `--interactive` | `-i` | Keep STDIN open even if not attached |
| `--tty` | `-t` | Allocate a pseudo-TTY |
| `--env` | `-e` | Set environment variables (KEY=VALUE) |
| `--env-file` | | Read in a file of environment variables |
| `--publish` | `-p` | Publish container port (hostPort:containerPort) |
| `--volume` | `-v` | Bind mount a volume (source:destination[:ro]) |
| `--network` | | Connect to a network |
| `--label` | `-l` | Set metadata labels (key=value) |
| `--workdir` | `-w` | Working directory inside the container |
| `--hostname` | `-h` | Container hostname |
| `--restart` | | Restart policy (no, always, on-failure, unless-stopped) |
| `--user` | `-u` | Username or UID (format: name\|uid[:group\|gid]) |
| `--entrypoint` | | Overwrite the default ENTRYPOINT of the image |
| `--platform` | | Set platform (e.g. linux/amd64, linux/arm64) |
| `--pull` | | Pull image before running (always\|missing\|never) |
| `--init` | | Run an init inside the container |
| `--dns` | | Set custom DNS servers |
| `--add-host` | | Add a custom host-to-IP mapping (host:ip) |
| `--mount` | | Attach a filesystem mount to the container |
| `--read-only` | | Mount the container's root filesystem as read only |
| `--tmpfs` | | Mount a tmpfs directory |
| `--shm-size` | | Size of /dev/shm |
| `--privileged` | | Give extended privileges to this container |
| `--cap-add` | | Add Linux capabilities |
| `--cap-drop` | | Drop Linux capabilities |
| `--stop-signal` | | Signal to stop the container (default: SIGTERM) |
| `--stop-timeout` | | Timeout (in seconds) to stop a container |
| `--memory` | `-m` | Memory limit (e.g. 512m, 1g) |
| `--cpus` | | Number of CPUs |
| `--rm` | | Automatically remove the container when it exits |
| `--annotation` | | Add an annotation to the container |
| `--attach` | `-a` | Attach to STDIN, STDOUT or STDERR |
| `--blkio-weight` | | Block IO (relative weight), 10-1000 or 0 to disable |
| `--blkio-weight-device` | | Block IO weight (relative device weight) |
| `--cgroup-parent` | | Optional parent cgroup for the container |
| `--cgroupns` | | Cgroup namespace to use (host\|private) |
| `--cidfile` | | Write the container ID to the file |
| `--cpu-shares` | `-c` | CPU shares (relative weight) |
| `--cpu-period` | | Limit CPU CFS period |
| `--cpu-quota` | | Limit CPU CFS quota |
| `--cpu-rt-period` | | Limit CPU real-time period in microseconds |
| `--cpu-rt-runtime` | | Limit CPU real-time runtime in microseconds |
| `--cpuset-cpus` | | CPUs in which to allow execution (0-3, 0,1) |
| `--cpuset-mems` | | MEMs in which to allow execution (0-3, 0,1) |
| `--detach-keys` | | Override the key sequence for detaching a container |
| `--device` | | Add a host device to the container |
| `--device-cgroup-rule` | | Add a rule to the cgroup allowed devices list |
| `--device-read-bps` | | Limit read rate (bytes/sec) from a device |
| `--device-read-iops` | | Limit read rate (IO/sec) from a device |
| `--device-write-bps` | | Limit write rate (bytes/sec) to a device |
| `--device-write-iops` | | Limit write rate (IO/sec) to a device |
| `--dns-option` | | Set DNS options |
| `--dns-search` | | Set custom DNS search domains |
| `--domainname` | | Container NIS domain name |
| `--expose` | | Expose a port or a range of ports |
| `--gpus` | | GPU devices to add to the container |
| `--group-add` | | Add additional groups to join |
| `--health-cmd` | | Command to run to check health |
| `--health-interval` | | Time between running the check |
| `--health-retries` | | Consecutive failures needed to report unhealthy |
| `--health-start-interval` | | Time between running check during start period |
| `--health-start-period` | | Start period for health-retries countdown |
| `--health-timeout` | | Maximum time to allow one check to run |
| `--ip` | | IPv4 address (e.g., 172.30.100.104) |
| `--ip6` | | IPv6 address (e.g., 2001:db8::33) |
| `--ipc` | | IPC mode to use |
| `--isolation` | | Container isolation technology |
| `--label-file` | | Read in a line delimited file of labels |
| `--link` | | Add link to another container |
| `--link-local-ip` | | Container IPv4/IPv6 link-local addresses |
| `--log-driver` | | Logging driver for the container |
| `--log-opt` | | Log driver options |
| `--mac-address` | | Container MAC address |
| `--memory-reservation` | | Memory soft limit |
| `--memory-swap` | | Swap limit equal to memory plus swap |
| `--memory-swappiness` | | Tune container memory swappiness (0 to 100) |
| `--network-alias` | | Add network-scoped alias for the container |
| `--no-healthcheck` | | Disable any container-specified HEALTHCHECK |
| `--oom-kill-disable` | | Disable OOM Killer |
| `--oom-score-adj` | | Tune host's OOM preferences (-1000 to 1000) |
| `--pid` | | PID namespace to use |
| `--pids-limit` | | Tune container pids limit (-1 for unlimited) |
| `--publish-all` | `-P` | Publish all exposed ports to random ports |
| `--quiet` | `-q` | Suppress the pull output |
| `--runtime` | | Runtime to use for this container |
| `--security-opt` | | Security Options |
| `--sig-proxy` | | Proxy received signals to the process (default: true) |
| `--storage-opt` | | Storage driver options for the container |
| `--sysctl` | | Sysctl options |
| `--ulimit` | | Ulimit options |
| `--use-api-socket` | | Bind mount Docker API socket and set DOCKER_HOST |
| `--userns` | | User namespace to use |
| `--uts` | | UTS namespace to use |
| `--volume-driver` | | Optional volume driver for the container |
| `--volumes-from` | | Mount volumes from the specified container(s) |

### `mocker create`

Create a new container (without starting it). Same flags as `run` except no `--detach-keys` or `--sig-proxy`.

```
mocker create [OPTIONS] IMAGE [COMMAND...]
```

### `mocker start`

Start one or more stopped containers.

```
mocker start [OPTIONS] CONTAINER [CONTAINER...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--attach` | `-a` | Attach STDOUT/STDERR and forward signals |
| `--interactive` | `-i` | Attach container's STDIN |
| `--detach-keys` | | Override the key sequence for detaching |

### `mocker stop`

Stop one or more running containers.

```
mocker stop [OPTIONS] CONTAINER [CONTAINER...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--timeout` | `-t` | Seconds to wait before killing (default: 10) |
| `--signal` | `-s` | Signal to send to the container |

### `mocker restart`

Restart one or more containers.

```
mocker restart [OPTIONS] CONTAINER [CONTAINER...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--timeout` | `-t` | Seconds to wait before killing (default: 10) |
| `--signal` | `-s` | Signal to send to the container |

### `mocker kill`

Kill one or more running containers.

```
mocker kill [OPTIONS] CONTAINER [CONTAINER...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--signal` | `-s` | Signal to send (default: KILL) |

### `mocker wait`

Block until one or more containers stop, then print their exit codes.

```
mocker wait CONTAINER [CONTAINER...]
```

### `mocker rm`

Remove one or more containers.

```
mocker rm [OPTIONS] CONTAINER [CONTAINER...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Force remove running containers |
| `--link` | `-l` | Remove the specified link |
| `--volumes` | `-v` | Remove anonymous volumes associated with the container |

### `mocker pause`

Pause all processes within one or more containers.

```
mocker pause CONTAINER [CONTAINER...]
```

### `mocker unpause`

Unpause all processes within one or more containers.

```
mocker unpause CONTAINER [CONTAINER...]
```

### `mocker update`

Update configuration of one or more containers.

```
mocker update [OPTIONS] CONTAINER [CONTAINER...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--memory` | `-m` | Memory limit (e.g. 512m, 1g) |
| `--cpus` | | Number of CPUs |
| `--cpu-shares` | `-c` | CPU shares (relative weight) |
| `--restart` | | Restart policy to apply |
| `--pids-limit` | | Tune container pids limit (-1 for unlimited) |
| `--blkio-weight` | | Block IO (relative weight), 10-1000 |
| `--cpu-period` | | Limit CPU CFS period |
| `--cpu-quota` | | Limit CPU CFS quota |
| `--cpu-rt-period` | | Limit CPU real-time period in microseconds |
| `--cpu-rt-runtime` | | Limit CPU real-time runtime in microseconds |
| `--cpuset-cpus` | | CPUs in which to allow execution |
| `--cpuset-mems` | | MEMs in which to allow execution |
| `--memory-reservation` | | Memory soft limit |
| `--memory-swap` | | Swap limit equal to memory plus swap |

---

## Container Management

### `mocker ps`

List containers.

```
mocker ps [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all containers (default shows just running) |
| `--quiet` | `-q` | Only display container IDs |
| `--filter` | `-f` | Filter output based on conditions provided |
| `--format` | | Format output using a custom template |
| `--no-trunc` | | Don't truncate output |
| `--last` | `-n` | Show n last created containers |
| `--latest` | `-l` | Show the latest created container |
| `--size` | `-s` | Display total file sizes |

### `mocker exec`

Execute a command in a running container.

```
mocker exec [OPTIONS] CONTAINER COMMAND [ARG...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--interactive` | `-i` | Keep STDIN open even if not attached |
| `--tty` | `-t` | Allocate a pseudo-TTY |
| `--env` | `-e` | Set environment variables |
| `--workdir` | `-w` | Working directory inside the container |
| `--detach` | `-d` | Detached mode: run command in the background |
| `--detach-keys` | | Override the key sequence for detaching |
| `--user` | `-u` | Username or UID |
| `--env-file` | | Read in a file of environment variables |
| `--privileged` | | Give extended privileges to the command |

### `mocker logs`

Fetch the logs of a container.

```
mocker logs [OPTIONS] CONTAINER
```

| Flag | Short | Description |
|------|-------|-------------|
| `--follow` | `-f` | Follow log output |
| `--tail` | `-n` | Number of lines to show from the end |
| `--since` | | Show logs since timestamp |
| `--until` | | Show logs before a timestamp |
| `--timestamps` | `-t` | Show timestamps |
| `--details` | | Show extra details provided to logs |

### `mocker inspect`

Return low-level information on container or image.

```
mocker inspect [OPTIONS] NAME|ID [NAME|ID...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output using a custom template |
| `--type` | | Only inspect objects of the given type |
| `--size` | `-s` | Display total file sizes if type is container |

### `mocker stats`

Display a live stream of container resource usage statistics.

```
mocker stats [OPTIONS] [CONTAINER...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--no-stream` | | Disable streaming stats and only pull the first result |
| `--all` | `-a` | Show all containers (default shows just running) |
| `--format` | | Format output using a custom template |
| `--no-trunc` | | Do not truncate output |

### `mocker attach`

Attach local standard input, output, and error streams to a running container.

```
mocker attach [OPTIONS] CONTAINER
```

| Flag | Short | Description |
|------|-------|-------------|
| `--detach-keys` | | Override the key sequence for detaching |
| `--no-stdin` | | Do not attach STDIN |
| `--sig-proxy` | | Proxy all received signals to the process (default: true) |

### `mocker rename`

Rename a container.

```
mocker rename CONTAINER NEW_NAME
```

### `mocker port`

List port mappings or a specific mapping for the container.

```
mocker port CONTAINER [PRIVATE_PORT]
```

### `mocker top`

Display the running processes of a container.

```
mocker top CONTAINER [PS_OPTIONS...]
```

### `mocker diff`

Inspect changes to files or directories on a container's filesystem.

```
mocker diff CONTAINER
```

### `mocker cp`

Copy files/folders between a container and the local filesystem.

```
mocker cp [OPTIONS] SOURCE DESTINATION
```

| Flag | Short | Description |
|------|-------|-------------|
| `--archive` | `-a` | Archive mode (copy all uid/gid information) |
| `--follow-link` | `-L` | Always follow symbol link in SRC_PATH |
| `--quiet` | `-q` | Suppress progress output during copy |

### `mocker commit`

Create a new image from a container's changes.

```
mocker commit [OPTIONS] CONTAINER [REPOSITORY[:TAG]]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--author` | `-a` | Author |
| `--change` | `-c` | Apply Dockerfile instruction to the created image |
| `--message` | `-m` | Commit message |
| `--no-pause` | | Disable pausing container during commit |

### `mocker export`

Export a container's filesystem as a tar archive.

```
mocker export [OPTIONS] CONTAINER
```

| Flag | Short | Description |
|------|-------|-------------|
| `--output` | `-o` | Write to a file, instead of STDOUT |

---

## Image Management

### `mocker build`

Build an image from a Dockerfile.

```
mocker build [OPTIONS] PATH
```

| Flag | Short | Description |
|------|-------|-------------|
| `--tag` | `-t` | Name and optionally a tag (name:tag) |
| `--file` | `-f` | Name of the Dockerfile (default: Dockerfile) |
| `--no-cache` | | Do not use cache when building |
| `--build-arg` | | Set build-time variables |
| `--platform` | | Set target platform for build |
| `--target` | | Set the target build stage to build |
| `--label` | `-l` | Set metadata for an image |
| `--pull` | | Always attempt to pull a newer version of the image |
| `--quiet` | `-q` | Suppress the build output |
| `--network` | | Set the networking mode for RUN instructions |
| `--add-host` | | Add a custom host-to-IP mapping (host:ip) |
| `--allow` | | Allow extra privileged entitlement |
| `--annotation` | | Add an annotation to the image |
| `--attest` | | Attestation parameters (type=sbom\|provenance) |
| `--build-context` | | Additional build contexts (e.g., name=path) |
| `--builder` | | Override the configured builder instance |
| `--cache-from` | | External cache sources |
| `--cache-to` | | Cache export destinations |
| `--call` | | Set method for evaluating build |
| `--cgroup-parent` | | Set the parent cgroup for RUN instructions |
| `--check` | | Shorthand for --call=check |
| `--debug` | `-D` | Enable debug logging |
| `--iidfile` | | Write the image ID to the file |
| `--load` | | Shorthand for --output=type=docker |
| `--metadata-file` | | Write build result metadata to the file |
| `--no-cache-filter` | | Do not cache specified stages |
| `--output` | `-o` | Output destination (format: type=local,dest=path) |
| `--policy` | | Set policy for build |
| `--progress` | | Set type of progress output (auto, plain, tty, rawjson) |
| `--provenance` | | Shorthand for --attest=type=provenance |
| `--push` | | Shorthand for --output=type=registry |
| `--sbom` | | Shorthand for --attest=type=sbom |
| `--secret` | | Secret to expose to the build |
| `--shm-size` | | Size of /dev/shm |
| `--ssh` | | SSH agent socket or keys to expose to the build |
| `--ulimit` | | Ulimit options |

### `mocker images`

List images.

```
mocker images [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--quiet` | `-q` | Only show image IDs |
| `--all` | `-a` | Show all images (default hides intermediate) |
| `--filter` | `-f` | Filter output based on conditions provided |
| `--format` | | Format output using a custom template |
| `--digests` | | Show digests |
| `--no-trunc` | | Don't truncate output |
| `--tree` | | List images in tree format (experimental) |

### `mocker pull`

Download an image from a registry.

```
mocker pull [OPTIONS] IMAGE
```

| Flag | Short | Description |
|------|-------|-------------|
| `--all-tags` | `-a` | Download all tagged images in the repository |
| `--platform` | | Set platform if server is multi-platform capable |
| `--quiet` | `-q` | Suppress verbose output |

### `mocker push`

Upload an image to a registry.

```
mocker push [OPTIONS] IMAGE
```

| Flag | Short | Description |
|------|-------|-------------|
| `--all-tags` | `-a` | Push all tags of an image to the repository |
| `--platform` | | Push a platform-specific manifest |
| `--quiet` | `-q` | Suppress verbose output |

### `mocker tag`

Create a tag that refers to a source image.

```
mocker tag SOURCE TARGET
```

### `mocker rmi`

Remove one or more images.

```
mocker rmi [OPTIONS] IMAGE [IMAGE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Force removal of the image |
| `--no-prune` | | Do not delete untagged parents |
| `--platform` | | Remove only the given platform variant |

### `mocker history`

Show the history of an image.

```
mocker history [OPTIONS] IMAGE
```

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | | Format output using a custom template |
| `--human` | `-H` | Print sizes and dates in human readable format (default: true) |
| `--no-trunc` | | Don't truncate output |
| `--quiet` | `-q` | Only show image IDs |
| `--platform` | | Set platform to show history for |

### `mocker save`

Save one or more images to a tar archive.

```
mocker save [OPTIONS] IMAGE [IMAGE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--output` | `-o` | Write to a file, instead of STDOUT |
| `--platform` | | Set platform to save for |

### `mocker load`

Load an image from a tar archive or STDIN.

```
mocker load [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--input` | `-i` | Read from tar archive file, instead of STDIN |
| `--quiet` | `-q` | Suppress the load output |
| `--platform` | | Set platform to load for |

### `mocker import`

Import the contents from a tarball to create a filesystem image.

```
mocker import [OPTIONS] SOURCE [REPOSITORY[:TAG]]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--change` | `-c` | Apply Dockerfile instruction to the created image |
| `--message` | `-m` | Set commit message for imported image |
| `--platform` | | Set platform for imported image |

### `mocker search`

Search Docker Hub for images.

```
mocker search [OPTIONS] TERM
```

| Flag | Short | Description |
|------|-------|-------------|
| `--filter` | `-f` | Filter output based on conditions provided |
| `--format` | | Format output using a custom template |
| `--limit` | | Max number of search results (default: 25) |
| `--no-trunc` | | Don't truncate output |

---

## Registry & Authentication

### `mocker login`

Authenticate to a registry.

```
mocker login [OPTIONS] [SERVER]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--username` | `-u` | Username |
| `--password` | `-p` | Password or Personal Access Token |
| `--password-stdin` | | Take the password from stdin |

### `mocker logout`

Log out from a registry.

```
mocker logout [SERVER]
```

### `mocker version`

Show the Mocker version information.

```
mocker version [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output using a custom template |

---

## Network Management

### `mocker network create`

```
mocker network create [OPTIONS] NAME
```

| Flag | Short | Description |
|------|-------|-------------|
| `--driver` | `-d` | Driver to manage the network (default: bridge) |
| `--subnet` | | Subnet in CIDR format |
| `--gateway` | | Gateway for the subnet |
| `--attachable` | | Enable manual container attachment |
| `--aux-address` | | Auxiliary IPv4 or IPv6 addresses |
| `--config-from` | | The network from which to copy the configuration |
| `--config-only` | | Create a configuration only network |
| `--ingress` | | Create swarm routing-mesh network |
| `--internal` | | Restrict external access to the network |
| `--ip-range` | | Allocate container ip from a sub-range |
| `--ipam-driver` | | IP Address Management Driver |
| `--ipam-opt` | | Set IPAM driver specific options |
| `--ipv4` | | Enable or disable IPv4 |
| `--ipv6` | | Enable or disable IPv6 |
| `--label` | | Set metadata on a network |
| `--opt` | `-o` | Set driver specific options |
| `--scope` | | Control the network's scope |

### `mocker network ls`

```
mocker network ls [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--filter` | `-f` | Filter output based on conditions provided |
| `--format` | | Format output using a custom template |
| `--quiet` | `-q` | Only display network IDs |
| `--no-trunc` | | Don't truncate output |

### `mocker network rm`

```
mocker network rm [OPTIONS] NETWORK [NETWORK...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Do not error if the network does not exist |

### `mocker network inspect`

```
mocker network inspect [OPTIONS] NAME
```

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output using the given Go template |
| `--verbose` | `-v` | Verbose output for diagnostics |

### `mocker network connect`

```
mocker network connect [OPTIONS] NETWORK CONTAINER
```

| Flag | Short | Description |
|------|-------|-------------|
| `--alias` | | Add network-scoped alias for the container |
| `--driver-opt` | | Driver options for the network |
| `--gw-priority` | | Gateway priority for the container |
| `--ip` | | IPv4 address |
| `--ip6` | | IPv6 address |
| `--link` | | Add link to another container |
| `--link-local-ip` | | Add a link-local address for the container |

### `mocker network disconnect`

```
mocker network disconnect [OPTIONS] NETWORK CONTAINER
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Force the container to disconnect |

### `mocker network prune`

```
mocker network prune [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Do not prompt for confirmation |
| `--filter` | | Provide filter values |

---

## Volume Management

### `mocker volume create`

```
mocker volume create [OPTIONS] NAME
```

| Flag | Short | Description |
|------|-------|-------------|
| `--driver` | `-d` | Volume driver (default: local) |
| `--label` | | Set metadata for a volume |
| `--opt` | `-o` | Set driver specific options |

### `mocker volume ls`

```
mocker volume ls [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--filter` | `-f` | Filter output based on conditions provided |
| `--format` | | Format output using a custom template |
| `--quiet` | `-q` | Only display volume names |

### `mocker volume rm`

```
mocker volume rm [OPTIONS] VOLUME [VOLUME...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Force the removal of one or more volumes |

### `mocker volume inspect`

```
mocker volume inspect [OPTIONS] NAME
```

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output using a custom template |

### `mocker volume prune`

```
mocker volume prune [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Do not prompt for confirmation |
| `--all` | `-a` | Prune all unused volumes, not just anonymous ones |
| `--filter` | | Provide filter values |

---

## System

### `mocker system info`

Display system-wide information.

```
mocker system info [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output using a custom template |

### `mocker system df`

Show disk usage.

```
mocker system df [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--verbose` | `-v` | Show detailed information on space usage |
| `--format` | | Format output using a custom template |

### `mocker system events`

Get real time events from the server.

```
mocker system events [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--filter` | `-f` | Filter output based on conditions provided |
| `--format` | | Format output using a custom template |
| `--since` | | Show all events created since timestamp |
| `--until` | | Stream events until this timestamp |

### `mocker system prune`

Remove unused data.

```
mocker system prune [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Remove all unused images, not just dangling ones |
| `--volumes` | | Also prune volumes |
| `--force` | `-f` | Do not prompt for confirmation |
| `--filter` | | Provide filter values |

---

## Compose

All compose subcommands support these shared flags:

| Flag | Short | Description |
|------|-------|-------------|
| `--file` | `-f` | Compose file path |
| `--project-name` | `-p` | Project name |

### `mocker compose up`

Create and start containers.

```
mocker compose up [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--detach` | `-d` | Run containers in the background |
| `--abort-on-container-exit` | | Stops all containers if any container was stopped |
| `--abort-on-container-failure` | | Stops all containers if any container exited with failure |
| `--always-recreate-deps` | | Recreate dependent containers |
| `--attach` | | Restrict attaching to the specified services |
| `--attach-dependencies` | | Automatically attach to log output of dependent services |
| `--build` | | Build images before starting containers |
| `--dry-run` | | Execute command in dry run mode |
| `--exit-code-from` | | Return the exit code of the selected service container |
| `--force-recreate` | | Recreate containers even if configuration hasn't changed |
| `--menu` | | Enable interactive shortcuts |
| `--no-attach` | | Do not attach to the specified services |
| `--no-build` | | Don't build an image, even if it's policy |
| `--no-color` | | Produce monochrome output |
| `--no-deps` | | Don't start linked services |
| `--no-log-prefix` | | Don't print prefix in logs |
| `--no-recreate` | | If containers already exist, don't recreate them |
| `--no-start` | | Don't start the services after creating them |
| `--pull` | | Pull image before running (always\|missing\|never) |
| `--quiet-build` | | Suppress build output |
| `--quiet-pull` | | Pull without printing progress information |
| `--remove-orphans` | | Remove containers for services not in Compose file |
| `--renew-anon-volumes` | `-V` | Recreate anonymous volumes |
| `--scale` | | Scale SERVICE to NUM instances |
| `--timeout` | `-t` | Use this timeout in seconds for container shutdown |
| `--timestamps` | | Add timestamps to log output |
| `--wait` | `-w` | Wait for services to be running\|healthy |
| `--wait-timeout` | | Maximum duration to wait |
| `--watch` | | Watch source code and rebuild/refresh containers |
| `--yes` | `-y` | Assume yes to all prompts |

### `mocker compose down`

Stop and remove containers, networks.

```
mocker compose down [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--remove-orphans` | | Remove containers for services not in Compose file |
| `--volumes` | `-v` | Remove named volumes |
| `--timeout` | `-t` | Timeout in seconds for stopping containers (default: 10) |
| `--dry-run` | | Execute command in dry run mode |
| `--rmi` | | Remove images used by services (all\|local) |

### `mocker compose ps`

List containers for a compose project.

```
mocker compose ps [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all stopped containers |
| `--dry-run` | | Execute command in dry run mode |
| `--filter` | | Filter services by a property |
| `--format` | | Format output using a custom template |
| `--no-trunc` | | Don't truncate output |
| `--orphans` | | Include orphaned containers |
| `--quiet` | `-q` | Only display IDs |
| `--services` | | Display the services |
| `--status` | | Filter services by status |

### `mocker compose logs`

View output from containers.

```
mocker compose logs [OPTIONS] [SERVICE]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--follow` | | Follow log output |
| `--dry-run` | | Execute command in dry run mode |
| `--index` | | Show logs for a specific container index |
| `--no-color` | | Produce monochrome output |
| `--no-log-prefix` | | Don't print prefix in logs |
| `--since` | | Show logs since timestamp |
| `--tail` | `-n` | Number of lines to show from the end |
| `--timestamps` | `-t` | Show timestamps |
| `--until` | | Show logs before a timestamp |

### `mocker compose build`

Build or rebuild services.

```
mocker compose build [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--no-cache` | | Do not use cache when building |
| `--pull` | | Always attempt to pull a newer version |
| `--build-arg` | | Set build-time variables |
| `--quiet` | `-q` | Suppress the build output |
| `--builder` | | Set builder to use |
| `--check` | | Check build configuration and exit |
| `--dry-run` | | Execute command in dry run mode |
| `--memory` | `-m` | Set memory limit for the build container |
| `--print` | | Print equivalent bake file |
| `--provenance` | | Set type of provenance attestation |
| `--push` | | Push service images after build |
| `--sbom` | | Set type of SBOM attestation |
| `--ssh` | | Set SSH authentications used during build |
| `--with-dependencies` | | Also build dependencies |

### `mocker compose pull`

Pull service images.

```
mocker compose pull [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--quiet` | `-q` | Suppress pull output |
| `--ignore-pull-failures` | | Pull what it can and ignore failures |
| `--dry-run` | | Execute command in dry run mode |
| `--ignore-buildable` | | Ignore images that can be built |
| `--include-deps` | | Also pull services declared as dependencies |
| `--policy` | | Apply pull policy (missing\|always) |

### `mocker compose push`

Push service images.

```
mocker compose push [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--ignore-push-failures` | | Push what it can and ignore failures |
| `--dry-run` | | Execute command in dry run mode |
| `--include-deps` | | Also push images of services declared as dependencies |
| `--quiet` | `-q` | Push without printing progress information |

### `mocker compose exec`

Execute a command in a running service container.

```
mocker compose exec [OPTIONS] SERVICE COMMAND [ARG...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--detach` | `-d` | Detached mode |
| `-i` | | Keep STDIN open |
| `-t` | | Allocate a pseudo-TTY |
| `--env` | `-e` | Set environment variables |
| `--user` | `-u` | Username or UID |
| `--workdir` | `-w` | Working directory inside the container |
| `--index` | | Index of the container if service is scaled |
| `--dry-run` | | Execute command in dry run mode |
| `--no-tty` | `-T` | Disable pseudo-TTY allocation |
| `--privileged` | | Give extended privileges to the process |

### `mocker compose run`

Run a one-off command on a service.

```
mocker compose run [OPTIONS] SERVICE [COMMAND...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--detach` | `-d` | Run container in background |
| `--rm` | | Remove container after run |
| `--env` | `-e` | Set environment variables |
| `--user` | `-u` | Username or UID |
| `--volume` | `-v` | Bind mount a volume |
| `--publish` | | Publish a container's port |
| `--workdir` | `-w` | Working directory inside the container |
| `--entrypoint` | | Override the entrypoint |
| `--no-deps` | | Don't start linked services |
| `--build` | | Build images before starting containers |
| `--cap-add` | | Add Linux capabilities |
| `--cap-drop` | | Drop Linux capabilities |
| `--dry-run` | | Execute command in dry run mode |
| `--env-from-file` | | Set environment variables from file |
| `--interactive` | `-i` | Keep STDIN open even if not attached |
| `--label` | `-l` | Add or override a label |
| `--name` | | Assign a name to the container |
| `--no-tty` | `-T` | Disable pseudo-TTY allocation |
| `--pull` | | Pull image before running (always\|missing\|never) |
| `--quiet` | `-q` | Suppress run output |
| `--quiet-build` | | Suppress build output |
| `--quiet-pull` | | Pull without printing progress information |
| `--remove-orphans` | | Remove containers for services not in Compose file |
| `--service-ports` | | Run command with all service's ports enabled |
| `--tty` | `-t` | Allocate a pseudo-TTY |
| `--use-aliases` | | Use the service's network aliases |
| `--publish-all` | `-P` | Publish all exposed ports to random host ports |

### `mocker compose stop`

```
mocker compose stop [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--timeout` | `-t` | Specify a shutdown timeout in seconds (default: 10) |
| `--dry-run` | | Execute command in dry run mode |

### `mocker compose start`

```
mocker compose start [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--dry-run` | | Execute command in dry run mode |
| `--wait` | | Wait for services to be running\|healthy |
| `--wait-timeout` | | Maximum duration to wait |

### `mocker compose restart`

```
mocker compose restart [OPTIONS] [SERVICE]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--dry-run` | | Execute command in dry run mode |
| `--no-deps` | | Don't restart dependent services |
| `--timeout` | `-t` | Specify a shutdown timeout in seconds |

### `mocker compose rm`

Remove stopped service containers.

```
mocker compose rm [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | | Don't ask to confirm removal |
| `--stop` | `-s` | Stop the containers, if required, before removing |
| `--volumes` | `-v` | Remove any anonymous volumes attached to containers |
| `--dry-run` | | Execute command in dry run mode |

### `mocker compose kill`

```
mocker compose kill [OPTIONS] [SERVICE]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--dry-run` | | Execute command in dry run mode |
| `--remove-orphans` | | Remove containers for services not in Compose file |
| `--signal` | `-s` | SIGNAL to send to the container |

### `mocker compose config`

Validate and view the Compose file.

```
mocker compose config [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--services` | | Print the service names, one per line |
| `--volumes` | | Print the volume names, one per line |
| `--quiet` | `-q` | Only validate the configuration |
| `--dry-run` | | Execute command in dry run mode |
| `--environment` | | Print the environment variables |
| `--format` | | Format the output (yaml\|json) |
| `--hash` | | Print the service config hash |
| `--images` | | Print the image names, one per line |
| `--lock-image-digests` | | Pin image tags to digests |
| `--models` | | Print the model names, one per line |
| `--networks` | | Print the network names, one per line |
| `--no-consistency` | | Don't check model consistency |
| `--no-env-resolution` | | Don't resolve environment variables |
| `--no-interpolate` | | Don't interpolate environment variables |
| `--no-normalize` | | Don't normalize compose model |
| `--no-path-resolution` | | Don't resolve file paths |
| `--output` | `-o` | Save to file |
| `--profiles` | | Print the profile names, one per line |
| `--resolve-image-digests` | | Pin image tags to digests |
| `--variables` | | Print the variable names, one per line |

### `mocker compose create`

Create containers for a service.

```
mocker compose create [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--build` | | Build images before starting containers |
| `--dry-run` | | Execute command in dry run mode |
| `--force-recreate` | | Recreate containers even if configuration hasn't changed |
| `--no-build` | | Don't build an image |
| `--no-recreate` | | If containers already exist, don't recreate them |
| `--pull` | | Pull image before running (always\|missing\|never) |
| `--quiet-pull` | | Pull without printing progress information |
| `--remove-orphans` | | Remove containers for services not in Compose file |
| `--scale` | | Scale SERVICE to NUM instances |
| `--yes` | `-y` | Assume yes to all prompts |

### `mocker compose images`

```
mocker compose images [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--dry-run` | | Execute command in dry run mode |
| `--format` | | Format the output (table\|json) |
| `--quiet` | `-q` | Only display IDs |

### `mocker compose top`

```
mocker compose top [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--dry-run` | | Execute command in dry run mode |

### `mocker compose port`

```
mocker compose port [OPTIONS] SERVICE PRIVATE_PORT
```

| Flag | Short | Description |
|------|-------|-------------|
| `--protocol` | | Protocol (tcp or udp) |
| `--index` | | Index of the container if service is scaled |
| `--dry-run` | | Execute command in dry run mode |

### `mocker compose pause`

```
mocker compose pause [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--dry-run` | | Execute command in dry run mode |

### `mocker compose unpause`

```
mocker compose unpause [OPTIONS] [SERVICE...]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--dry-run` | | Execute command in dry run mode |

### `mocker compose ls`

List running compose projects.

```
mocker compose ls [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all stopped compose projects |
| `--format` | | Format output using a custom template |
| `--quiet` | `-q` | Only display project names |
| `--dry-run` | | Execute command in dry run mode |
| `--filter` | | Filter output based on conditions provided |

### `mocker compose cp`

Copy files/folders between a service container and the local filesystem.

```
mocker compose cp [OPTIONS] SOURCE DESTINATION
```

| Flag | Short | Description |
|------|-------|-------------|
| `--index` | | Index of the container if service is scaled (default: 1) |
| `--all` | `-a` | Copy to all containers of the service |
| `--archive` | | Archive mode (copy all uid/gid information) |
| `--dry-run` | | Execute command in dry run mode |
| `--follow-link` | `-L` | Always follow symbol link in source path |

---

## Other

### `mocker container`

Management command grouping all container operations. Subcommands: `attach`, `commit`, `cp`, `create`, `diff`, `exec`, `export`, `inspect`, `kill`, `logs`, `ls` (default), `pause`, `port`, `prune`, `rename`, `restart`, `rm`, `run`, `start`, `stats`, `stop`, `top`, `unpause`, `update`, `wait`.

### `mocker image`

Management command grouping all image operations. Subcommands: `build`, `history`, `import`, `inspect`, `ls` (default), `prune`, `pull`, `push`, `rm`, `rmi`, `save`, `tag`.

### `mocker container prune`

Remove all stopped containers.

| Flag | Short | Description |
|------|-------|-------------|
| `--filter` | | Provide filter values (e.g. "until=<timestamp>") |
| `--force` | `-f` | Do not prompt for confirmation |

### `mocker image inspect`

Display detailed information on one or more images.

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output using a custom template |
| `--platform` | | Inspect a specific platform of the multi-platform image |

### `mocker image prune`

Remove unused images.

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Remove all unused images, not just dangling ones |
| `--filter` | | Provide filter values |
| `--force` | `-f` | Do not prompt for confirmation |

### `mocker proxy`

Internal proxy command for container networking.
