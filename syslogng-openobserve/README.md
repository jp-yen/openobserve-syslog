# OpenObserve と syslog-ng による Syslog サーバー

このプロジェクトは、`docker compose` を使用して `syslog-ng` と `OpenObserve` を連携させた syslog サーバーを構築するためのものです。`syslog-ng` が受信したログを `OpenObserve` に転送し、ログの集約、検索、可視化を行います。

## 概要

*   **syslog-ng**: ネットワークから syslog を受け付け OpenObserve に転送します
*   **OpenObserve**: 受信した syslog をブラウザ上で表示します。DB 上で圧縮されるため、受信するログが多い環境でも安心です。

## 起動方法

`docker-compose.yml` があるディレクトリで以下のコマンドを実行します。

```sh
make up
```

## ログの見方

受信したログを表示するには http://<サーバーのIPアドレス>:5080 へアクセス、
    ユーザ名 : root@root.root
    パスワード : root
でログインします。(ユーザー名とパスワードは openobserve/.env で指定)
左側に並んでいる中から「ストリーム」をクリック。「syslog-ng」の行の🔍をクリックするとログが表示されます。


## 設定詳細

### OpenObserve

*   **公式ドキュメント:** [OpenObserve Self-hosted Installation](https://openobserve.ai/docs/guide/quickstart/#self-hosted-installation)
*   **イメージ:** `public.ecr.aws/zinclabs/openobserve:latest`
    *   注意: `simd` タグ付きのイメージ (例: `public.ecr.aws/zinclabs/openobserve:latest-simd`) は AVX512 命令セットに対応した CPU (主に Xeon など) が必要です。
*   **コンテナ名:** `OpenObserve`
*   **ポートマッピング:**
    *   `5080:5080` (OpenObserve UI および API)
*   **ボリュームマッピング:**
    *   `./openobserve/data/`: `/data/` (OpenObserve のデータ永続化用)
*   **環境変数:**
    *   `TZ=Asia/Tokyo` (タイムゾーン設定)
*   **env_file:**
    *   `./openobserve/.env` (追加の環境変数を定義可能)
*   **再起動ポリシー:** `unless-stopped`

### syslog-ng

*   **公式ドキュメント:** [linuxserver/syslog-ng](https://docs.linuxserver.io/images/docker-syslog-ng/)
*   **イメージ:** `lscr.io/linuxserver/syslog-ng:latest`
    *   `syslog-ng_Dockerfile` は試しに書いただけで利用していません
*   **コンテナ名:** `syslog-ng`
*   **ポート:**
    *    `514/tcp,udp`	# 標準的な RFC 5424 形式のログを受ける (改行区切り)
    *   `2514/tcp`	    # RFC 5424 octet-counted 形式のログを受ける
    *   `3514/tcp,udp`	# Cisco機器からのログを受ける
    *   `4514/tcp,udp`	# 古い RFC 3164 形式のログを受ける
    *   `5514/tcp,udp`	# Fortigate 用
    *   `6514/tcp,udp`	# JSON 構造化ログを受け付ける
*   **ボリュームマッピング:**
    *   `./syslog-ng/conf/`: `/config/` 設定ファイル
    *   `./syslog-ng/buffer/`: `/buffer/` ログのバッファリング用
*   **環境変数:**
    *   `PUID=1000` (プロセスのユーザーID)
    *   `PGID=1000` (プロセスのグループID)
    *   `TZ=Asia/Tokyo` (タイムゾーン設定)
*   **再起動ポリシー:** `unless-stopped`

## 使い方

1.  **設定ファイルの準備:**
    *   `./openobserve/.env`: 必要に応じて OpenObserve の設定を記述します。
    *   `./syslog-ng/conf/syslog-ng.conf`: `syslog-ng` の設定ファイルです。ログのフィルタリングや OpenObserve への転送設定などを記述します。
        (設定例は `syslog-ng` のドキュメントや OpenObserve の連携ガイドを参照してください)

2.  **サービスの起動:**
    ```sh
    make up
    ```

3.  **OpenObserve へのアクセス:**
    Web ブラウザで `http://<サーバーのIPアドレス>:5080` にアクセスします。

4.  **ログの送信:**
    各機器やアプリケーションの Syslog 設定で、このサーバーの IP アドレスと以下のポートを指定します。

    | ポート | プロトコル | 用途 |
    |--------|------------|------|
    | 514 | TCP/UDP | 標準的な RFC 5424 形式 (推奨) |
    | 2514 | TCP | RFC 5424 octet-counted 形式 |
    | 3514 | TCP/UDP | Cisco 機器専用 |
    | 4514 | TCP/UDP | 古い RFC 3164 形式 |
    | 5514 | TCP/UDP | Fortigate 専用 |
    | 6514 | TCP/UDP | JSON 構造化ログ |

5.  **ログの確認:**
    OpenObserve の UI で収集されたログを検索・確認できます。
    `docker compose logs syslog-ng` や `docker compose logs OpenObserve` で各コンテナのログも確認できます。

6.  **サービスの削除:**
    ```sh
    make down
    ```

## Makefile による操作

`Makefile` を使用して、一般的な操作を簡単に行うことができます。

*   **コンテナの起動:**
    ```sh
    make up
    ```
*   **コンテナの停止、削除:**
    ```sh
    make down
    ```
*   **コンテナの再起動とバージョンアップ:**
    ```sh
    make restart
    ```
    このコマンドはコンテナを再作成します。`docker-compose.yml` でイメージのタグが `:latest` になっている場合や、イメージのバージョン指定を更新した場合、このコマンドで新しいバージョンのコンテナが起動します。(local に :latest のイメージが存在する場合、新たに取得しない場合があります)
*   **起動状況の確認:**
    ```sh
    make ps
    ```
*   **データとログの削除 (初期化):**
    ```sh
    make clean
    ```
    注意: このコマンドは `OpenObserve` の永続化データと `syslog-ng` の一部ログファイルを削除します。実行には `root` 権限が必要な場合があります。
*   **イメージの更新と再起動 (バージョンアップ):**
    ```sh
    make update-image
    ```
    このコマンドは、コンテナを停止し、`docker-compose.yml` で定義されたサービスに関連する全てのイメージを削除した後、新しいイメージでコンテナを再起動します。データボリュームは保持されるため、ログは削除されません。
*   **syslog-ng 設定ファイルのチェック:**
    ```sh
    make conf_check
    ```
*   **テスト用 syslog メッセージの送信:**
    ```sh
    make flood_syslog
    ```
    または
    ```sh
    make syslog_s
    ```
    これらのコマンドはテスト目的でダミーの syslog メッセージを送信します。実行には `root` 権限が必要な場合があります。

各コマンドの詳細や実行に必要な権限については、`Makefile` を参照してください。

## ログのダウンロード

`download_syslog.py` スクリプトを使用して、OpenObserve に蓄積されたログを CSV ファイルとしてダウンロードできます。

### 依存関係のインストール

スクリプトを実行する前に、必要な Python パッケージをインストールしてください。

```sh
pip3 install requests tqdm
```

### 使用方法

1.  **設定の変更:**
    スクリプト内の設定項目を環境に合わせて変更してください。
    ```python
    API_URL = "http://<サーバーのIPアドレス>:5080"    # OpenObserve の URL
    USERNAME = "root@root.root"              # ユーザー名
    PASSWORD = "root"                        # パスワード
    STREAM_NAME = "syslog_ng"               # ストリーム名
    ORG_ID = "default"                      # 組織ID
    CHUNK_SIZE = 100000                     # 一度に取得するログ数
    
    # ログ取得範囲（日時指定）
    START_TIME_STR = "2025-06-01 00:00:00"
    END_TIME_STR   = "2025-06-10 23:59:59"
    ```

2.  **スクリプトの実行:**
    ```sh
    python3 download_syslog.py
    ```

3.  **出力ファイル:**
    - `logs_merged.csv`: ダウンロードした syslog データ の CSV ファイル
    - 処理中に一時的に `logs_temp_*.csv` ファイルが作成されますが、完了後に自動削除されます

### 機能

*   **指定期間のログダウンロード**: 開始日時と終了日時を指定してログを取得
*   **大容量対応**: 分割ダウンロードにより、大量のログも処理可能
*   **CSV形式での出力**: Excel や他のツールで分析しやすい CSV 形式で保存
*   **フィールド自動検出**: ログの構造変化に対応してフィールドを自動検出
*   **進捗表示**: ダウンロード状況をリアルタイムで表示

---
### syslog 設定例


#### VyOS (514/tcp または 514/udp)
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
- `set system syslog local ～` はローカルなので送信に影響ない
- `format octet-counted` は指定しない (改行区切りで送信)
- TCP 推奨 (`protocol 'tcp'`)、UDP の場合は `protocol 'udp'`


#### Cisco (3514/tcp または 3514/udp)
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

! Syslog サーバー設定 (TCP 推奨)
logging host <syslog server> transport tcp port 3514 sequence-num-session

! または UDP を使う場合
! logging host <syslog server> transport udp port 3514

! ログレベル設定
logging trap informational

end
write memory
```

**補足:**
- コンソールポート (シリアル) にログが表示されるのを抑制したい場合は `no logging console` を追加
- ローカルバッファにもログを保存したい場合は以下を追加
  ```
  logging buffered 64000
  ```


#### NEC IX UNIVERGE (4514/udp)
```conf
syslog facility local2
syslog ip host <syslog server> port 4514
syslog timestamp datetime
syslog id hostname

syslog ip enable

! src addr や vrf を指定する場合
syslog vrf <vrf_NAME> ip source <src addr>
```


#### YAMAHA RTX (514/udp)
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

#### rsyslog

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

#### syslog-ng (514/tcp または 514/udp)

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

**注意:**
- **514/tcp, 514/udp**: 一般的な RFC 5424/3164 形式として `s_rfc5424` で受信されます
- **ポート番号を変えることで、受信側の処理を変えることができます** (Cisco パーサー、Fortigate パーサーなど)

