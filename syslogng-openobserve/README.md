# OpenObserve と Fluent Bit による syslog サーバー

このプロジェクトは、`docker compose` を使用して `Fluent Bit` (Lua スクリプト使用) と `OpenObserve` を連携させた syslog サーバーを構築するためのものです。`Fluent Bit` が受信したログを Lua スクリプトでパース・整形し、`OpenObserve` に転送してログの集約を行います。

## 概要

* **Fluent Bit**: ネットワークから syslog を受け付け、Lua スクリプトでパース・加工して OpenObserve に転送します。
* **OpenObserve**: 受信した syslog を UI で表示します。DB 上で圧縮されるため、受信するログが多い環境でも安心です。

## 起動方法

`.env.example` を参考に `.env` ファイルを作成し、コンテナを実行するユーザーの UID/GID を指定してください。

```sh
cp .env.example .env
# .env ファイルを開き、id コマンド等で確認した自身の UID/GID を設定してください (デフォルト: 1000:1000)
# 必要に応じて Timezone (TZ) も変更してください (デフォルト: Asia/Tokyo)
```

その後、Compose 定義があるディレクトリで以下のコマンドを実行します。

```sh
make up
```

## ログの見方

受信したログを表示するには `http://<サーバーのIPアドレス>:5080` へアクセスし、以下でログインします。

* ユーザー名: `root@root.root`
* パスワード: `root`

(ユーザー名とパスワードは `.env` で指定)
左側に並んでいる中から「ストリーム」をクリックし、「syslog-ng」の行の🔍をクリックするとログが表示されます。

## ログフィールド仕様

Lua スクリプトで整形された出力フィールドのメモ。

| フィールド | 内容 |
|---|---|
| `_timestamp` | **ログ生成時刻** — ログ内タイムスタンプを UTC UNIX エポック時刻（内部的には秒＋小数点以下6桁のマイクロ秒精度 16桁整数で完全保持。※OpenObserve WebUI 上の表示仕様では小数点以下3桁のミリ秒まで表示）。抽出不可時は受信時刻にフォールバック |
| `received_at` | **Fluent Bit 受信時刻** — コンテナ設定のタイムゾーンに従った ISO 8601 形式（例: `YYYY-MM-DDTHH:MM:SS.ffffff+09:00`） |
| `parse_type` | **パース種別** — どのパーサー/形式として識別されたか（値の一覧は下表参照） |
| `message` | ログ本文のみ |
| `raw_message` | 受信した生ログ文字列全体 |
| `priority` | ログレベル 大文字: `INFO` / `WARNING` / `ERR` / `DEBUG` / `NOTICE` / `CRIT` / `ALERT` / `EMERG` |
| `facility` | ファシリティ 大文字: `LOCAL0`〜`LOCAL7` / `USER` / `DAEMON` / `AUTH` 等 |
| `host` | ログ内ホスト名 > 接続元IP |
| `host_from` | 実際の TCP/UDP 接続元 IP |
| `source` | 入力識別子 例: `s_fluent_bit/6514/tcp` |

### `parse_type` の値一覧

