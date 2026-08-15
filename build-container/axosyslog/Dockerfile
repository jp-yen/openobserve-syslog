# AxoSyslog (Cloud-Ready Syslog-ng distribution)
# IPv6 / JSON / HTTP / Python / SNMP / SQL［MySQL, PostgreSQL, SQLite］/ AMQP / GeoIP2 / SSL を有効化 (Linux Caps/Java は無効化)

ARG DEBIAN_RELEASE=13.5
ARG AXOSYSLOG_VERSION=4.26.0

# ---- ビルドステージ ---------------------------------------------------------
FROM debian:${DEBIAN_RELEASE} AS builder

ENV DEBIAN_FRONTEND=noninteractive
ARG AXOSYSLOG_VERSION

RUN apt-get update && apt-get install -y \
  git ca-certificates \
  build-essential autoconf autoconf-archive automake libtool pkg-config \
  flex bison gperf \
  libglib2.0-dev libcurl4-openssl-dev \
  libjson-c-dev libsystemd-dev liblua5.4-dev python3 python3-dev python3-venv \
  libsnmp-dev libesmtp-dev \
  libdbi-dev libdbd-mysql libdbd-pgsql libdbd-sqlite3 libsqlite3-dev \
  libpcre2-dev \
  libperl-dev perl librabbitmq-dev libssl-dev libmaxminddb-dev \
  && rm -rf /var/lib/apt/lists/*

# AxoSyslog のソースコードを取得
WORKDIR /src
RUN git clone --depth 1 --filter=blob:none -b axosyslog-${AXOSYSLOG_VERSION} https://github.com/axoflow/axosyslog.git .

ENV CFLAGS="-pipe -O2"
ENV CXXFLAGS="-pipe -O2"

RUN ./autogen.sh

# ビルド
RUN ./configure \
  --prefix=/usr/local \
  --localstatedir=/var/lib/syslog-ng \
  --with-pidfile-dir=/var/lib/syslog-ng \
  --enable-ipv6 \
  --enable-json \
  --enable-sql \
  --enable-afsnmp \
  --enable-amqp \
  --enable-dynamic-linking \
  --enable-geoip2 \
  --enable-ssl \
  --with-openssl \
  --disable-linux-caps \
  --disable-tcp-wrapper \
  --disable-java

# 【修正】syslog-ng-ctl のデフォルトソケットパスを強制的に書き換え & ビルド実行
RUN sed -i 's|#define PATH_CONTROL_SOCKET.*|#define PATH_CONTROL_SOCKET "/var/lib/syslog-ng/syslog-ng.ctl"|' lib/syslog-ng.h && \
    make -j"$(nproc)" && make install DESTDIR=/install

# ---- 実行ステージ ---------------------------------------------------------
FROM debian:${DEBIAN_RELEASE}-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PUID=65534 PGID=65534

RUN apt-get update && apt-get install -y \
  ca-certificates \
  gosu \
  libglib2.0-0 libcurl4 \
  libjson-c5 libsystemd0 liblua5.4-0 python3 libpython3.13 python3-venv \
  libsnmp40 libesmtp6 \
  libdbi1 libdbd-mysql libdbd-pgsql libdbd-sqlite3 libsqlite3-0 \
  libpcre2-8-0 \
  perl librabbitmq4 libmaxminddb0 libssl3 \
  tzdata \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# ビルド成果物・スクリプト・デフォルト設定のコピー
COPY --from=builder /install/ /
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY syslog-ng.conf /usr/local/share/syslog-ng/default.conf

# ディレクトリ作成・権限付与・ライブラリ読み込みを一括実行
RUN ldconfig && \
    mkdir -p /etc/syslog-ng /var/lib/syslog-ng /var/log/syslog-ng /config && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 514/tcp 514/udp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
