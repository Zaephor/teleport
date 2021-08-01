FROM lsiobase/ubuntu:bionic
EXPOSE 3022 3023 3024 3025 3026 3080
VOLUME /config
COPY s6/ /
ARG RELEASE
RUN \
    curl -s -k -L  https://github.com/Zaephor/teleport/releases/download/${RELEASE}/teleport-${RELEASE}-$(uname -s | tr '[A-Z]' '[a-z]')-$(dpkg --print-architecture).tar.gz -o /tmp/teleport.tar.gz && \
    tar -xvf /tmp/teleport.tar.gz -C /usr/local/bin --strip-components=1 teleport/teleport teleport/tctl teleport/tsh && \
    tar -xvf /tmp/teleport.tar.gz -C / --strip-components=1 teleport/VERSION && \
    rm /tmp/teleport.tar.gz