| カテゴリ / 機器 | `parse_type` | 説明・判定形式 |
|---|---|---|
| **標準 Syslog** | `RFC5424` | RFC 5424 形式 (`<pri>1 YYYY-MM-DDTHH:MM:SS ...`、標準Linux/CoreDNS等) |
| | `RFC3164_PRI_Host_Prog_PID` | `<pri> Mon DD HH:MM:SS host program[pid]: msg` (NEC UNIVERGE IX ルーター等) |
| | `RFC3164_PRI_Host_Prog` | `<pri> Mon DD HH:MM:SS host program: msg` |
| | `RFC3164_PRI_Host` | `<pri> Mon DD HH:MM:SS host msg` (プログラム名なし) |
| | `RFC3164_PRI` | `<pri> Mon DD HH:MM:SS msg` (ホスト名なし) |
| | `BSD` | PRI なしの BSD Syslog 形式 (`Mon DD HH:MM:SS ...`) |
| | `YAMAHA` | YAMAHA RTX 日時形式 (`YYYY/MM/DD HH:MM:SS ...`) |
| **Cisco 機器** | `Cisco_PRI_Seq_Host_SD_Seq` | `<pri>seq1: host: [syslog@9...]: seq2: msg` (PRI+Seq+Host名+構造化データ+Seq2) |
| | `Cisco_PRI_Seq_Host_SD` | `<pri>seq1: host: [syslog@9...]: msg` (PRI+Seq+Host名+構造化データ、Cat3560CG等) |
| | `Cisco_PRI_Seq_SD_Seq` | `<pri>seq1: [syslog@9...]: seq2: msg` (PRI+Seq+構造化データ+Seq2、Host名なし) |
| | `Cisco_PRI_Seq_SD` | `<pri>seq1: [syslog@9...]: msg` (PRI+Seq+構造化データ、Host名なし) |
| | `Cisco_PRI_Seq_Host` | `<pri>seq: host: msg` (PRI+Seq+Host名) |
| | `Cisco_PRI_Seq` | `<pri>seq: msg` (PRI+Seq、Host名なし) |
| | `Cisco_PRI_Host` | `<pri>host: msg` (PRI+Host名、Seqなし) |
| | `Cisco_Seq_Host` | `seq: host: msg` (Seq+Host名、PRIなし、標準 IOS) |
| | `Cisco_Seq` | `seq: msg` (Seqのみ、PRIなし、Host名なし) |
| | `Cisco_FACILITY` | ヘッダー未合致だが `%FACILITY-SEV-MNEMONIC:` を含む形式 |
| **セキュリティ / ネットワーク機器** | `FortiGate` | FortiGate Key-Value 形式 (`devname=`, `type=`, `date= time=` 等) |
| | `PAN-OS` | Palo Alto PAN-OS CSV 構造化ログ形式 |
| | `AlaxalA` | AlaxalA スイッチログ形式 (AX2600S / AX3660S / AX3630S / AX2100S 等の運用ログ・画面出力形式・メッセージテキスト形式、および従来形式に対応) |
| | `CEF` | CEF 形式 (`CEF:0\|...`) |
| **アプリケーション / JSON** | `JSON` | 有効な JSON 構造化ログ（内部の logfmt / タイムスタンプも自動解析） |
| | `LOGFMT` | 非 JSON だが `msg="..."` や `key=value` ペアを含む形式 |
| **フォールバック** | `*_FALLBACK` | パース不能時に生ログをロストせず保存（`JSON_FALLBACK`, `RFC5424_FALLBACK`, `RFC3164_FALLBACK`, `Cisco_FALLBACK`, `FortiGate_FALLBACK`, `PAN-OS_FALLBACK`, `AlaxalA_FALLBACK`, `CEF_FALLBACK`, `RAW_FALLBACK`） |



## 現行デフォルト設定

以下は、Compose 定義に書かれたコンテナ側の現行デフォルト設定です。

### OpenObserve

