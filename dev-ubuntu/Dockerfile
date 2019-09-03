# from https://github.com/h2o/h2o/blob/master/misc/docker-ci/Dockerfile
FROM ubuntu:18.04

RUN apt-get --yes update

# huge packages go first (for better cacheability)
RUN apt-get install --yes emacs
RUN apt-get install --yes bison ruby-dev
RUN apt-get install --yes php-cgi

# tools for building and testing
RUN apt-get install --yes apache2-utils cmake cmake-data git memcached netcat-openbsd nghttp2-client redis-server wget sudo
RUN apt-get install --yes libev-dev libc-ares-dev libnghttp2-dev libssl-dev libuv1-dev zlib1g-dev

# clang-4.0 for fuzzing
RUN apt-get install -y clang-4.0
ENV PATH=/usr/lib/llvm-4.0/bin:$PATH

# curl with http2 support
RUN wget --no-verbose -O - https://curl.haxx.se/download/curl-7.57.0.tar.gz | tar xzf -
RUN (cd curl-7.57.0 && ./configure --prefix=/usr/local --with-nghttp2 --disable-shared && make && sudo make install)

ARG OPENSSL_URL="https://www.openssl.org/source/"

# openssl 1.1.1
ARG OPENSSL_VERSION="1.1.1c"
ARG OPENSSL_SHA1="71b830a077276cbeccc994369538617a21bee808"
RUN curl -O ${OPENSSL_URL}openssl-${OPENSSL_VERSION}.tar.gz
RUN (echo "${OPENSSL_SHA1} openssl-${OPENSSL_VERSION}.tar.gz" | sha1sum -c - && tar xf openssl-${OPENSSL_VERSION}.tar.gz)
RUN (cd openssl-${OPENSSL_VERSION} && \
	./config --prefix=/opt/openssl-1.1.1 --openssldir=/opt/openssl-1.1.1 shared enable-ssl3 enable-ssl3-method enable-weak-ssl-ciphers && \
	make -j $(nproc) && make -j install_sw install_ssldirs)

# use dumb-init
RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.1/dumb-init_1.2.1_amd64 \
 && chmod +x /usr/local/bin/dumb-init

#create user
RUN useradd --create-home cwyang
RUN echo 'cwyang ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
WORKDIR /home/cwyang
USER cwyang

ENTRYPOINT ["/usr/local/bin/dumb-init"]
