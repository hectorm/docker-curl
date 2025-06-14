m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/alpine:3]], [[FROM docker.io/alpine:3]]) AS build

# Install system packages
RUN apk add --no-cache \
		autoconf \
		automake \
		build-base \
		coreutils \
		curl \
		findutils \
		gengetopt \
		gettext-dev \
		git \
		gperf \
		groff \
		gtk-doc \
		libtool \
		linux-headers \
		make \
		perl \
		pkgconf \
		texinfo

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
ARG ZLIB_TREEISH=v1.3.1
ARG ZLIB_REMOTE=https://github.com/madler/zlib.git
RUN mkdir /tmp/zlib/
WORKDIR /tmp/zlib/
RUN git clone "${ZLIB_REMOTE:?}" ./
RUN git checkout "${ZLIB_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--static
RUN make -j"$(nproc)"
RUN make install

# Build zstd
ARG ZSTD_TREEISH=v1.5.7
ARG ZSTD_REMOTE=https://github.com/facebook/zstd.git
RUN mkdir /tmp/zstd/
WORKDIR /tmp/zstd/
RUN git clone "${ZSTD_REMOTE:?}" ./
RUN git checkout "${ZSTD_TREEISH:?}"
RUN git submodule update --init --recursive
WORKDIR /tmp/zstd/lib/
RUN make libzstd.a-release -j"$(nproc)"
RUN make install-pc install-static install-includes PREFIX="${TMPPREFIX:?}"

# Build c-ares
ARG C_ARES_TREEISH=v1.34.5
ARG C_ARES_REMOTE=https://github.com/c-ares/c-ares.git
RUN mkdir /tmp/c-ares/
WORKDIR /tmp/c-ares/
RUN git clone "${C_ARES_REMOTE:?}" ./
RUN git checkout "${C_ARES_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared
RUN make -j"$(nproc)"
RUN make install

# Build wolfSSL
ARG WOLFSSL_TREEISH=v5.8.0-stable
ARG WOLFSSL_REMOTE=https://github.com/wolfSSL/wolfssl.git
RUN mkdir /tmp/wolfssl/
WORKDIR /tmp/wolfssl/
RUN git clone "${WOLFSSL_REMOTE:?}" ./
RUN git checkout "${WOLFSSL_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./autogen.sh
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared \
		--enable-reproducible-build \
		--enable-all
RUN make -j"$(nproc)"
RUN make install

# Build nghttp2
ARG NGHTTP2_TREEISH=v1.65.0
ARG NGHTTP2_REMOTE=https://github.com/nghttp2/nghttp2.git
RUN mkdir /tmp/nghttp2/
WORKDIR /tmp/nghttp2/
RUN git clone "${NGHTTP2_REMOTE:?}" ./
RUN git checkout "${NGHTTP2_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared \
		--enable-lib-only \
		--with-wolfssl
RUN make -j"$(nproc)"
RUN make install

# Build nghttp3
ARG NGHTTP3_TREEISH=v1.10.1
ARG NGHTTP3_REMOTE=https://github.com/ngtcp2/nghttp3.git
RUN mkdir /tmp/nghttp3/
WORKDIR /tmp/nghttp3/
RUN git clone "${NGHTTP3_REMOTE:?}" ./
RUN git checkout "${NGHTTP3_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared \
		--enable-lib-only
RUN make -j"$(nproc)"
RUN make install

# Build ngtcp2
ARG NGTCP2_TREEISH=v1.13.0
ARG NGTCP2_REMOTE=https://github.com/ngtcp2/ngtcp2.git
RUN mkdir /tmp/ngtcp2/
WORKDIR /tmp/ngtcp2/
RUN git clone "${NGTCP2_REMOTE:?}" ./
RUN git checkout "${NGTCP2_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared \
		--enable-lib-only \
		--with-wolfssl
RUN make -j"$(nproc)"
RUN make install

# Build wolfSSH
ARG WOLFSSH_TREEISH=v1.4.19-stable
ARG WOLFSSH_REMOTE=https://github.com/wolfSSL/wolfssh.git
RUN mkdir /tmp/wolfssh/
WORKDIR /tmp/wolfssh/
RUN git clone "${WOLFSSH_REMOTE:?}" ./
RUN git checkout "${WOLFSSH_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared \
		--enable-sftp \
		--with-wolfssl="${TMPPREFIX:?}"
RUN make -j"$(nproc)"
RUN make install

