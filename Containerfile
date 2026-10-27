# Debian userspace with libgpiod 2.2.1 (matches common BBB Debian images).
# Default arch = host arch so ioctl against host gpio-sim is reliable on RHEL9.
ARG DEBIAN_TAG=bookworm
FROM debian:${DEBIAN_TAG}

ARG LIBGPIOD_VER=2.2.1
ENV DEBIAN_FRONTEND=noninteractive \
    LIBGPIOD_VER=${LIBGPIOD_VER}

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      xz-utils \
      build-essential \
      autoconf \
      automake \
      libtool \
      pkg-config \
      m4 \
      python3 \
    && rm -rf /var/lib/apt/lists/*

# Build libgpiod from the exact release tarball (tools + C library).
WORKDIR /tmp/libgpiod-src
RUN set -eux; \
    curl -fsSL \
      "https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/snapshot/libgpiod-${LIBGPIOD_VER}.tar.gz" \
      -o libgpiod.tar.gz; \
    tar -xzf libgpiod.tar.gz --strip-components=1; \
    ./autogen.sh \
      --prefix=/usr/local \
      --enable-tools=yes \
      --enable-bindings-cxx=no \
      --enable-bindings-python=no; \
    make -j"$(nproc)"; \
    make install; \
    ldconfig; \
    gpiodetect --version; \
    rm -rf /tmp/libgpiod-src

COPY entrypoint.sh /usr/local/bin/bbb-gpio-entrypoint
RUN chmod +x /usr/local/bin/bbb-gpio-entrypoint

WORKDIR /root
ENTRYPOINT ["/usr/local/bin/bbb-gpio-entrypoint"]
CMD []
