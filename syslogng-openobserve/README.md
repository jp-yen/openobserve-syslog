# OpenObserve と syslog-ng による Syslog サーバー

このプロジェクトは、`docker-compose` を使用して `syslog-ng` と `OpenObserve` を連携させた Syslog サーバーを構築するためのものです。`syslog-ng` が受信したログを `OpenObserve` に転送し、ログの集約、検索、可視化を行います。

## 概要

*   **syslog-ng**: ネットワークから syslog を受け付け OpenObserve に転送します
*   **OpenObserve**: 受信した syslog をブラウザ上で表示します。DB 上で圧縮されるため、受信するログが多い環境でも安心です。

## 起動方法

`docker-compose.yml` があるディレクトリで以下のコマンドを実行します。

```sh
docker-compose up -d
```

## ログの見方

受信したログを表示するには http://localhost:5080 へアクセス、
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
*   **コンテナ名:** `syslog-ng`
*   **ポートマッピング:**
    *   `514:6601/tcp` (Syslog TCP 受信ポート)
    *   `514:5514/udp` (Syslog UDP 受信ポート)
    *   コメントアウト: `# - 6514:6514/tcp` (Syslog TLS 用。設定が必要です)
*   **ボリュームマッピング:**
    *   `./syslog-ng/conf/`: `/config/` (syslog-ng の設定ファイル用)
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
    docker-compose up -d
    ```

3.  **OpenObserve へのアクセス:**
    Web ブラウザで `http://<サーバーのIPアドレス>:5080` にアクセスします。

4.  **ログの送信:**
    各機器やアプリケーションの Syslog 設定で、このサーバーの IP アドレスとポート `514` (TCP または UDP) を指定します。

5.  **ログの確認:**
    OpenObserve の UI で収集されたログを検索・確認できます。
    `docker-compose logs syslog-ng` や `docker-compose logs OpenObserve` で各コンテナのログも確認できます。

6.  **サービスの停止:**
    ```sh
    docker-compose stop
    ```

## Makefile による操作

`Makefile` を使用して、一般的な操作を簡単に行うことができます。

*   **コンテナの起動:**
    ```sh
    make up
    ```
*   **コンテナの停止:**
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
    API_URL = "http://192.168.0.252:5080"    # OpenObserve の URL
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
    - `logs_merged.csv`: ダウンロードしたすべてのログが統合された CSV ファイル
    - 処理中に一時的に `logs_temp_*.csv` ファイルが作成されますが、完了後に自動削除されます

### 機能

*   **指定期間のログダウンロード**: 開始日時と終了日時を指定してログを取得
*   **大容量対応**: チャンク単位での分割ダウンロードにより、大量のログも処理可能
*   **CSV形式での出力**: Excel や他のツールで分析しやすい CSV 形式で保存
*   **フィールド自動検出**: ログの構造変化に対応してフィールドを自動検出
*   **プログレスバー表示**: `tqdm` ライブラリによる詳細な進捗表示
    - ダウンロード進捗をパーセンテージで表示
    - 最後に処理したタイムスタンプを表示
    - バッチ処理時間を表示
    - ファイルマージ進捗も表示

### 注意事項

*   大量のログをダウンロードする場合は時間がかかります
*   OpenObserve の API 制限に注意してください
*   ダウンロード中にネットワーク接続が切断されないようご注意ください
