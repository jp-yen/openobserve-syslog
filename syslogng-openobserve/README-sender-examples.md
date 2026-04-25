# 送信元機器の設定例

以下は、syslog を送信する機器やアプリケーション側の設定例です。上の [README](README.md) にある「現行デフォルト設定」とは役割が異なります。

#### VyOS (514/tcp または 514/udp)

設定例:

```conf
config
set system syslog local facility all level 'info'
set system syslog local facility local7 level 'debug'
set system syslog remote <syslog server> facility all level 'info'
set system syslog remote <syslog server> facility local7 level 'debug'
set system syslog remote <syslog server> format include-timezone
set system syslog remote <syslog server> port 514
set system syslog remote <syslog server> protocol 'tcp'
commit ; save ; exit
```

**注意:**

* `set system syslog local ～` はローカルなので送信に影響ない
* `format octet-counted` は指定しない (改行区切りで送信)
* TCP 推奨 (`protocol 'tcp'`)、UDP の場合は `protocol 'udp'`

#### Cisco (3514/tcp または 3514/udp)

設定例:

```conf
configure terminal

! タイムゾーン設定
clock timezone JST 9 0

! タイムスタンプ設定 (ローカル・syslog 送信両方)
service timestamps debug datetime msec localtime show-timezone year
service timestamps log datetime msec localtime show-timezone year
service sequence-numbers
! ログにホスト名を含める
logging origin-id hostname

! syslog サーバー設定 (TCP 推奨)
logging host <syslog server> transport tcp port 3514 sequence-num-session

! または UDP を使う場合
! logging host <syslog server> transport udp port 3514

! ログレベル設定
logging trap informational

end
write memory
```

**補足:**

* コンソールポート (シリアル) にログが表示されるのを抑制したい場合は `no logging console` を追加
* ローカルバッファにもログを保存したい場合は以下を追加

  ```
  logging buffered 64000
  ```

#### CentreCOM (514/udp)

ポートが変更できないので 514/udp を使用。
syslog の送信元アドレスで振り分けを行う。

```conf
ntp server <ntp サーバ>     # NTPで時間同期をしていないと syslog は送信しない

log host <syslog server>
log host <syslog server> time utc-offset plus 9
log host <syslog server>level debugging facility local5
```

#### NEC IX UNIVERGE (4514/udp)

設定例:

```conf
syslog facility local2
syslog ip host <syslog server> port 4514
syslog timestamp datetime
syslog id hostname

syslog ip enable

! src addr や vrf を指定する場合
syslog vrf <vrf_NAME> ip source <src addr>
```

#### AlaxalA (7514/tcp, 7514/udp)

設定例:

OS-L2A Ver. 4.11 の例です。

```
clock timezone "JST" +9

logging host 172.31.220.57 tcp port 7514
logging facility local4
logging tcp trailer crlf
logging tcp connect delay 0
logging tcp reconnect delay 1
```

tcp 接続の時、接続・切断のログを表示 (切れている間はログが転送されていない可能性あり)

```
logging tcp notify open
logging tcp notify resume
```

#### YAMAHA RTX 新 (514/udp)

<details>
<summary>設定例を表示</summary>

対応機種の目安は次のとおりです。

RTX1300 は Rev.23.00.14 以降  
RTX1220 は Rev.15.04.07 以降  
RTX1210 は Rev.14.01.42 以降  
RTX830 は Rev.15.02.31 以降

設定例:

```conf
syslog format hostname text <syslog に表示されるホスト名>
syslog format type rfc5424
syslog host <syslog server>
syslog facility local6
syslog info on
syslog notice  off
syslog debug off

syslog local address <送信元アドレス>
```
</details>

#### YAMAHA RTX 旧 (514/udp)

<details>
<summary>設定例と注意点を表示</summary>

設定例:

```conf
syslog host <syslog server>
syslog facility local6
syslog info on
syslog notice  off
syslog debug off

syslog local address <送信元アドレス>
```

「＜PRI＞MSG」という、ファシリティーとシビアリティー、メッセージだけで構成されているため
この設定では syslog-ng は正しくフォーマットを処理できません。
RTX は送信先のポート番号を指定できないので
syslog-ng.conf で IP アドレスで処理を切り替える必要があります。

本リポジトリの `syslog-ng/conf/syslog-ng.conf` には既に設定が含まれています。
`filter f_old_yamaha` の IP アドレスをご自身の環境に合わせて変更してください。

