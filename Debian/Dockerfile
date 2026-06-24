FROM debian:trixie-slim AS builder

ARG BIRD_VERSION="3.2.2"
#ARG BIRD_URL="https://bird.network.cz/download/bird-${BIRD_VERSION}.tar.gz"
ARG BIRD_URL="https://bird.nic.cz/download/bird-${BIRD_VERSION}.tar.gz"
# SHA256 of the upstream tarball, verified against bird.nic.cz over HTTPS on
# 2026-06-24. Upstream publishes no .asc/SHA256SUMS, so this pin is the
# supply-chain control. Bump in lockstep with BIRD_VERSION; re-derive with:
#   curl -fsSL "$BIRD_URL" | sha256sum
ARG BIRD_SHA256="5b275f0f91c063bd0369a2996982f8f578736eb9b4b5c0fb62a275ec663f74df"

ENV DEBIAN_FRONTEND=noninteractive
ARG UID=179
ARG GID=179

RUN set -eux \
    && apt-get update -qyy \
    && apt-get install -qyy --no-install-recommends --no-install-suggests \
        ca-certificates \
        wget \
        build-essential \
        gawk \
        flex \
        bison \
        libncurses-dev \
        libreadline-dev \
        libssh-dev \
    && rm -rf /var/lib/apt/lists/* /var/log/*

RUN set -eux \
    && mkdir -p /usr/src \
    && wget -O /tmp/bird.tar.gz "${BIRD_URL}" \
    && echo "${BIRD_SHA256}  /tmp/bird.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/bird.tar.gz -C /usr/src/ \
    && rm -f /tmp/bird.tar.gz

RUN set -eux \
    && cd /usr/src/bird-${BIRD_VERSION}/ \
    && ./configure \
        --prefix=/usr/ \
        --sysconfdir=/etc/bird/ \
        #--enable-debug \
        --localstatedir=/var/ \
        --enable-libssh \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make install DESTDIR=/install \
    # strip any installed executables under /install to reduce final image size
    && { find /install -type f -executable -exec strip --strip-all "{}" + || true; }

######

FROM debian:trixie-slim

ARG BIRD_VERSION
ARG DATE_CREATED
ARG UID=179
ARG GID=179
ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="bird" \
    org.opencontainers.image.description="The BIRD Internet Routing Daemon" \
    org.opencontainers.image.vendor="https://bird.network.cz/" \
    org.opencontainers.image.author="bzsparks" \
    org.opencontainers.image.version="$BIRD_VERSION" \
    org.opencontainers.image.created="$DATE_CREATED"

COPY --from=builder /install/usr/sbin/ /usr/sbin/
COPY --from=builder /install/etc/bird/ /etc/bird/

RUN set -eux \
    && apt-get update -qyy \
    && apt-get install -qyy --no-install-recommends --no-install-suggests \
        iproute2 \
        libtinfo6 \
        libreadline8 \
        libssh-4 \
        iputils-ping \
        procps \
		dnsutils \
	passwd \
    && rm -rf /var/lib/apt/lists/* /var/log/*

# NOTE: the absence of a `USER bird` directive is intentional and load-bearing.
# The default ENTRYPOINT drops privileges itself (`bird -u bird -g bird`), so
# the daemon runs unprivileged. Containers that REUSE this image with a custom
# entrypoint — e.g. the anycast health sidecar that runs `ip addr` ops — rely
# on the container starting as root so that cap_add NET_ADMIN is effective
# (a non-root process gets added caps in its bounding set, not its effective
# set, without ambient caps). Adding `USER bird` here would silently break
# those reuses. Drop privileges in the entrypoint, never via USER.
RUN groupadd --system --gid ${GID} bird && \
    useradd --system --uid ${UID} --no-create-home --gid bird --shell /usr/sbin/nologin bird

# Create default configuration directory
RUN mkdir -p /etc/bird && chown root:bird /etc/bird/ && chmod 750 /etc/bird

HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=30s \
            --retries=3 \
    CMD /usr/sbin/birdc show protocols | grep -q "Established" || exit 1

EXPOSE 179/tcp

ENTRYPOINT ["/usr/sbin/bird", "-u", "bird", "-g", "bird"]
CMD ["-f", "-c", "/etc/bird/bird.conf"]
