FROM debian:bookworm-slim AS builder

ARG BIRD_VERSION="3.1.2"
ARG BIRD_URL="https://bird.network.cz/download/bird-${BIRD_VERSION}.tar.gz"

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

RUN wget -O bird.tar.gz ${BIRD_URL} \
    && tar -xzvf bird.tar.gz -C /usr/src/ \
    && rm -rf bird.tar.gz

RUN set -eux \
    && cd /usr/src/bird-${BIRD_VERSION}/ \
    && ./configure \
        --prefix=/usr/ \
        --sysconfdir=/etc/bird/ \
        --localstatedir=/var/ \
        --enable-libssh \
    && make -j $(nproc) \
    && make install \
    && { find /usr/sbin/bird* -type f -executable -exec strip --strip-all "{}" +; }

######

FROM debian:bookworm-slim

ARG BIRD_VERSION
ARG DATE_CREATED
ARG UID=179
ARG GID=179
ENV DEBIAN_FRONTEND=noninteractive

LABEL com.bzsparks.image.title="bird" \
    com.bzsparks.image.description="The BIRD Internet Routing Daemon" \
    com.bzsparks.image.url="https://github.com/bzsparks/docker-bird" \
    com.bzsparks.image.vendor="bzsparks.com" \
    com.bzsparks.image.author="Ben Sparks" \
    com.bzsparks.version="$BIRD_VERSION" \
    com.bzsparks.image.created="$DATE_CREATED"

COPY --from=builder /usr/sbin/bird* /usr/sbin/
COPY --from=builder /etc/bird/ /etc/bird/

# Create user and group
RUN addgroup --system -gid ${GID} bird && \
    adduser --system -uid ${UID} --no-create-home --ingroup bird --shell /usr/sbin/nologin bird

# Create default configuration file
RUN mkdir -p /etc/bird && chown root:bird /etc/bird/ && chmod 750 /etc/bird
#RUN touch /etc/bird/bird.conf && chown root:bird /etc/bird/bird.conf && chmod 644 /etc/bird/bird.conf

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

EXPOSE 179/tcp

ENTRYPOINT ["/usr/sbin/bird", "-u", "bird", "-g", "bird"]
CMD ["-f", "-c", "/etc/bird/bird.conf"]
