# 概要
syslog-ng コンテナです。
セキュリティ向上のため、デフォルトで非 root ユーザーとして動作します。
`PUID`/`PGID` を指定することで、保存されるログファイルの所有権をホスト側のユーザーに合わせることができ、管理が容易になります。

## ビルド方法
以下のコマンドを実行してください。

```bash
cd build-container/syslog-ng
docker build -t syslog-ng:latest .
```

### ビルド (docker buildx を使用する場合)

`buildx` を使用すると、ビルドの並列実行による高速化や、異なる CPU アーキテクチャ向け（マルチアーキテクチャ）のイメージ作成が可能です。

**1. 高速ビルド (現在のアーキテクチャ向け)**
キャッシュが強力に効くため、再ビルドが高速になります。
```bash
docker buildx build -t syslog-ng:latest --load .
```

**2. マルチアーキテクチャビルド (AMD64 & ARM64)**
PC (amd64) と Raspberry Pi (arm64) の両方で動くイメージを作る場合です。
※ `--load` (ローカル保存) はマルチアーキテクチャと同時に使えない場合があるため、テスト時は `--platform` を一つに絞るか、レジストリへ `--push` してください。

```bash
# 初回のみビルダーを作成
docker buildx create --name mybuilder --use

# 両方のアーキテクチャ用にビルドして出力 (例: レジストリへのプッシュ)
# docker buildx build --platform linux/amd64,linux/arm64 -t start9/syslog-ng:latest --push .
```

### バージョン指定ビルド

syslog-ng の特定のバージョンを指定してビルドしたい場合は、`--build-arg` を使用します。

```bash
# バージョンを変数で定義
VERSION="4.10.2"

docker buildx build \
  --build-arg SYSLOG_NG_version="${VERSION}" \
  -t syslog-ng-dev:"${VERSION}" \
  --load .
```
（GitHub のリリースタグ `syslog-ng-x.y.z` に対応します）
ビルド時は、生成されるイメージにもバージョン情報やGitコミットハッシュをタグ付けすることを推奨します。

```bash
# 変数設定 (例)
VERSION="4.10.2"

# ビルド実行
docker build \
  --build-arg SYSLOG_NG_version="${VERSION}" \
  -t syslog-ng-dev:"${VERSION}" \
  .
```

## コンテナの起動方法

推奨される構成（設定ファイルの永続化＋ログ保存＋ローカルタイム設定）での起動例です。
まず、設定ファイルとログを保存するディレクトリを作成します。

```bash
mkdir -p conf logs
```

```bash
docker run -d \
  --name syslog-ng-dev \
  --restart unless-stopped \
  -p 666:514/udp \
  -p 666:514/tcp \
  -v ./conf:/config \
  -v ./conf/syslog-ng.conf:/config/syslog-ng.conf:ro \
  -v ./logs:/var/log/syslog-ng \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Tokyo \
  --ulimit nofile=10000:10000 \
  syslog-ng-dev:4.10.2
```

## パラメータ設定

コンテナの動作を制御する主なパラメータ一覧です。

| パラメータ | 形式 | デフォルト | 説明 |
|---|---|---|---|
| `-p` | Port | 514 | TCP/UDP の受信ポート (必要に応じて変更可) |
| `-v /config` | Volume | - | 設定ファイルや永続データ (`.persist`) の保存場所 |
| `-e PUID` | Env | 65534 | 実行ユーザーID (デフォルト: nobody) |
| `-e PGID` | Env | 65534 | 実行グループID (デフォルト: nogroup) |
| `-e TZ` | Env | - | タイムゾーン (例: `Asia/Tokyo`) |
| `--ulimit` | Arg | - | 大規模環境用 (例: `nofile=10000:10000`) |

### ディレクトリ・ファイル構成 (マウント設定)

| ホスト側パス (例) | コンテナ内パス | 説明 | 必須 |
|---|---|---|---|
| `logs/` | `/var/log/syslog-ng` | ログファイルの出力先 | 推奨 |
| `config/` | `/config` | 永続データ (`.persist`) の保存場所 | **必須** |
| `syslog-ng.conf` | `/config/syslog-ng.conf` | 設定ファイル (Read-Only 推奨) | 任意 |



### タイムゾーン (TZ)

コンテナ内の時刻をローカルタイム（ログのタイムスタンプ等）に合わせる場合、環境変数 `TZ` を指定します。
例: `-e TZ=Asia/Tokyo`

これにより、`syslog-ng` はログのタイムスタンプを正しく（例: `+09:00`）記録します。



### デフォルト起動オプションとカスタマイズ

#### デフォルトコマンド
コンテナは以下のオプションで `syslog-ng` を起動します：
```bash
/usr/local/sbin/syslog-ng -F -f <CONFIG_FILE> -R /config/syslog-ng.persist --stderr
```
(各オプション: `-F` フォアグラウンド, `-f` 設定ファイル, `-R` 永続ファイル, `--stderr` 標準エラー出力)

#### 起動コマンドへのオプション追加 (Advanced)

`docker run` の引数にオプションを指定すると、デフォルトの起動コマンドに追加されます。
`-F` (フォアグラウンド)、`-f` (設定ファイル)、`-R` (Persistファイル)、`--stderr` (標準エラー出力) は自動的に付与されるため、指定不要です。

```bash
# デバッグモード (-d) を有効にする例
docker run -d \
  ... \
  syslog-ng:4.10.2 -d
```

※ 内部的に実行されるコマンド:
`/usr/local/sbin/syslog-ng -F -f <CONFIG_FILE> -R /config/syslog-ng.persist --stderr -d`

#### 大量接続時の注意 (ulimit)
多数のクライアントから接続を受け付ける場合、デフォルトの上限 (1024) では不足する可能性があります。
その場合は `--ulimit nofile=10000:10000` を指定して起動してください。

## 運用 Tips

### 設定のリロード
コンテナを再起動せずに設定ファイル (`syslog-ng.conf`) の変更を反映させるには、以下のコマンドを実行します。
```bash
docker exec syslog-ng-dev syslog-ng-ctl reload
```
（または `docker kill -s HUP syslog-ng-dev` でも可能です）

### 統計情報の確認
現在のログ受信数やドロップ数などの統計情報を確認するには、以下のコマンドを実行します。
```bash
docker exec syslog-ng-dev syslog-ng-ctl stats
```

# 送信試験 TCP, UDP で100件づつ送信する
```bash
for i in $(seq 1 100); do
  logger -n 127.0.0.1 -T -P 666 --octet-count "alpha beta TCP #$i"
  logger -n 127.0.0.1 -P 666 "alpha beta UDP #$i"
done
```

