FROM alpine:3.9
LABEL maintainer="Rafael Pirolla <spam@pirolla.com>"

# This is the release of Nomad to pull in.
ENV NOMAD_VERSION=0.9.3
ENV GLIBC_VERSION "2.25-r0"

# This is the location of the releases.
ENV HASHICORP_RELEASES=https://releases.hashicorp.com

# Create a hashicorp user and group first so the IDs get set the same way, even as
# the rest of this may change over time.
RUN addgroup nomad && \
    adduser -S -G nomad nomad

RUN set -eux && \
  apk add --no-cache ca-certificates curl dumb-init gnupg libcap openssl su-exec iputils jq && \
  gpg --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 91A6E7F85D05C65630BEF18951852D87348FFC4C && \
  mkdir /tmp/build && \
  cd /tmp/build && \
  apkArch="$(apk --print-arch)" && \
  case "${apkArch}" in \
      aarch64) alpineArch='arm64' ;; \
      armhf) alpineArch='arm' ;; \
      x86) alpineArch='386' ;; \
      x86_64) alpineArch='amd64' ;; \
      *) echo >&2 "error: unsupported architecture: ${apkArch} (see ${HASHICORP_RELEASES}/nomad/${NOMAD_VERSION}/)" && exit 1 ;; \
  esac && \
  wget https://github.com/andyshinn/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk && \
  apk add --allow-untrusted /tmp/build/glibc-${GLIBC_VERSION}.apk && \
  wget ${HASHICORP_RELEASES}/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_${alpineArch}.zip && \
  wget ${HASHICORP_RELEASES}/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_SHA256SUMS && \
  wget ${HASHICORP_RELEASES}/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_SHA256SUMS.sig && \
  gpg --batch --verify nomad_${NOMAD_VERSION}_SHA256SUMS.sig nomad_${NOMAD_VERSION}_SHA256SUMS && \
  grep nomad_${NOMAD_VERSION}_linux_${alpineArch}.zip nomad_${NOMAD_VERSION}_SHA256SUMS | sha256sum -c && \
  unzip -d /bin nomad_${NOMAD_VERSION}_linux_${alpineArch}.zip && \
  cd /tmp && \
  rm -rf /tmp/build && \
  rm -rf /tmp/build/glibc-${GLIBC_VERSION}.apk && \
  apk del gnupg openssl && \
  rm -rf /root/.gnupg && \
# tiny smoke test to ensure the binary we downloaded runs
  nomad version
  
RUN set -x \
  && apk --update add --no-cache ca-certificates openssl \
  && update-ca-certificates

# The /nomad/data dir is used by Nomad to store state. The agent will be started
# with /nomad/config as the configuration directory so you can add additional
# config files in that location.
RUN mkdir -p /nomad/data && \
    mkdir -p /nomad/config && \
    chown -R nomad:nomad /nomad

# set up nsswitch.conf for Go's "netgo" implementation which is used by Consul,
# otherwise DNS supercedes the container's hosts file, which we don't want.
RUN test -e /etc/nsswitch.conf || echo 'hosts: files dns' > /etc/nsswitch.conf

# Expose the nomad data directory as a volume since there's mutable state in there.
VOLUME /nomad/data

# NOMAD PORTS
EXPOSE 4646 4647 4648 4648/udp

# Nomad doesn't need root privileges so we run it as the nomad user from the
# entry point script. The entry point script also uses dumb-init as the top-level
# process to reap any zombie processes created by Nomad sub-processes.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

# By default you'll get an insecure single-node development server that stores
# everything in RAM, exposes a web UI and HTTP endpoints, and bootstraps itself.
# Don't use this configuration for production.
CMD ["agent", "-dev"]
