FROM alpine:latest AS builder

ARG BIRD_VERSION="3.2.2"
ARG BIRD_URL="https://bird.nic.cz/download/bird-${BIRD_VERSION}.tar.gz"
# SHA256 of the upstream tarball, verified against bird.nic.cz over HTTPS on
# 2026-06-24. Bump in lockstep with BIRD_VERSION; re-derive with:
#   curl -fsSL "$BIRD_URL" | sha256sum
ARG BIRD_SHA256="5b275f0f91c063bd0369a2996982f8f578736eb9b4b5c0fb62a275ec663f74df"

ARG UID=179
ARG GID=179

RUN set -eux \
    && apk add --no-cache \
        ca-certificates \
        wget \
        build-base \
        flex \
        bison \
        ncurses-dev \
        readline-dev \
        libssh-dev \
        linux-headers

RUN set -eux \
    && mkdir -p /usr/src \
    && wget -O /tmp/bird.tar.gz "${BIRD_URL}" \
    && echo "${BIRD_SHA256}  /tmp/bird.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/bird.tar.gz -C /usr/src/ \
    && rm -f /tmp/bird.tar.gz

# Build and install into a clean DESTDIR (/install)
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

FROM alpine:latest

ARG BIRD_VERSION
ARG DATE_CREATED
ARG UID=179
ARG GID=179

LABEL org.opencontainers.image.title="bird" \
    org.opencontainers.image.description="The BIRD Internet Routing Daemon" \
    org.opencontainers.image.vendor="https://bird.nic.cz/" \
    org.opencontainers.image.author="bzsparks" \
    org.opencontainers.image.version="$BIRD_VERSION" \
    org.opencontainers.image.created="$DATE_CREATED"

COPY --from=builder /install/usr/sbin/ /usr/sbin/
COPY --from=builder /install/etc/bird/ /etc/bird/

# Create user and group
RUN addgroup -g ${GID} -S bird && \
    adduser -u ${UID} -D -S -G bird -s /bin/false bird

# Create default configuration directory
RUN mkdir -p /etc/bird && chown root:bird /etc/bird/ && chmod 750 /etc/bird

RUN set -eux \
    && apk add --no-cache \
        iproute2 \
        ncurses-libs \
        readline \
        libssh \
        iputils \
        procps

EXPOSE 179/tcp

ENTRYPOINT ["/usr/sbin/bird", "-f", "-u", "bird", "-g", "bird"]
#CMD ["-f", "-c", "/etc/bird/bird.conf"]
