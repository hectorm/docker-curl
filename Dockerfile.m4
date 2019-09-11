m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/alpine:edge]], [[FROM docker.io/alpine:edge]]) AS build
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectormolinero/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN apk add --no-cache \
		autoconf \
		automake \
		build-base \
		coreutils \
		curl \
		git \
		libtool \
		linux-headers \
		perl \
		pkgconf

# Switch to unprivileged user
ENV USER=builder GROUP=builder
RUN addgroup -S "${GROUP:?}"
RUN adduser -S -G "${GROUP:?}" "${USER:?}"
USER "${USER}:${GROUP}"

# Environment
ENV TMPPREFIX=/tmp/usr
ENV CFLAGS='-O2 -fPIC -fPIE -fstack-protector-strong -frandom-seed=42 -Wformat -Werror=format-security'
ENV CXXFLAGS=${CFLAGS}
ENV CPPFLAGS='-Wdate-time -D_FORTIFY_SOURCE=2'
ENV LDFLAGS='--static -Wl,-z,relro -Wl,-z,now'
ENV PKG_CONFIG_PATH=${TMPPREFIX}/lib/pkgconfig
ENV LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1

# Build zlib
ARG ZLIB_TREEISH=v1.2.11
ARG ZLIB_REMOTE=https://github.com/madler/zlib.git
RUN mkdir /tmp/zlib/
WORKDIR /tmp/zlib/
RUN git clone "${ZLIB_REMOTE:?}" ./
RUN git checkout "${ZLIB_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./configure --prefix="${TMPPREFIX:?}" --static
RUN make -j"$(nproc)"
RUN make install

# Build OpenSSL
ARG OPENSSL_TREEISH=openssl-quic-draft-22
ARG OPENSSL_REMOTE=https://github.com/tatsuhiro-t/openssl.git
RUN mkdir /tmp/openssl/
WORKDIR /tmp/openssl/
RUN git clone "${OPENSSL_REMOTE:?}" ./
RUN git checkout "${OPENSSL_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./config --prefix="${TMPPREFIX:?}" no-shared no-engine
RUN make build_libs OPENSSLDIR= ENGINESDIR= -j"$(nproc)"
RUN make install_dev

# Build Nghttp2
ARG NGHTTP2_TREEISH=v1.39.2
ARG NGHTTP2_REMOTE=https://github.com/nghttp2/nghttp2.git
RUN mkdir /tmp/nghttp2/
WORKDIR /tmp/nghttp2/
RUN git clone "${NGHTTP2_REMOTE:?}" ./
RUN git checkout "${NGHTTP2_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -i && automake && autoconf
RUN ./configure --prefix="${TMPPREFIX:?}" --enable-static --disable-shared --enable-lib-only
RUN make -j"$(nproc)"
RUN make install

# Build Ngtcp2
ARG NGTCP2_TREEISH=draft-22
ARG NGTCP2_REMOTE=https://github.com/ngtcp2/ngtcp2.git
RUN mkdir /tmp/ngtcp2/
WORKDIR /tmp/ngtcp2/
RUN git clone "${NGTCP2_REMOTE:?}" ./
RUN git checkout "${NGTCP2_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -i && automake && autoconf
RUN ./configure --prefix="${TMPPREFIX:?}" --enable-static --disable-shared
RUN make -j"$(nproc)"
RUN make install

# Build Nghttp3
ARG NGHTTP3_TREEISH=master
ARG NGHTTP3_REMOTE=https://github.com/ngtcp2/nghttp3.git
RUN mkdir /tmp/nghttp3/
WORKDIR /tmp/nghttp3/
RUN git clone "${NGHTTP3_REMOTE:?}" ./
RUN git checkout "${NGHTTP3_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -i && automake && autoconf
RUN ./configure --prefix="${TMPPREFIX:?}" --enable-static --disable-shared --enable-lib-only
RUN make -j"$(nproc)"
RUN make install

# Build cURL
ARG CURL_TREEISH=curl-7_66_0
ARG CURL_REMOTE=https://github.com/curl/curl.git
ARG CURL_TESTS=enabled
RUN mkdir /tmp/curl/
WORKDIR /tmp/curl/
RUN git clone "${CURL_REMOTE:?}" ./
RUN git checkout "${CURL_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./buildconf
RUN ./lib/mk-ca-bundle.pl ./ca-bundle.crt
RUN ./configure --prefix="${TMPPREFIX:?}" --enable-static --disable-shared \
		--with-ca-bundle=./ca-bundle.crt \
		--with-zlib="${TMPPREFIX:?}" \
		--with-ssl="${TMPPREFIX:?}" \
		--with-nghttp2="${TMPPREFIX:?}" \
		--with-ngtcp2="${TMPPREFIX:?}"
RUN make -j"$(nproc)"
RUN make install-strip

##################################################
## "base" stage
##################################################

FROM scratch AS base

# Copy cURL binary and certificate bundle
COPY --from=build /tmp/usr/bin/curl /tmp/curl/ca-bundle.crt /

##################################################
## "test" stage
##################################################

FROM base AS test
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectormolinero/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

RUN ["/curl", "--version"]
RUN ["/curl", "--verbose", "--silent", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--http2-prior-knowledge", "--tlsv1.3", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--doh-url", "https://1.1.1.1/dns-query", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--http3", "https://quic.tech:8443"]

##################################################
## "curl" stage
##################################################

FROM base AS curl

ENTRYPOINT ["/curl"]
CMD ["--help"]
