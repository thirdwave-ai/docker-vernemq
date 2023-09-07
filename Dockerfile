ARG vernemq_version=1.13.0
ARG twa_build_num=1

# Building based on the instructions from https://github.com/vernemq/vernemq#building-vernemq which
# simply tells us to "use Erlang/OTP 24-25".  Reviewing users in the space, it seems that 25.3.2.2 is
# a good choice that others are using for version 1.13.

FROM debian:bullseye-slim as builder
ARG vernemq_version
ARG twa_build_num

RUN apt-get update && \
    apt-get -y install bash build-essential procps openssl iproute2 curl jq libncurses5 libsctp1 libsnappy-dev \
    libssl-dev git pkg-config libncurses5-dev libwxgtk3.0-gtk3-0v5 libwxgtk3.0-gtk3-dev libwxgtk-webview3.0-gtk3-dev \
    unixodbc-dev && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/erlang && cd /tmp/erlang && \
    curl -JLO https://github.com/erlang/otp/releases/download/OTP-25.3.2.2/otp_src_25.3.2.2.tar.gz && \
    tar -zxf otp_src_25.3.2.2.tar.gz && rm otp_src_25.3.2.2.tar.gz

RUN cd /tmp/erlang/otp_src_25.3.2.2 && ./configure --prefix=/usr && make && make install

# Note: in order for the build to run correctly, it must be a git checkout.
RUN mkdir -p /artifacts /tmp/vernemq && \
    git clone --depth 1 --branch ${vernemq_version} https://github.com/vernemq/vernemq.git /tmp/vernemq && \
    cd /tmp/vernemq && \
    make rel && cd _build/default/rel/vernemq && \
    tar -zcf /tmp/vernemq_bin_${vernemq_version}_twa${twa_build_num}.tar.gz *

VOLUME ["/artifacts"]

CMD cp /tmp/vernemq_bin_${vernemq_version}_twa${twa_build_num}.tar.gz /artifacts



FROM debian:bullseye-slim
ARG vernemq_version
ARG twa_build_num

RUN apt-get update && \
    apt-get -y install bash procps openssl iproute2 curl jq libsnappy-dev net-tools nano && \
    rm -rf /var/lib/apt/lists/* && \
    addgroup --gid 10000 vernemq && \
    adduser --uid 10000 --system --ingroup vernemq --home /vernemq --disabled-password vernemq

WORKDIR /vernemq

# Defaults
ENV DOCKER_VERNEMQ_KUBERNETES_LABEL_SELECTOR="app=vernemq" \
    DOCKER_VERNEMQ_LOG__CONSOLE=console \
    PATH="/vernemq/bin:$PATH" \
    VERNEMQ_VERSION=${vernemq_version}
COPY --chown=10000:10000 bin/vernemq.sh /usr/sbin/start_vernemq
COPY --chown=10000:10000 files/vm.args /vernemq/etc/vm.args

# Grab the twa binary.
COPY --from=builder /tmp/vernemq_bin_${vernemq_version}_twa${twa_build_num}.tar.gz /tmp/vernemq-$VERNEMQ_VERSION.bullseye.tar.gz

RUN tar -xzvf /tmp/vernemq-$VERNEMQ_VERSION.bullseye.tar.gz && \
    rm /tmp/vernemq-$VERNEMQ_VERSION.bullseye.tar.gz && \
    chown -R 10000:10000 /vernemq && \
    ln -s /vernemq/etc /etc/vernemq && \
    ln -s /vernemq/data /var/lib/vernemq && \
    ln -s /vernemq/log /var/log/vernemq

# Ports
# 1883  MQTT
# 8883  MQTT/SSL
# 8080  MQTT WebSockets
# 44053 VerneMQ Message Distribution
# 4369  EPMD - Erlang Port Mapper Daemon
# 8888  Health, API, Prometheus Metrics
# 9100 9101 9102 9103 9104 9105 9106 9107 9108 9109  Specific Distributed Erlang Port Range

EXPOSE 1883 8883 8080 44053 4369 8888 \
       9100 9101 9102 9103 9104 9105 9106 9107 9108 9109


VOLUME ["/vernemq/log", "/vernemq/data", "/vernemq/etc"]

HEALTHCHECK CMD vernemq ping | grep -q pong

USER vernemq

CMD ["start_vernemq"]
