# syslog-ng
# IPv6 / JSON / HTTP / Python / Lua / Linux Caps / SNMP / SMTP / SQL［MySQL & PostgreSQL］を有効化

ARG DEBIAN_RELEASE=bookworm
ARG SYSLOG_NG_version=4.10.2

# ---- ビルドステージ ---------------------------------------------------------
FROM debian:${DEBIAN_RELEASE} AS builder

ENV DEBIAN_FRONTEND=noninteractive
ARG SYSLOG_NG_version

RUN apt-get update && apt-get install -y \
  git ca-certificates \
  build-essential autoconf autoconf-archive automake libtool pkg-config \
  flex bison gperf \
  libglib2.0-dev libevent-dev libcurl4-openssl-dev \
  libjson-c-dev libsystemd-dev liblua5.4-dev python3-dev python3-venv \
  libsnmp-dev libesmtp-dev \
  libdbi-dev libdbd-mysql libdbd-pgsql \
  libpcre2-dev \
  && rm -rf /var/lib/apt/lists/*

# syslog-ng のソースコードを取得
WORKDIR /src
RUN git clone --depth 1 --filter=blob:none -b syslog-ng-${SYSLOG_NG_version} https://github.com/syslog-ng/syslog-ng.git .

# 指定された機能で syslog-ng をビルド
RUN ./autogen.sh
# 最適化、必要であれば -march=native も
ENV CFLAGS="-pipe -O2"
ENV CXXFLAGS="-pipe -O2"

# ビルド
RUN ./configure \
  --prefix=/usr/local \
  --localstatedir=/var/lib/syslog-ng \
  --with-pidfile-dir=/var/lib/syslog-ng \
  --enable-ipv6 \
  --enable-json \
  --enable-http \
  --enable-python \
  --enable-lua \
  --disable-linux-caps \
  --enable-sql \
  --enable-snmp \
  --enable-smtp \
  --disable-java

# 【修正】syslog-ng-ctl のデフォルトソケットパスを強制的に書き換え
RUN sed -i 's|#define PATH_CONTROL_SOCKET.*|#define PATH_CONTROL_SOCKET "/var/lib/syslog-ng/syslog-ng.ctl"|' lib/syslog-ng.h
RUN make -j"$(nproc)" && make install DESTDIR=/install

# ---- 実行ステージ ---------------------------------------------------------
FROM debian:${DEBIAN_RELEASE}-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
  ca-certificates \
  gosu \
  libglib2.0-0 libevent-2.1-7 libcurl4 \
  libjson-c5 libsystemd0 liblua5.4-0 python3-minimal libpython3.11 \
  libsnmp40 libesmtp6 \
  libdbi1 libdbd-mysql libdbd-pgsql \
  libpcre2-8-0 \
  tzdata \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# ビルド成果物をコピー
COPY --from=builder /install/ /
RUN ldconfig
ENV LD_LIBRARY_PATH=/usr/local/lib
# RUN setcap 'cap_net_bind_service=+ep' /usr/local/sbin/syslog-ng # disable-linux-caps

# ベースディレクトリ
RUN mkdir -p /etc/syslog-ng /var/lib/syslog-ng /var/log/syslog-ng /config

# デフォルトの PUID/PGID を定義（上書き可能）
ENV PUID=65534 PGID=65534

# entrypoint スクリプトを追加
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# デフォルト設定を保存（起動時に /config が空の場合に使用）
COPY syslog-ng.conf /usr/local/share/syslog-ng/default.conf

EXPOSE 514/tcp 514/udp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