```
# syslog-ng/conf/syslog-ng.conf 内の該当箇所
filter f_old_yamaha {
  host("^192.168.99.99$") or
  host("^192.168.99.222$");   # RTX のアドレス (正規表現で指定)
};
```

host(1.2.3.4) とか書くと、11.2.3.44 にもマッチするので注意。'^' と '$' はじゅーよー

**処理内容 (参考):**

```
log {
  source(s_rfc5424);
  filter(f_old_yamaha);
  # RTXのログはPROGRAMとMESSAGEに分割されてしまうため、ここで結合する
  rewrite {
    set("${PROGRAM} ${MESSAGE}", value("MESSAGE"));
    unset(value("PROGRAM"));
  };
  destination(d_openobserve);
  flags(final);
};
```
</details>

#### rsyslog

<details>
<summary>設定例を表示</summary>

**最小限の設定 (514/tcp - 推奨):**

```conf
# /etc/rsyslog.d/50-remote.conf
*.* @@<syslog server>:514
```

**UDP で送信する場合 (514/udp):**

```conf
*.* @<syslog server>:514
```

**RFC 3164 形式で送信する場合 (4514):**

```conf
*.* @@<syslog server>:4514  # TCP
*.* @<syslog server>:4514   # UDP
```

**設定の反映:**

```sh
sudo systemctl restart rsyslog
```

**注意:** `@@` は TCP、`@` は UDP を意味します
</details>

#### syslog-ng (514/tcp または 514/udp)

<details>
<summary>設定例を表示</summary>

**RFC 5424 形式で送信 (推奨):**

```conf
# リモート syslog-ng サーバーへの転送先定義
destination d_remote_syslog {
  syslog(
    "<syslog server>"
    transport("tcp")        # 推奨: tcp (信頼性重視)
    port(514)               # 標準 syslog ポート
    flags(syslog-protocol)  # RFC 5424 形式
    frac-digits(6)          # マイクロ秒精度
  );
};

# ログパイプライン
log {
  source(s_local);        # ローカルのログソース
  destination(d_remote_syslog);
};
```

**UDP で送信する場合 (軽量だが欠損の可能性あり):**

```conf
destination d_remote_syslog {
  syslog(
    "<syslog server>"
    transport("udp")
    port(514)
    flags(syslog-protocol)  # RFC 5424 形式
  );
};
```

**TLS 暗号化通信で送信する場合 (機密性重視):**

```conf
destination d_remote_syslog {
  syslog(
    "<syslog server>"
    transport("tls")
    port(6514)
    tls(
      ca-dir("/etc/ssl/certs")
      # または証明書を明示的に指定
      # ca-file("/path/to/ca.pem")
      # cert-file("/path/to/client-cert.pem")
      # key-file("/path/to/client-key.pem")
    )
    flags(syslog-protocol)
    frac-digits(6)
  );
};
```
</details>

#### Fluent Bit (Docker Compose)

<details>
<summary>設定例を表示</summary>

Docker Compose の `fluentd` ロギングドライバーを利用して、各コンテナのログを Fluent Bit 経由で構造化 JSON ログとして送信する設定例です（6514/tcp）。

**fluent-bit.conf:**
Fluent-bit は、ディスクにバッファリングする
```conf
[SERVICE]
    Flush           1
    storage.path    /var/log/flb-storage/
    storage.sync    normal
    storage.checksum off
    storage.backlog.mem_limit 5M

[INPUT]
    Name            forward
    Listen          0.0.0.0
    Port            24224
    storage.type    filesystem

[FILTER]
    Name modify
    Match *

[OUTPUT]
    Name        tcp
    Match       *
    Host        ${SYSLOG_HOST}
    Port        6514
    Format      json_lines
    Retry_Limit     no_limits
```

**compose.yaml:**

fluent-bit を起動し、他のコンテナのロギング先として指定します。

```yaml
x-logging-def: &logging-def
  driver: "fluentd"
  options:
    fluentd-address: "127.0.0.1:24224"
    fluentd-async: "true"
    tag: "{{.Name}}"
    labels: "system,program"    # 👈 抽出するラベルを指定

services:
  fluent-bit:
    image: fluent/fluent-bit:5.0.3
    restart: unless-stopped

  # --- 他のコンテナの例 ---
  app:
    image: your-app-image
    labels:
      system: web               # 👈 分類カテゴリ
      program: your-app         # 👈 program カラムの値になります
    depends_on:
      - fluent-bit              # 👈 fluent-bit を先に起動
    logging: *logging-def       # 👈 定義したログドライバへ送信
```
</details>