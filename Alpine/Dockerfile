# Global scope (before the first FROM) so every stage can import it with a bare
# `ARG BIRD_VERSION`. A default declared inside a stage never reaches later
# stages, which is why the image.version label was empty through 3.2.2.
ARG BIRD_VERSION="3.3.3"
# Base pinned by tag and index digest so a rebuild is the same build; a floating
# tag would undercut the tarball SHA256 pin below. Bump deliberately; re-derive
# the digest with:
#   docker buildx imagetools inspect alpine:<ver> --format '{{json .Manifest}}' | jq -r .digest
ARG BASE_IMAGE="alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6"

FROM ${BASE_IMAGE} AS builder

ARG BIRD_VERSION
ARG BIRD_URL="https://bird.nic.cz/download/bird-${BIRD_VERSION}.tar.gz"
# SHA256 of the upstream tarball, verified against bird.nic.cz over HTTPS on
# 2026-10-12 from two vantage points (Mac + docker-dev, matching). Bump in
# lockstep with BIRD_VERSION; re-derive with:
#   curl -fsSL "$BIRD_URL" | sha256sum
ARG BIRD_SHA256="7e8b28a17dd619eb73eba959ef6a944dd9c11cf5c1700a2ecbb8eb13bd4a8a57"

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

# Local fixes on top of the verified tarball; each patch's header says why and
# when it can go. A patch that no longer applies fails the build, which forces a
# re-check on every BIRD_VERSION bump. rte-announce-overread.patch is what
# keeps this image from dying with SIGILL on its first route (Alpine enables
# _FORTIFY_SOURCE=2 by default).
COPY patches/ /usr/src/patches/
RUN set -eux \
    && for p in /usr/src/patches/*.patch; do \
        patch -p1 --forward --batch -d /usr/src/bird-${BIRD_VERSION}/ < "$p"; \
    done

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

FROM ${BASE_IMAGE}

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
