FROM debian:trixie-slim AS builder

ARG BIRD_VERSION="3.1.4"
#ARG BIRD_URL="https://bird.network.cz/download/bird-${BIRD_VERSION}.tar.gz"
ARG BIRD_URL="https://bird.nic.cz/download/bird-${BIRD_VERSION}.tar.gz"

ENV DEBIAN_FRONTEND=noninteractive
ARG UID=179
ARG GID=179

RUN set -eux \
    && apt-get update -qyy \
    && apt-get install -qyy --no-install-recommends --no-install-suggests \
        ca-certificates \
        wget \
        build-essential \
        flex \
        bison \
        libncurses-dev \
        libreadline-dev \
        libssh-dev \
    && rm -rf /var/lib/apt/lists/* /var/log/*

RUN set -eux \
    && mkdir -p /usr/src \
    && wget -O /tmp/bird.tar.gz "${BIRD_URL}" \
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

RUN groupadd --system --gid ${GID} bird && \
    useradd --system --uid ${UID} --no-create-home --gid bird --shell /usr/sbin/nologin bird

# Create default configuration directory
RUN mkdir -p /etc/bird && chown root:bird /etc/bird/ && chmod 750 /etc/bird

RUN set -eux \
    && apt-get update -qyy \
    && apt-get install -qyy --no-install-recommends --no-install-suggests \
        iproute2 \
        libtinfo6 \
        libreadline8 \
        libssh-4 \
        iputils-ping \
        procps \
    && rm -rf /var/lib/apt/lists/* /var/log/*

HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=30s \
            --retries=3 \
    CMD /usr/sbin/birdc show protocols | grep -q "Established" || exit 1

EXPOSE 179/tcp

ENTRYPOINT ["/usr/sbin/bird", "-u", "bird", "-g", "bird"]
CMD ["-f", "-c", "/etc/bird/bird.conf"]
