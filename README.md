<h1 align="center">BIRD</h1>

<p align="center">The BIRD project aims to develop a fully functional dynamic IP routing daemon.</p>

<p align="center">
    <a href="https://bird.network.cz">Project Source</a>
</p>

---

### Start Container

```bash
$ docker run -d \
  -v /etc/bird/bird.conf:/etc/bird/bird.conf:ro \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --network=host \
  --restart=always \
  --name=bird \
  ghcr.io/bzsparks/bird
```
