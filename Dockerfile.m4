m4_changequote([[, ]])

m4_ifdef([[CROSS_QEMU]], [[
##################################################
## "qemu-user-static" stage
##################################################

FROM ubuntu:18.04 AS qemu-user-static
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends qemu-user-static
]])

##################################################
## "build" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM CROSS_ARCH/alpine:edge]], [[FROM alpine:edge]]) AS build
m4_ifdef([[CROSS_QEMU]], [[COPY --from=qemu-user-static CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN apk add --no-cache \
		autoconf \
		automake \
		build-base \
		curl \
		git \
		libtool \
		linux-headers \
		perl \
		pkgconf

# Switch to unprivileged user
ENV USER=builder GROUP=builder
RUN addgroup -S "${GROUP}"
RUN adduser -S -G "${GROUP}" "${USER}"
USER "${USER}:${GROUP}"

# Environment
ENV CFLAGS='-O2 -fPIE -fstack-protector-strong -frandom-seed=42 -Wformat -Werror=format-security'
ENV CPPFLAGS='-Wdate-time -D_FORTIFY_SOURCE=2'
ENV LDFLAGS='--static -Wl,-z,relro -Wl,-z,now'
ENV LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1

# Build zlib
ARG ZLIB_TREEISH=v1.2.11
ARG ZLIB_REMOTE=https://github.com/madler/zlib.git
RUN mkdir /tmp/zlib/
WORKDIR /tmp/zlib/
RUN git clone "${ZLIB_REMOTE}" ./
RUN git checkout "${ZLIB_TREEISH}"
RUN git submodule update --init --recursive
RUN ./configure --prefix=/tmp/usr --static
RUN make -j"$(nproc)"
RUN make install

# Build OpenSSL
ARG OPENSSL_TREEISH=OpenSSL_1_1_1b
ARG OPENSSL_REMOTE=https://github.com/openssl/openssl.git
RUN mkdir /tmp/openssl/
WORKDIR /tmp/openssl/
RUN git clone "${OPENSSL_REMOTE}" ./
RUN git checkout "${OPENSSL_TREEISH}"
RUN git submodule update --init --recursive
RUN ./config --prefix=/tmp/usr no-shared no-engine
RUN make build_libs OPENSSLDIR= ENGINESDIR= -j"$(nproc)"
RUN make install_dev

# Build Nghttp2
ARG NGHTTP2_TREEISH=v1.38.0
ARG NGHTTP2_REMOTE=https://github.com/nghttp2/nghttp2.git
RUN mkdir /tmp/nghttp2/
WORKDIR /tmp/nghttp2/
RUN git clone "${NGHTTP2_REMOTE}" ./
RUN git checkout "${NGHTTP2_TREEISH}"
RUN git submodule update --init --recursive
RUN autoreconf -i && automake && autoconf
RUN ./configure --prefix=/tmp/usr --enable-static --disable-shared --enable-lib-only
RUN make -j"$(nproc)"
RUN make install

# Build cURL
ARG CURL_TREEISH=curl-7_64_1
ARG CURL_REMOTE=https://github.com/curl/curl.git
ARG CURL_TESTS=enabled
RUN mkdir /tmp/curl/
WORKDIR /tmp/curl/
RUN git clone "${CURL_REMOTE}" ./
RUN git checkout "${CURL_TREEISH}"
RUN git submodule update --init --recursive
RUN ./buildconf
RUN ./lib/mk-ca-bundle.pl ./ca-bundle.crt
RUN ./configure --prefix=/tmp/usr --enable-static --disable-shared \
		--with-ca-bundle=./ca-bundle.crt \
		--with-zlib=/tmp/usr \
		--with-ssl=/tmp/usr \
		--with-nghttp2=/tmp/usr
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
m4_ifdef([[CROSS_QEMU]], [[COPY --from=qemu-user-static CROSS_QEMU CROSS_QEMU]])

RUN ["/curl", "--version"]
RUN ["/curl", "--verbose", "--silent", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--http2-prior-knowledge", "--tlsv1.3", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--doh-url", "https://1.1.1.1/dns-query", "https://cloudflare.com"]

##################################################
## "curl" stage
##################################################

FROM base AS curl

ENTRYPOINT ["/curl"]
CMD ["--help"]
