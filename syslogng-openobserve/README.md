# OpenObserve と syslog-ng による syslog サーバー

このプロジェクトは、`docker compose` を使用して `syslog-ng` と `OpenObserve` を連携させた syslog サーバーを構築するためのものです。`syslog-ng` が受信したログを `OpenObserve` に転送し、ログの集約、検索、可視化を行います。

## 概要

* **syslog-ng**: ネットワークから syslog を受け付け、OpenObserve に転送します
* **OpenObserve**: 受信した syslog を UI で表示します。DB 上で圧縮されるため、受信するログが多い環境でも安心です。

## 起動方法

`.env.example` を参考に `.env` ファイルを作成し、コンテナを実行するユーザーの UID/GID を指定してください。
`syslog-ng` はここで指定されたユーザーで動作し、ログファイルの書き込みを行います。
そのため、`.env` 内の UID/GID はホスト側のディレクトリ所有者と一致している必要があります。

```sh
cp .env.example .env
# .env ファイルを開き、id コマンド等で確認した自身の UID/GID を設定してください (デフォルト: 1000:1000)
# 必要に応じて Timezone (TZ) も変更してください (デフォルト: Asia/Tokyo)
```

もし書き込みエラー (Permission denied) が発生する場合は、ディレクトリの所有権を `.env` で指定したユーザーの UID/GID と一致するように修正してください。

```sh
# 例: .env で UID=1000, GID=1000 と指定した場合
sudo chown -R 1000:1000 ./syslog-ng/
```

その後、Compose 定義があるディレクトリで以下のコマンドを実行します。

```sh
make up
```

## ログの見方

受信したログを表示するには `http://<サーバーのIPアドレス>:5080` へアクセスし、以下でログインします。

* ユーザー名: `root@root.root`
* パスワード: `root`

(ユーザー名とパスワードは `openobserve/.env` で指定)
左側に並んでいる中から「ストリーム」をクリックし、「syslog-ng」の行の🔍をクリックするとログが表示されます。

## 現行デフォルト設定

以下は、Compose 定義に書かれたコンテナ側の現行デフォルト設定です。

### OpenObserve

