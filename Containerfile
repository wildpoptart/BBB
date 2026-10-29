# Optional Debian userspace with libgpiod 1.6.3 (same major API as RHEL 9).
# Prefer container/Containerfile.rhel9 for the Zorin lab.
ARG DEBIAN_TAG=bookworm
FROM debian:${DEBIAN_TAG}

ARG LIBGPIOD_VER=1.6.3
ENV DEBIAN_FRONTEND=noninteractive \
    LIBGPIOD_VER=${LIBGPIOD_VER}

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils \
      build-essential autoconf automake libtool pkg-config m4 python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/libgpiod-src
RUN set -eux; \
    curl -fsSL \
      "https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/snapshot/libgpiod-${LIBGPIOD_VER}.tar.gz" \
      -o libgpiod.tar.gz; \
    tar -xzf libgpiod.tar.gz --strip-components=1; \
    ./autogen.sh --prefix=/usr/local --enable-tools=yes --enable-bindings-cxx=no; \
    make -j"$(nproc)"; make install; ldconfig; \
    gpiodetect --version; \
    rm -rf /tmp/libgpiod-src

COPY entrypoint.sh /usr/local/bin/bbb-gpio-entrypoint
RUN chmod +x /usr/local/bin/bbb-gpio-entrypoint
WORKDIR /root
ENTRYPOINT ["/usr/local/bin/bbb-gpio-entrypoint"]
CMD []
