# from https://github.com/h2o/h2o/blob/master/misc/docker-ci/Dockerfile
FROM ubuntu:18.04

RUN apt-get --yes update

# tzdata
RUN ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
ENV DEBIAN_FRONTEND=noninteractive

# huge packages go first (for better cacheability)
RUN apt-get install --yes tzdata emacs-nox vim-nox

# tools for building and testing
RUN apt-get install --yes perl gdb openssl ssh wget curl sudo telnet
RUN apt-get install --yes iptables netcat-openbsd net-tools binutils dnsutils iputils-ping

# use dumb-init
RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.1/dumb-init_1.2.1_amd64 \
 && chmod +x /usr/local/bin/dumb-init

#create user
RUN useradd --create-home cwyang
RUN echo 'cwyang ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
WORKDIR /home/cwyang
USER cwyang

ENTRYPOINT ["/usr/local/bin/dumb-init"]
CMD ["/bin/bash"]
