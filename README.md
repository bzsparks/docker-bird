<h1 align="center">docker-bird</h1>

<p align="center">Minimal Docker images for the BIRD Internet Routing Daemon</p>

<p align="center">
  <a href="https://bird.nic.cz">Project Source</a>
</p>

---

### Images

| Image | Tags | Base |
|-------|------|------|
| `bzsprks/bird` | `latest`, `3.2.1` | `debian:trixie-slim` |
| `bzsprks/bird` | `3.2.1-alpine` | `alpine:latest` |

Each image contains BIRD 3.2.1 compiled from source with libssh (RPKI) support. The process runs as the unprivileged `bird` user (UID 179, GID 179).

---

### Runtime Requirements

BIRD manipulates the kernel routing table of whatever network namespace it runs in. It needs access to the interfaces and routes it's configured to manage. This can be:

- **`--network=host`** — the host's network namespace (common for host-level routing)
- **`network_mode: "service:xxx"`** — another container's network namespace (e.g., sharing with a DNS server)
- Any arrangement where BIRD has visibility of the interfaces and routes it needs

Regardless of network mode, the container needs:

- **Four capabilities** (minimum, no `--privileged`):

| Capability | Purpose |
|------------|---------|
| `CAP_NET_ADMIN` | Manipulate kernel routing table (required) |
| `CAP_NET_BIND_SERVICE` | Bind to port 179 |
| `CAP_NET_BROADCAST` | Broadcast/multicast |
| `CAP_NET_RAW` | Raw sockets for ICMP/BGP |

- **Config volume** — BIRD configuration mounted read-only at `/etc/bird/bird.conf`

---

### Start Container

**Debian (recommended):**

```bash
docker run -d \
  -v /etc/bird/bird.conf:/etc/bird/bird.conf:ro \
  --cap-add=NET_ADMIN \
  --cap-add=NET_BIND_SERVICE \
  --cap-add=NET_BROADCAST \
  --cap-add=NET_RAW \
  --network=host \
  --restart=always \
  --name=bird \
  bzsprks/bird:3.2.1
```

**Alpine:**

```bash
docker run -d \
  -v /etc/bird/bird.conf:/etc/bird/bird.conf:ro \
  --cap-add=NET_ADMIN \
  --cap-add=NET_BIND_SERVICE \
  --cap-add=NET_BROADCAST \
  --cap-add=NET_RAW \
  --network=host \
  --restart=always \
  --name=bird-alpine \
  bzsprks/bird:3.2.1-alpine
```

### Image Differences

| | Debian | Alpine |
|--|--------|--------|
| Size | ~102 MB | ~16 MB |
| HEALTHCHECK | Yes (`birdc show protocols`) | No |
| ENTRYPOINT | `bird -u bird -g bird` | `bird -f -u bird -g bird` |
| CMD | `-f -c /etc/bird/bird.conf` | none |

### Build Locally

```bash
# Debian
cd Debian && docker build --no-cache -t bird:test .

# Alpine
cd Alpine && docker build --no-cache -t bird-alpine:test .
```

Verify the installed version:

```bash
docker run --rm --entrypoint /usr/sbin/bird bird:test --version
```

### Notes

- BIRD doesn't require `--network=host` specifically — it just needs a network namespace with the interfaces and routes it's configured to manage. `network_mode: "service:xxx"` works too.
- The four capabilities are the minimum. BIRD will fail without `CAP_NET_ADMIN` — it needs this to manipulate the kernel routing table.
- BGP peer connections listen on TCP port 179. Ensure your firewall allows inbound/outbound traffic on this port.
- Configuration is mounted read-only. BIRD runs as unprivileged user `bird` (UID/GID 179).