* **公式ドキュメント:** [OpenObserve Self-hosted Installation](https://openobserve.ai/docs/guide/quickstart/#self-hosted-installation)
* **イメージ:** `public.ecr.aws/zinclabs/openobserve:v0.80.0`
  * 注意: `simd` タグ付きのイメージ (例: `public.ecr.aws/zinclabs/openobserve:latest-simd`) は AVX512 命令セットに対応した CPU (主に Xeon など) が必要です。
* **コンテナ名:** `OpenObserve`
* **ポートマッピング:**
  * `5080:5080` (OpenObserve の UI および API)
* **ボリュームマッピング:**
  * `./openobserve/data/`: `/data/` (OpenObserve のデータ永続化用)
* **環境変数:**
  * `TZ=${TZ}` (タイムゾーン設定: .env で指定可能)
* **env_file:**
  * `./openobserve/.env` (追加の環境変数を定義可能)
* **再起動ポリシー:** `unless-stopped`

### syslog-ng

* **参考ドキュメント:** [linuxserver/syslog-ng](https://docs.linuxserver.io/images/docker-syslog-ng/)
* **イメージ:** `1yen00docker/syslog-ng:1yen00_v4.11.0`
* **コンテナ名:** `syslog-ng`
* **ポート:**
  * `514/tcp,udp` # 標準的な RFC 5424 形式用 (改行区切り)
  * `2514/tcp`     # RFC 5424 octet-counted 形式用
  * `3514/tcp,udp` # Cisco 機器用
  * `4514/tcp,udp` # RFC 3164 形式用
  * `5514/tcp,udp` # Fortigate 用
  * `5515/tcp,udp` # Palo Alto (PAN-OS) 用
  * `6514/tcp,udp` # JSON 構造化ログ用
  * `7514/tcp,udp` # AlaxalA 用
  * `999/tcp`       # CEF ログ用
* **ボリュームマッピング:**
  * `./syslog-ng/conf/`: `/config/` 設定ファイル
  * `./syslog-ng/buffer/`: `/buffer/` ログのバッファリング用
* **環境変数:**
  * `PUID=${UID}` (プロセスのユーザーID: .env の UID が適用されます)
  * `PGID=${GID}` (プロセスのグループID: .env の GID が適用されます)
  * `TZ=${TZ}` (タイムゾーン設定: .env の TZ が適用されます)
* **再起動ポリシー:** `unless-stopped`

## 使い方

この下の「syslog 設定例」は、接続先機器やアプリケーション側で設定する内容です。上の「現行デフォルト設定」と役割が異なるため、分けて掲載しています。

1. **設定ファイルの準備:**
    * `./openobserve/.env`: 必要に応じて OpenObserve の設定を記述します。
    * `./syslog-ng/conf/syslog-ng.conf`: `syslog-ng` の設定ファイルです。ログのフィルタリングや OpenObserve への転送設定などを記述します。
      (設定例は `syslog-ng` のドキュメントや OpenObserve の連携ガイドを参照してください)

2. **サービスの起動:**

    ```sh
    make up
    ```

3. **OpenObserve へのアクセス:**
    Web ブラウザで `http://<サーバーのIPアドレス>:5080` にアクセスします。

4. **ログの送信:**
    各機器やアプリケーションの syslog 設定で、このサーバーの IP アドレスと以下のポートを指定します。

    | ポート | プロトコル | 用途 |
    |--------|------------|------|
    | 514 | TCP/UDP | 標準的な RFC 5424 形式用 |
    | 2514 | TCP | RFC 5424 octet-counted 形式用 |
    | 3514 | TCP/UDP | Cisco 機器用 |
    | 4514 | TCP/UDP | RFC 3164 形式用 |
    | 5514 | TCP/UDP | Fortigate 用 |
    | 5515 | TCP/UDP | Palo Alto (PAN-OS) 用 |
    | 6514 | TCP/UDP | JSON 構造化ログ用 |
    | 7514 | TCP/UDP | AlaxalA 用 |
    | 999 | TCP | CEF ログ用 |

5. **ログの確認:**
    OpenObserve の UI で収集されたログを検索・確認できます。
    `docker compose logs syslog-ng` や `docker compose logs OpenObserve` で各コンテナのログも確認できます。

6. **設定変更の反映:**
    設定ファイルを変更した場合、変更内容に応じて以下のコマンドを実行します。

    * **`syslog-ng.conf` を変更した場合:**

        ```sh
        make reload
        ```

        `syslog-ng` コンテナを再起動して設定を反映します。

    * **Compose 設定ファイル (docker-compose.yml) や `.env` を変更した場合:**

        ```sh
        make restart
        ```

        コンテナを再作成 (`down` && `up`) して変更を適用します。ポート変更や環境変数の変更時はこちらを使用してください。

7. **サービスの削除:**

    ```sh
    make down
    ```

## Makefile による操作

`Makefile` を使用して、一般的な操作を簡単に行うことができます。

* **コンテナの起動:**

    ```sh
    make up
    ```

* **コンテナの停止、削除:**

    ```sh
    make down
    ```

* **コンテナの再起動とバージョンアップ:**

    ```sh
    make restart
    ```

    このコマンドは `docker compose pull` 後にコンテナを再作成します (`down` && `up`)。Compose 設定ファイルのイメージタグを更新した場合、このコマンドで反映できます。
* **起動状況の確認:**

    ```sh
    make ps
    ```

* **データとログの削除 (初期化):**

    ```sh
    make clean
    ```

    注意: このコマンドは `OpenObserve` の永続化データと `syslog-ng` の一部ログファイルを削除します。実行には `root` 権限が必要な場合があります。
* **イメージの更新と再起動 (バージョンアップ):**

    ```sh
    make update-image
    ```

    このコマンドは、コンテナを停止し、Compose 定義で管理しているサービスに関連する全てのイメージを削除した後、新しいイメージでコンテナを再起動します。データボリュームは保持されるため、ログは削除されません。
* **syslog-ng 設定の高速リロード:**

    ```sh
    make reload
    ```

    `syslog-ng` コンテナを再起動して設定を反映します。コンテナを再作成せずに設定変更を反映させたい場合に便利です。
* **syslog-ng 設定ファイルのチェック:**

    ```sh
    make conf_check
    ```

* **テスト用 syslog メッセージの送信:**

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

1. **設定の変更:**
  スクリプトの現行デフォルト値は以下です。必要に応じて環境に合わせて変更してください。

    ```python
    API_URL = "http://127.0.0.1:5080"          # OpenObserve の URL
    USERNAME = "root@root.root"              # ユーザー名
    PASSWORD = "root"                        # パスワード
    STREAM_NAME = "syslog_ng"               # ストリーム名
    ORG_ID = "default"                      # 組織ID
    CHUNK_SIZE = 10000                      # 一度に取得するログ数
    
    # ログ取得範囲（日時指定）
    START_TIME_STR = "2026-01-10 00:00:00"
    END_TIME_STR   = "2026-01-17 23:59:59"
    ```

    補足: OpenObserve 上のストリーム名表示は `syslog-ng` でも、SQL クエリでは `syslog_ng` を指定します。

2. **スクリプトの実行:**

    ```sh
    python3 download_syslog.py
    ```

3. **出力ファイル:**
    * `logs_merged.csv`: ダウンロードした syslog データ の CSV ファイル
    * 処理中に一時的に `logs_temp_*.csv` ファイルが作成されますが、完了後に自動削除されます

### 機能

* **指定期間のログダウンロード**: 開始日時と終了日時を指定してログを取得
* **大容量対応**: 分割ダウンロードにより、大量のログも処理可能
* **CSV形式での出力**: Excel や他のツールで分析しやすい CSV 形式で保存
* **フィールド自動検出**: ログの構造変化に対応してフィールドを自動検出
* **進捗表示**: ダウンロード状況をリアルタイムで表示

---

### 送信元機器の設定例

送信元機器やアプリケーションの設定例は別ファイルに分けました。詳細は [送信元機器の設定例](README-sender-examples.md) を参照してください。