# Build libunistring
ARG LIBUNISTRING_TREEISH=v1.3
ARG LIBUNISTRING_REMOTE=https://git.savannah.gnu.org/git/libunistring.git
RUN mkdir /tmp/libunistring/
WORKDIR /tmp/libunistring/
RUN git clone "${LIBUNISTRING_REMOTE:?}" ./
RUN git checkout "${LIBUNISTRING_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./autopull.sh && ./autogen.sh
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared
RUN make -j"$(nproc)"
RUN make install

# Build libidn2
ARG LIBIDN2_TREEISH=v2.3.7
ARG LIBIDN2_REMOTE=https://gitlab.com/libidn/libidn2.git
RUN mkdir /tmp/libidn2/
WORKDIR /tmp/libidn2/
RUN git clone "${LIBIDN2_REMOTE:?}" ./
RUN git checkout "${LIBIDN2_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./bootstrap --skip-po
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared \
		--disable-doc
RUN make -j"$(nproc)"
RUN make install

# Build libpsl
ARG LIBPSL_TREEISH=0.21.5
ARG LIBPSL_REMOTE=https://github.com/rockdaboot/libpsl.git
RUN mkdir /tmp/libpsl/
WORKDIR /tmp/libpsl/
RUN git clone "${LIBPSL_REMOTE:?}" ./
RUN git checkout "${LIBPSL_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./autogen.sh
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared \
		--disable-man
RUN make -j"$(nproc)"
RUN make install

# Build OpenLDAP
ARG OPENLDAP_TREEISH=OPENLDAP_REL_ENG_2_6_9
ARG OPENLDAP_REMOTE=https://git.openldap.org/openldap/openldap.git
RUN mkdir /tmp/openldap/
WORKDIR /tmp/openldap/
RUN git clone "${OPENLDAP_REMOTE:?}" ./
RUN git checkout "${OPENLDAP_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared
RUN make -j"$(nproc)"
RUN make install

# Build cURL
ARG CURL_TREEISH=curl-8_12_0
ARG CURL_REMOTE=https://github.com/curl/curl.git
RUN mkdir /tmp/curl/
WORKDIR /tmp/curl/
RUN git clone "${CURL_REMOTE:?}" ./
RUN git checkout "${CURL_TREEISH:?}"
RUN git submodule update --init --recursive
RUN autoreconf -fi
RUN ./scripts/mk-ca-bundle.pl ./ca-bundle.crt
RUN ./configure \
		--prefix="${TMPPREFIX:?}" \
		--enable-static \
		--disable-shared \
		--disable-docs \
		--enable-ares \
		--enable-threaded-resolver \
		--enable-ech \
		--enable-websockets \
		--enable-ldap \
		--enable-ldaps \
		--with-ca-bundle=./ca-bundle.crt \
		--with-zlib="${TMPPREFIX:?}" \
		--with-zstd="${TMPPREFIX:?}" \
		--with-wolfssl="${TMPPREFIX:?}" \
		--with-nghttp2="${TMPPREFIX:?}" \
		--with-nghttp3="${TMPPREFIX:?}" \
		--with-ngtcp2="${TMPPREFIX:?}" \
		--with-wolfssh="${TMPPREFIX:?}" \
		--with-libidn2="${TMPPREFIX:?}" \
		--with-libpsl="${TMPPREFIX:?}" \
		LDFLAGS="--static -L${TMPPREFIX:?}/lib ${LDFLAGS-}" \
		CPPFLAGS="-I${TMPPREFIX:?}/include ${CPPFLAGS-}" \
		LIBS='-lidn2 -lunistring'
RUN make -j"$(nproc)"
RUN make install-strip

##################################################
## "test" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/hectorm/scratch:CROSS_ARCH]], [[FROM scratch]]) AS test

COPY --from=build /tmp/usr/bin/curl /tmp/curl/ca-bundle.crt /

RUN ["/curl", "--version"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--url", "https://cloudflare.com", "--tlsv1.3"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--url", "https://cloudflare.com", "--http2-prior-knowledge"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--url", "https://cloudflare.com", "--http3-only"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--url", "https://cloudflare.com", "--dns-servers", "1.1.1.1,1.0.0.1"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--url", "https://cloudflare.com", "--doh-url", "https://one.one.one.one/dns-query"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--url", "https://defo.ie",        "--doh-url", "https://one.one.one.one/dns-query", "--ech", "true"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--url", "https://はじめよう.みんな"]
RUN ["/curl", "--verbose", "--silent", "--output", "/dev/null", "--url", "ldaps://ldap-eu.apache.org"]

##################################################
## "main" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/hectorm/scratch:CROSS_ARCH]], [[FROM scratch]]) AS main

COPY --from=test /curl /ca-bundle.crt /

ENTRYPOINT ["/curl"]
CMD ["--help"]
