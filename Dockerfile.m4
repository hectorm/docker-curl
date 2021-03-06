m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/alpine:3]], [[FROM docker.io/alpine:3]]) AS build
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectormolinero/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN apk add --no-cache \
		autoconf \
		automake \
		build-base \
		coreutils \
		curl \
		findutils \
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
ENV CFLAGS='-O2 -fstack-protector-strong -frandom-seed=42 -Wformat -Werror=format-security'
m4_ifelse(CROSS_ARCH, amd64, [[ENV CFLAGS="${CFLAGS} -fstack-clash-protection -fcf-protection=full"]])
ENV CXXFLAGS=${CFLAGS}
ENV CPPFLAGS='-Wdate-time -D_FORTIFY_SOURCE=2'
ENV LDFLAGS='-static -Wl,-z,defs -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack'
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

# Build zstd
ARG ZSTD_TREEISH=v1.5.0
ARG ZSTD_REMOTE=https://github.com/facebook/zstd.git
RUN mkdir /tmp/zstd/
WORKDIR /tmp/zstd/
RUN git clone "${ZSTD_REMOTE:?}" ./
RUN git checkout "${ZSTD_TREEISH:?}"
RUN git submodule update --init --recursive
WORKDIR /tmp/zstd/lib/
RUN make libzstd.a-release -j"$(nproc)"
RUN make install-pc install-static install-includes PREFIX="${TMPPREFIX:?}"

# Build OpenSSL
ARG OPENSSL_TREEISH=OpenSSL_1_1_1k
ARG OPENSSL_REMOTE=https://github.com/openssl/openssl.git
RUN mkdir /tmp/openssl/
WORKDIR /tmp/openssl/
RUN git clone "${OPENSSL_REMOTE:?}" ./
RUN git checkout "${OPENSSL_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./config --prefix="${TMPPREFIX:?}" no-shared no-engine
RUN make build_libs OPENSSLDIR= ENGINESDIR= -j"$(nproc)"
RUN make install_dev

# Build Nghttp2
ARG NGHTTP2_TREEISH=v1.44.0
ARG NGHTTP2_REMOTE=https://github.com/nghttp2/nghttp2.git
RUN mkdir /tmp/nghttp2/
WORKDIR /tmp/nghttp2/
RUN git clone "${NGHTTP2_REMOTE:?}" ./
RUN git checkout "${NGHTTP2_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi && automake && autoconf
RUN ./configure --prefix="${TMPPREFIX:?}" --enable-static --disable-shared --enable-lib-only
RUN make -j"$(nproc)"
RUN make install

# Build libssh2
ARG LIBSSH2_TREEISH=libssh2-1.9.0
ARG LIBSSH2_REMOTE=https://github.com/libssh2/libssh2.git
RUN mkdir /tmp/libssh2/
WORKDIR /tmp/libssh2/
RUN git clone "${LIBSSH2_REMOTE:?}" ./
RUN git checkout "${LIBSSH2_TREEISH:?}"
RUN git submodule update --init --recursive
# TODO: Remove when libssh2/libssh2#594 arrives to a stable version
RUN sed -ri '/m4_undefine\(\[backend\]\)/d' ./configure.ac
RUN ./buildconf
RUN ./configure --prefix="${TMPPREFIX:?}" --enable-static --disable-shared
RUN make -j"$(nproc)"
RUN make install

# Build cURL
ARG CURL_TREEISH=curl-7_77_0
ARG CURL_REMOTE=https://github.com/curl/curl.git
RUN mkdir /tmp/curl/
WORKDIR /tmp/curl/
RUN git clone "${CURL_REMOTE:?}" ./
RUN git checkout "${CURL_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi && automake && autoconf
RUN ./lib/mk-ca-bundle.pl ./ca-bundle.crt
RUN ./configure --prefix="${TMPPREFIX:?}" --enable-static --disable-shared \
		--with-ca-bundle=./ca-bundle.crt \
		--with-zlib="${TMPPREFIX:?}" \
		--with-zstd="${TMPPREFIX:?}" \
		--with-openssl="${TMPPREFIX:?}" \
		--with-nghttp2="${TMPPREFIX:?}" \
		--with-libssh2="${TMPPREFIX:?}" \
		LDFLAGS="--static ${LDFLAGS-}"
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
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--http2-prior-knowledge", "--tlsv1.3", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--doh-url", "https://1.1.1.1/dns-query", "https://cloudflare.com"]

##################################################
## "curl" stage
##################################################

FROM base AS curl

ENTRYPOINT ["/curl"]
CMD ["--help"]