* **公式ドキュメント:** [OpenObserve Self-hosted Installation](https://openobserve.ai/docs/guide/quickstart/#self-hosted-installation)
* **イメージ:** `public.ecr.aws/zinclabs/openobserve:v1.0.0`
* **コンテナ名:** `OpenObserve`
* **ポートマッピング:**
  * `5080:5080` (OpenObserve の UI および API)
* **ボリュームマッピング:**
  * `./openobserve/data/`: `/data/` (OpenObserve のデータ永続化用)
* **環境変数:**
  * `TZ=${TZ}` (タイムゾーン設定: .env で指定可能)
  * `ZO_DATA_DIR` / `ZO_ROOT_USER_EMAIL` / `ZO_ROOT_USER_PASSWORD` (.env で指定可能)

### Fluent Bit

* **公式ドキュメント:** [Fluent Bit Documentation](https://docs.fluentbit.io/)
* **イメージ:** `fluent/fluent-bit:5.1.2`
* **コンテナ名:** `fluent-bit`
* **ポート:**
  * `514/tcp,udp`  # 標準的な RFC 5424, RFC 3164, YAMAHA RTX 形式用 (改行区切り)
  * `2514/tcp`      # RFC 5424 octet-counted 形式用 (RFC 6587 / RFC 5425 フレーミング)
  * `3514/tcp,udp`  # Cisco 機器用 (PRI, シーケンス番号, 構造化データ等に対応)
  * `4514/tcp,udp`  # 標準的な RFC 3164, RFC 5424, YAMAHA RTX, NEC IX 等用 (改行区切り)
  * `5514/tcp,udp`  # Fortigate 用 (Key-Value 形式)
  * `5515/tcp,udp`  # Palo Alto (PAN-OS) 用 (CSV 形式)
  * `6514/tcp,udp`  # JSON 構造化ログ / LOGFMT 形式用
  * `7514/tcp,udp`  # AlaxalA スイッチ用 (運用ログ・画面出力形式等)
  * `999/tcp`        # CEF ログ用
* **ボリュームマッピング:**
  * `./fluent-bit/conf/fluent-bit.conf`: `/fluent-bit/etc/fluent-bit.conf` (メイン設定)
  * `./fluent-bit/conf/parsers.conf`: `/fluent-bit/etc/parsers.conf` (パーサー定義)
  * `./fluent-bit/scripts/`: `/fluent-bit/scripts/` (ポート別の Lua 変換スクリプト群)
  * `./fluent-bit/buffer/`: `/fluent-bit/buffer/` (ログのディスクバッファ用)
* **環境変数:**
  * `TZ=${TZ}` (タイムゾーン設定: .env の TZ が適用されます)

## 使い方

1. **設定ファイルの準備:**
    * `.env`: UID/GID、TZ、OpenObserve の管理者アカウント等を記述します（`.env.example` から作成）。
    * `./fluent-bit/conf/fluent-bit.conf`: Fluent Bit のメイン設定ファイルです。
    * `./fluent-bit/scripts/`: 各ポートに対応する独立したパース用 Lua スクリプト (`common.lua`, `syslog_standard.lua`, `cisco.lua`, `json.lua` 等) です。

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
    | 514 | TCP/UDP | 標準的な RFC 5424, RFC 3164, YAMAHA RTX 形式用 (改行区切り) |
    | 2514 | TCP | RFC 5424 octet-counted 形式用 (RFC 6587 / RFC 5425 フレーミング) |
    | 3514 | TCP/UDP | Cisco 機器用 (PRI, シーケンス番号, 構造化データ等に対応) |
    | 4514 | TCP/UDP | 標準的な RFC 3164, RFC 5424, YAMAHA RTX, NEC IX 等用 (改行区切り) |
    | 5514 | TCP/UDP | Fortigate 用 (Key-Value 形式) |
    | 5515 | TCP/UDP | Palo Alto (PAN-OS) 用 (CSV 形式) |
    | 6514 | TCP/UDP | JSON 構造化ログ / LOGFMT 形式用 |
    | 7514 | TCP/UDP | AlaxalA スイッチ用 (運用ログ・画面出力形式等) |
    | 999 | TCP | CEF ログ用 |

5. **ログの確認:**
    OpenObserve の UI で収集されたログを検索・確認できます。
    `docker compose logs fluent-bit` や `docker compose logs OpenObserve` で各コンテナのログも確認できます。

6. **設定変更の反映:**
    設定ファイルや Lua スクリプトを変更した場合、変更内容に応じて以下のコマンドを実行します。

    * **`fluent-bit.conf` や Lua スクリプトを変更した場合:**

        ```sh
        make reload
        ```

        `fluent-bit` コンテナを再起動して設定を反映します。

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

`Makefile` を使用した主な操作コマンド一覧です。

| コマンド | 説明 | 権限 |
|---|---|:---:|
| `make up` | コンテナの起動 | 一般 |
| `make down` | コンテナの停止・削除 | 一般 |
| `make restart` | `docker compose pull` 後にコンテナ再作成（更新反映） | 一般 |
| `make reload` | `fluent-bit` コンテナを再起動して設定を即時反映 | 一般 |
| `make ps` | 起動状況の確認 | 一般 |
| `make conf_check` | Fluent Bit 設定ファイルの構文チェック（dry-run） | 一般 |
| `make clean` | データ・ログの削除（初期化） | root |
| `make update-image` | ローカルイメージ全削除後に再取得・再起動（ログ保持） | 一般 |
| `make test_syslog` | 各パーサーへテスト syslog を送信（各機器・形式の検証） | 一般 |
| `make flood_syslog` / `make syslog_s` | 大量 syslog ダミーメッセージの送信（負荷試験） | root |

詳細は `Makefile` を参照してください。

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

### 機能

* **指定期間のログダウンロード**: 開始日時と終了日時を指定してログを取得
* **大容量対応**: 分割ダウンロードにより、大量のログも処理可能
* **CSV形式での出力**: Excel や他のツールで分析しやすい CSV 形式で保存
* **フィールド自動検出**: ログの構造変化に対応してフィールドを自動検出
* **進捗表示**: ダウンロード状況をリアルタイムで表示

---

### 送信元機器の設定例

送信元機器やアプリケーションの設定例は [送信元機器の設定例](README-sender-examples.md) を参照のこと。
