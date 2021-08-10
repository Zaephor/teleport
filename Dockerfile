FROM lsiobase/ubuntu:focal
EXPOSE 3022 3023 3024 3025 3026 3080
VOLUME /config
COPY s6/ /
ARG RELEASE
RUN \
    curl -s -k -L  https://github.com/Zaephor/teleport/releases/download/${RELEASE}/teleport-${RELEASE}-linux-$(dpkg --print-architecture).tar.gz | \
    tar -zxvf - -C /usr/local/bin --strip-components=1 teleport/teleport teleport/tctl teleport/tsh teleport/VERSION && \
    mv /usr/local/bin/VERSION /
