<h1 align="center">docker-bird</h1>

<p align="center">Minimal Docker images for the BIRD Internet Routing Daemon</p>

<p align="center">
  <a href="https://bird.nic.cz">Project Source</a>
</p>

---

### Images

| Image | Tags | Base |
|-------|------|------|
| `bzsprks/bird` | `latest`, `3.2.2` | `debian:trixie-slim` |
| `bzsprks/bird` | `3.2.2-alpine` | `alpine:latest` |

Each image contains BIRD 3.2.2 compiled from source with libssh (RPKI) support. The process runs as the unprivileged `bird` user (UID 179, GID 179).

---

### Sidecar Deployment

```text
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                                     Host Machine                                         │
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                           Shared Network Namespace                                 │  │
│  │                                                                                     │  │
│  │  ┌────────────────────────┐  ┌──────────────────────────────────────┐              │  │
│  │  │    Primary Service     │  │              BIRD Sidecar             │              │  │
│  │  │                        │  │                                      │              │  │
│  │  │  ┌──────────────────┐  │  │  ┌──────────────────────────────┐   │              │  │
│  │  │  │  eth0 (10.0.0.10)│  │  │  │                               │   │              │  │
│  │  │  │                  │◄─┼──┼─┤  /usr/sbin/bird                │   │              │  │
│  │  │  │  lo:0 (10.0.0.11)│  │  │  │  -u bird -g bird              │   │              │  │
│  │  │  └──────────────────┘  │  │  │                               │   │              │  │
│  │  │                        │  │  └──────────────────────────────┘   │              │  │
│  │  │                        │  │                                      │              │  │
│  │  │  named (BIND9 DNS)     │  │  /etc/bird/bird.conf                │              │  │
│  │  │  :53/udp, :53/tcp      │  │  (mounted :ro)                      │              │  │
│  │  └────────────────────────┘  └──────────────────────────────────────┘              │  │
│  │                                                                                     │  │
│  │  ┌────────────────────────────────────────────────────────────────────────────────┐ │  │
│  │  │                              Shared Kernel State                                │ │  │
│  │  │  • Routing table   ── BIRD programs BGP routes here                            │ │  │
│  │  │  • Interfaces      ── both containers see the same set                         │ │  │
│  │  │  • ARP table       ── shared L2 resolution                                     │ │  │
│  │  └────────────────────────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                          │
│  BGP Peering:  :179/tcp ──────────────────────────────────────────────────────────────► │
│  (on shared ns)   BIRD speaks BGP on behalf of the primary service                       │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

With `network_mode: "service:primary"`, BIRD shares the network namespace of another container. It manipulates that container's routing table and speaks BGP on its interfaces — no `--network=host` needed.

```yaml
services:
  bind9:
    image: internetsystemsconsortium/bind9:9.20
    # ... DNS server config ...

  bird:
    image: bzsprks/bird:3.2.2
    network_mode: "service:bind9"
    cap_add:
      - NET_ADMIN
      - NET_BIND_SERVICE
      - NET_BROADCAST
      - NET_RAW
    volumes:
      - './bird/bird.conf:/etc/bird/bird.conf:ro'
    depends_on:
      bind9:
        condition: service_healthy
```

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
  bzsprks/bird:3.2.2
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
  bzsprks/bird:3.2.2-alpine
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
