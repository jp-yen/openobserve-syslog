# 送信元機器の設定例

以下は、syslog を送信する機器やアプリケーション側の設定例です。上の [README](README.md) にある「現行デフォルト設定」とは役割が異なります。

#### VyOS (514/tcp または 514/udp)

設定例:

```conf
config
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
! シーケンス番号を有効化 (logの抜け、順序のチェック)
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
# NTPで時間同期をしていないと syslog は送信しない
ntp server <ntp サーバ>

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

tcp 接続の時、接続・切断のログを表示したい場合 (切れている間はログが転送されていない可能性あり)

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

旧ファームウェアの RTX は「`<PRI> [TAG] MSG`」というヘッダー（ホスト名・時刻なし）で送信されます。

本システムの Fluent Bit パーサー（`syslog_standard.lua`）がこれを自動検出し、以下のように自動補正して登録します：
- **`host`**: 送信元 IP アドレスを自動設定
- **`program`**: 先頭の `[TAG]`（例: `[NAT]`, `[IP]`）を抽出して設定
- **`message`**: `[TAG]` を除いた本文を設定
- **`_timestamp`**: 受信時刻（高精度）を付与
</details>

#### rsyslog (514/tcp 推奨)

<details>
<summary>設定例を表示</summary>

rsyslog から最も多くの情報（マイクロ秒精度タイムスタンプ、タイムゾーン、PID、構造化データ等）を欠落なく送信するには、**RFC 5424 形式（IETF 形式）かつ TCP（514/tcp）** を使用するのが最も推奨されます。

**推奨設定 1: rsyslog v8+ アクション構文（最も推奨）:**

`/etc/rsyslog.d/50-remote.conf` などの設定ファイルに記述します。

```conf
# /etc/rsyslog.d/50-remote.conf
# RFC 5424 形式（高精度タイムスタンプ・PID・タイムゾーン付き）で TCP 送信
action(
    type="omfwd"
    target="<syslog server>"
    port="514"
    protocol="tcp"
    template="RSYSLOG_SyslogProtocol23Format"
)
```

**推奨設定 2: 1行レガシー構文:**

```conf
# /etc/rsyslog.d/50-remote.conf
*.* @@<syslog server>:514;RSYSLOG_SyslogProtocol23Format
```

**最小限のデフォルト設定 (514/tcp):**

```conf
*.* @@<syslog server>:514
```

**UDP で送信する場合 (514/udp):**

```conf
# RFC 5424 形式 (UDP)
*.* @<syslog server>:514;RSYSLOG_SyslogProtocol23Format

# デフォルト形式 (UDP)
*.* @<syslog server>:514
```

**RFC 3164 形式専用ポートで送信する場合 (4514):**

```conf
*.* @@<syslog server>:4514  # TCP
*.* @<syslog server>:4514   # UDP
```

**設定の確認と反映:**

```sh
# 構文チェック
sudo rsyslogd -N1

# 反映
sudo systemctl restart rsyslog
```

**注意:** `@@` は TCP、`@` は UDP を意味します。
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