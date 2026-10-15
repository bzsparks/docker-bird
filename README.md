# docker-bird

Small, unprivileged container images for [BIRD](https://bird.nic.cz), the
Internet Routing Daemon.

The image is only BIRD 3, built from upstream source: no wrapper scripts, no
generated config, no opinions about your topology. Mount a `bird.conf`, grant
four network capabilities, and it runs whatever BIRD can run: BGP to an
upstream or a ToR, a route server or reflector, OSPF or Babel inside a fabric,
RPKI-validated filtering, or announcing a service address from beside the
service.

## What's in the image

- **BIRD 3 from source.** The upstream tarball is checked against a pinned
  SHA256 at build time. Upstream publishes no signatures, so that pin is the
  supply-chain control. The base images are pinned by digest as well, so a
  rebuild produces the same image.
- **One local patch**, for an upstream bug (see [Patches](#patches)).
- **`bird`, `birdc` and `birdcl`**, stripped and copied out of a multi-stage
  build, so no compiler or headers end up in the runtime image.
- **libssh**, for RPKI-to-Router over SSH. RTR over plain TCP works without it.
- **An unprivileged daemon.** BIRD starts as root only long enough to drop to
  `bird:bird` (UID/GID 179), keeping just the capabilities listed below.
- **Troubleshooting tools:** `ip`, `ping` and `ps`, so `docker exec` is useful
  without a debug container.

## Tags

| Tag | Base | Notes |
|-----|------|-------|
| `latest`, `3.3.3` | `debian:trixie-20261005-slim` | Default. glibc, built-in health check |
| `3.3.3-alpine` | `alpine:3.24.2` | musl, about 16 MB versus 94 MB for Debian, no health check |

Version tags match the upstream BIRD release. Pin a version in production,
because `latest` moves.

## Quick start

A minimal config that originates one prefix to one eBGP peer and imports
nothing. It uses documentation addresses and ASNs; substitute your own.

```text
# bird.conf
log stderr all;              # so `docker logs` shows it
router id 192.0.2.10;

protocol device {}

protocol static announce {
  ipv4;
  route 203.0.113.0/24 blackhole;
}

protocol bgp upstream {
  local as 64500;
  neighbor 192.0.2.1 as 64501;
  ipv4 {
    import none;
    export where proto = "announce";
  };
}
```

```bash
docker run -d --name bird \
  --network host \
  --cap-add NET_ADMIN --cap-add NET_BIND_SERVICE \
  --cap-add NET_BROADCAST --cap-add NET_RAW \
  -v "$PWD/bird.conf:/etc/bird/bird.conf:ro" \
  --restart unless-stopped \
  bzsprks/bird:3.3.3
```

```bash
docker exec bird birdc show protocols
```

The same container in Compose:

```yaml
services:
  bird:
    image: bzsprks/bird:3.3.3
    network_mode: host
    restart: unless-stopped
    cap_add: [NET_ADMIN, NET_BIND_SERVICE, NET_BROADCAST, NET_RAW]
    volumes:
      - ./bird.conf:/etc/bird/bird.conf:ro
```

## Capabilities

The image works without `--privileged`, but it does need these four
capabilities, **all four, whatever protocols you run**. BIRD's privilege drop
asks the kernel to keep exactly this set. If any of them is missing from the
container, it stops at startup with `capset: Operation not permitted`.

| Capability | What BIRD uses it for |
|------------|-----------------------|
| `NET_ADMIN` | Writing the kernel routing table over netlink (the `kernel` protocol) and setting interface socket options |
| `NET_BIND_SERVICE` | Binding ports below 1024: BGP on 179, RIP on 520 |
| `NET_RAW` | Raw sockets for OSPF (IP protocol 89) and RAdv (ICMPv6), and binding sockets to an interface |
| `NET_BROADCAST` | Part of the set BIRD keeps. Current Linux kernels never check it, but the drop fails without it |

Docker's defaults already include `NET_BIND_SERVICE` and `NET_RAW`. Listing
them anyway keeps the command working on runtimes or policies with a smaller
default set.

Once it has started, the daemon holds only these four, whatever the container
grants. Removing everything else, as in the profile below, mostly narrows the
moment before the privilege drop and what `docker exec` sessions can do:

```yaml
services:
  bird:
    image: bzsprks/bird:3.3.3
    network_mode: host
    restart: unless-stopped
    cap_drop: [ALL]
    cap_add:
      - NET_ADMIN
      - NET_BIND_SERVICE
      - NET_BROADCAST
      - NET_RAW
      - SETUID          # privilege drop
      - SETGID          # privilege drop
      - CHOWN           # hand the control socket to bird
      - FOWNER          # set the control socket's mode
      - DAC_OVERRIDE    # lets root birdc and the health check reach the socket
    security_opt: [no-new-privileges:true]
    read_only: true
    tmpfs: [/run]       # the control socket lives here
    volumes:
      - ./bird:/etc/bird:ro
```

You can drop `DAC_OVERRIDE` if you always run `docker exec -u bird bird birdc ...`
and don't rely on the health check. Without it, root cannot open the control
socket.

## Networking

BIRD routes for whichever network namespace it runs in. Choose that namespace
deliberately:

| Mode | BIRD manages | Typical use |
|------|--------------|-------------|
| `--network host` | The host's routing table and interfaces | The host's routing daemon, such as an edge router, a hypervisor announcing workloads, or an OSPF or BGP fabric member |
| `--network container:<name>` (Compose: `network_mode: "service:<name>"`) | Another container's namespace | Announcing that service's address from inside its namespace, for example an anycast or VIP service |
| Bridge, with `-p 179:179` | Only the container's own namespace | Route servers, reflectors and collectors that never program a kernel table |

Running BIRD alongside another container:

```yaml
services:
  app:
    image: example/app      # owns the namespace and the address being announced

  bird:
    image: bzsprks/bird:3.3.3
    network_mode: "service:app"
    cap_add: [NET_ADMIN, NET_BIND_SERVICE, NET_BROADCAST, NET_RAW]
    volumes:
      - ./bird.conf:/etc/bird/bird.conf:ro
    depends_on:
      app:
        condition: service_healthy
```

Docker does not reattach a shared namespace when its owner restarts. BIRD
keeps running, but it is left with only `lo`, so restart it along with that
container. If either side needs to restart on
its own, have both join a dedicated pause container's namespace.

BIRD installs routes, but it does not turn on forwarding. If the host or
namespace needs to forward packets, set `net.ipv4.ip_forward` and
`net.ipv6.conf.all.forwarding` yourself, on the host or with Compose
`sysctls:`.

Open whatever ports your protocols use: TCP 179 for BGP, UDP 3784–3785 for
BFD, IP protocol 89 for OSPF, UDP 6696 for Babel. `EXPOSE 179/tcp` is only
metadata.

## Configuration

- **Path.** BIRD reads `/etc/bird/bird.conf`. The image contains only
  upstream's example file as a placeholder, so mount your own, read-only.
- **Permissions.** BIRD reads its config as UID/GID 179, after dropping root.
  The file, and anything it `include`s, must be readable by that UID or GID,
  or BIRD stops with `Permission denied`. Configs often hold BGP passwords, so
  prefer group access over world-readable:
  `sudo chgrp 179 bird.conf && chmod 640 bird.conf`.
- **Single file or directory.** A single-file bind mount points at an inode.
  Editors that save by writing a new file and renaming it, which includes vim
  and most IDEs, leave the container reading the old copy. If you edit and
  reload in place, or use `include`, mount the directory instead:
  `-v "$PWD/bird:/etc/bird:ro"`.
- **Validate before deploying.** This parses the config and exits non-zero on
  an error, which makes it usable in CI:

  ```bash
  docker run --rm -v "$PWD/bird.conf:/etc/bird/bird.conf:ro" \
    --entrypoint /usr/sbin/bird bzsprks/bird:3.3.3 -p -c /etc/bird/bird.conf
  ```

- **Logging.** Add `log stderr all;`, or a narrower class list. With no `log`
  statement BIRD logs to syslog, there is no syslog daemon in the container,
  and `docker logs` stays empty.

## Operating

`birdc` talks to the daemon over its control socket, `/run/bird.ctl`
(`bird:bird`, mode 0660):

```bash
docker exec bird birdc show protocols all upstream
docker exec bird birdc show route
docker exec bird birdc configure check   # validate the mounted config
docker exec bird birdc configure         # apply it with no restart
docker exec -it bird birdc               # interactive
```

## Health check (Debian only)

The Debian image includes a health check that runs `birdc show protocols` and
reports healthy while **at least one BGP session is Established**. It checks
every 30 s, after a 30 s start period. That suits BGP speakers. It reports an
OSPF-only router, or a route server waiting for its first peer, as unhealthy.

To check only that the daemon is up and answering, override it:

```bash
docker run ... --health-cmd 'birdc show status' bzsprks/bird:3.3.3
```

```yaml
    healthcheck:
      test: ["CMD", "birdc", "show", "status"]
```

To disable it, use `--no-healthcheck` or `healthcheck: { disable: true }`.

## Variants

| | Debian | Alpine |
|--|--------|--------|
| Base | `debian:trixie-20261005-slim` | `alpine:3.24.2` |
| libc | glibc | musl |
| Size | about 94 MB | about 16 MB |
| Health check | Yes | No |
| `ENTRYPOINT` | `bird -u bird -g bird` | `bird -f -u bird -g bird` |
| `CMD` | `-f -c /etc/bird/bird.conf` | none |

The two images treat extra arguments differently. On Debian, arguments
**replace** `CMD`, so keep `-f` yourself, for example
`... bzsprks/bird:3.3.3 -f -c /etc/bird/alt.conf`. Without `-f`, BIRD forks
into the background and the container exits straight away with code 0. On
Alpine, arguments are **appended** after `-f`, for example
`... bzsprks/bird:3.3.3-alpine -c /etc/bird/alt.conf`.

## Building

```bash
docker build -t bird:local Debian/
docker build -t bird:local-alpine Alpine/
docker run --rm --entrypoint /usr/sbin/bird bird:local --version
```

| Build arg | Default | Purpose |
|-----------|---------|---------|
| `BIRD_VERSION` | `3.3.3` | Upstream release to build |
| `BIRD_SHA256` | pinned | SHA256 of that release's tarball. Must change with `BIRD_VERSION`, or the build fails |
| `BASE_IMAGE` | pinned `tag@sha256:` | Base for both stages |
| `DATE_CREATED` | empty | Value for the `org.opencontainers.image.created` label |
| `UID` / `GID` | `179` | IDs of the `bird` user and group |

To bump the version, update `BIRD_VERSION` and `BIRD_SHA256` in both
Dockerfiles together, then rebuild. If a patch no longer applies, the build
fails, so a bump forces you to check whether upstream has fixed it yet. To
compute the new hash:

```bash
curl -fsSL "https://bird.nic.cz/download/bird-${BIRD_VERSION}.tar.gz" | sha256sum
```

To move a base image, set `BASE_IMAGE` to the new tag and its index digest:

```bash
docker buildx imagetools inspect alpine:3.24.2 --format '{{json .Manifest}}' | jq -r .digest
```

## Patches

Each build context has a `patches/` directory, and its patches are applied to
the verified tarball before `configure`. Each patch's header explains the fix
and when it can be removed.

| Patch | Fixes |
|-------|-------|
| `rte-announce-overread.patch` | An upstream bug, present in 3.3.3 and the current development branch. Every route announcement copies the journal's aligned slot size (48 bytes on x86_64) out of a 40-byte struct on the stack. On glibc, the extra 8 bytes are read without any visible effect. Alpine compiles with `_FORTIFY_SOURCE=2` by default, so its fortify headers catch the over-read and BIRD dies with SIGILL on its first route. This is why Alpine tags up to the original `3.3.3-alpine` could not hold a BGP session. |

## License

The Dockerfiles and docs in this repository are licensed under
[Apache 2.0](LICENSE). BIRD itself is licensed under the GNU GPL. See
[bird.nic.cz](https://bird.nic.cz).
