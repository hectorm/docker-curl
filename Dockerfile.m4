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
		cmake \
		coreutils \
		curl \
		findutils \
		git \
		jq \
		libc6-compat \
		libtool \
		linux-headers \
		perl \
		pkgconf

# Switch to unprivileged user
ENV USER=builder GROUP=builder HOME=/home/${USER}
RUN addgroup -S "${GROUP:?}"
RUN adduser -S -G "${GROUP:?}" "${USER:?}" -h "${HOME:?}"
USER "${USER}:${GROUP}"

# Environment
ENV TMPPREFIX=/tmp/usr
ENV CFLAGS='-O2 -fPIC -fPIE -fstack-protector-strong -frandom-seed=42 -Wformat -Werror=format-security'
ENV CXXFLAGS=${CFLAGS}
ENV CPPFLAGS='-Wdate-time -D_FORTIFY_SOURCE=2'
ENV LDFLAGS='--static -Wl,-z,relro -Wl,-z,now'
ENV PKG_CONFIG_PATH=${TMPPREFIX}/lib/pkgconfig
ENV LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf 'https://sh.rustup.rs' | sh -s -- -y
ENV PATH=${HOME}/.cargo/bin:${PATH}

# Install Go
ENV GOROOT=${HOME}/.goroot/ GOPATH=${HOME}/.gopath/
RUN mkdir -p "${GOROOT:?}" "${GOPATH:?}/bin" "${GOPATH:?}/src"
RUN GOLANG_VERSION=$(curl -sSLf 'https://golang.org/dl/?mode=json' | jq -r 'map(select(.version | startswith("go1."))) | first | .version') \
	&& case "$(uname -m)" in x86_64) GOLANG_ARCH=amd64 ;; aarch64) GOLANG_ARCH=arm64 ;; armv6l|armv7l) GOLANG_ARCH=armv6l ;; esac \
	&& GOLANG_PKG_URL=https://dl.google.com/go/${GOLANG_VERSION:?}.linux-${GOLANG_ARCH:?}.tar.gz \
	&& curl -sSLf "${GOLANG_PKG_URL:?}" | tar -xz --strip-components=1 -C "${GOROOT:?}"
ENV PATH=${GOROOT}/bin:${GOPATH}/bin:${PATH}

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
ARG ZSTD_TREEISH=v1.4.5
ARG ZSTD_REMOTE=https://github.com/facebook/zstd.git
RUN mkdir /tmp/zstd/
WORKDIR /tmp/zstd/
RUN git clone "${ZSTD_REMOTE:?}" ./
RUN git checkout "${ZSTD_TREEISH:?}"
RUN git submodule update --init --recursive
RUN make -j"$(nproc)"
RUN make install PREFIX="${TMPPREFIX:?}"

# Build BoringSSL and Quiche
ARG QUICHE_TREEISH=master
ARG QUICHE_REMOTE=https://github.com/cloudflare/quiche.git
RUN mkdir /tmp/quiche/
WORKDIR /tmp/quiche/
RUN git clone "${QUICHE_REMOTE:?}" ./
RUN git checkout "${QUICHE_TREEISH:?}"
RUN git submodule update --init --recursive
RUN mkdir /tmp/quiche/deps/boringssl/build/
WORKDIR /tmp/quiche/deps/boringssl/build/
RUN cmake ./ -D CMAKE_POSITION_INDEPENDENT_CODE=1 ../
RUN make -j"$(nproc)"
RUN cp -a ./crypto/libcrypto.a "${TMPPREFIX:?}"/lib/libcrypto.a
RUN cp -a ./decrepit/libdecrepit.a "${TMPPREFIX:?}"/lib/libdecrepit.a
RUN cp -a ./ssl/libssl.a "${TMPPREFIX:?}"/lib/libssl.a
RUN cp -a ../include/openssl/ "${TMPPREFIX:?}"/include/openssl/
WORKDIR /tmp/quiche/
RUN QUICHE_BSSL_PATH="${PWD:?}"/deps/boringssl cargo build --release --features=pkg-config-meta
RUN cp -a ./include/quiche.h "${TMPPREFIX:?}"/include/quiche.h
RUN cp -a ./target/release/libquiche.a "${TMPPREFIX:?}"/lib/libquiche.a
RUN cp -a ./target/release/quiche.pc "${TMPPREFIX:?}"/lib/pkgconfig/quiche.pc
RUN sed -i "s|^\(includedir\)=.*$|\1=${TMPPREFIX:?}/include|g" "${TMPPREFIX:?}"/lib/pkgconfig/quiche.pc
RUN sed -i "s|^\(libdir\)=.*$|\1=${TMPPREFIX:?}/lib|g" "${TMPPREFIX:?}"/lib/pkgconfig/quiche.pc

# Build Nghttp2
ARG NGHTTP2_TREEISH=v1.41.0
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

# Build cURL
ARG CURL_TREEISH=curl-7_72_0
ARG CURL_REMOTE=https://github.com/curl/curl.git
RUN mkdir /tmp/curl/
WORKDIR /tmp/curl/
RUN git clone "${CURL_REMOTE:?}" ./
RUN git checkout "${CURL_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./buildconf
RUN ./lib/mk-ca-bundle.pl ./ca-bundle.crt
RUN ./configure --prefix="${TMPPREFIX:?}" --enable-static --disable-shared \
		--enable-alt-svc \
		--with-ca-bundle=./ca-bundle.crt \
		--with-zlib="${TMPPREFIX:?}" \
		--with-zstd="${TMPPREFIX:?}" \
		--with-ssl="${TMPPREFIX:?}" \
		--with-nghttp2="${TMPPREFIX:?}" \
		--with-quiche="${TMPPREFIX:?}"/lib/pkgconfig
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
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--http2-prior-knowledge", "--tlsv1.2", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--doh-url", "https://1.1.1.1/dns-query", "https://cloudflare.com"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--http3", "https://quic.tech:8443"]

##################################################
## "curl" stage
##################################################

FROM base AS curl

ENTRYPOINT ["/curl"]
CMD ["--help"]
