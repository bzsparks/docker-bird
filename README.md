<h1 align="center">docker-bird</h1>

<p align="center">Hardened Docker images for the BIRD Internet Routing Daemon</p>

<p align="center">
  <a href="https://bird.nic.cz">Project Source</a>
</p>

---

### Images

| Image | Tag | Base |
|-------|-----|------|
| `bzsprks/bird` | `latest`, `3.2.1` | `debian:trixie-slim` |
| `bzsprks/bird` | `3.2.1-alpine` | `alpine:latest` |

---

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     Host Machine                             │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │         docker run bzsprks/bird:3.2.1                  │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Capabilities (no full privileged mode):         │  │  │
│  │  │  CAP_NET_ADMIN   ─ manipulate routing tables     │  │  │
│  │  │  CAP_NET_BIND_SERVICE ─ bind to ports < 1024    │  │  │
│  │  │  CAP_NET_BROADCAST ─ broadcast/multicast        │  │  │
│  │  │  CAP_NET_RAW       ─ raw sockets for ICMP/BGP   │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  /usr/sbin/bird -f -u bird -g bird               │  │  │
│  │  │                                                  │  │  │
│  │  │  bird  ── BGP speaker ──►  :179/tcp              │  │  │
│  │  │       ── routing table ──► host kernel RIB       │  │  │
│  │  │       ── config ──► /etc/bird/bird.conf (vol)    │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                                                        │  │
│  │  Volume mount:                                         │  │
│  │    /etc/bird/bird.conf ──► /etc/bird/bird.conf:ro     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ── network=host (shares host network namespace) ──         │
└──────────────────────────────────────────────────────────────┘
```

BIRD runs inside a minimal container with `--network=host` to share the host's network namespace. It receives only the four capabilities required to manipulate routing tables and speak BGP — no full `--privileged` mode. Configuration is mounted read-only from the host via a volume bind.

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

### Configuration

Mount your BIRD configuration file as a read-only volume:

```
-v /path/to/bird.conf:/etc/bird/bird.conf:ro
```

BIRD runs as the unprivileged `bird` user (UID 179, GID 179).

### Build Locally

```bash
# Debian
cd Debian && docker build -t bird:test .

# Alpine
cd Alpine && docker build -t bird-alpine:test .
```

Verify the installed version:

```bash
docker run --rm --entrypoint '' bird:test /usr/sbin/bird --version
```

### Notes

- BIRD requires `--network=host` to access the host's routing table and network interfaces directly.
- The four capabilities are the minimum required. BIRD will fail to start without `CAP_NET_ADMIN` — it needs this to manipulate the kernel routing table.
- BGP peer connections listen on TCP port 179. Ensure your firewall allows inbound/outbound traffic on this port.
