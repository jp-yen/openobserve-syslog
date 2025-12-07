#!/usr/bin/env bash
set -euo pipefail

# 環境変数（docker-compose/env から渡す）
PUID="${PUID:-65534}"
PGID="${PGID:-65534}"
USER_NAME="syslogng"
GROUP_NAME="syslogng"

# 既存グループ/ユーザーを確認・作成
# 優先順位:
# 1. 指定された PGID/PUID を持つ既存のグループ/ユーザーがいれば、それを使用する (修正なし)
# 2. なければ、デフォルト名 (syslogng) のグループ/ユーザーを探して ID を修正する
# 3. それもなければ新規作成する

# グループの決定
if getent group "${PGID}" >/dev/null 2>&1; then
  # GID が一致するグループが既にある -> その名前を採用
  GROUP_NAME="$(getent group "${PGID}" | cut -d: -f1)"
elif getent group "${GROUP_NAME}" >/dev/null 2>&1; then
  # グループ名は存在するが GID が違う -> GID を修正して使用
  groupmod -g "${PGID}" "${GROUP_NAME}"
else
  # 新規作成
  groupadd -g "${PGID}" "${GROUP_NAME}"
fi

# ユーザーの決定
if id -u "${PUID}" >/dev/null 2>&1; then
  # UID が一致するユーザーが既にある -> その名前を採用
  USER_NAME="$(id -u -n "${PUID}")"
elif id -u "${USER_NAME}" >/dev/null 2>&1; then
  # ユーザー名は存在するが UID が違う -> UID を修正して使用
  usermod -u "${PUID}" -g "${PGID}" "${USER_NAME}"
else
  # 新規作成
  useradd -u "${PUID}" -g "${PGID}" -d /var/lib/syslog-ng -s /sbin/nologin "${USER_NAME}"
fi

# 必要ディレクトリを作成・所有権付与
# /var/lib/syslog-ng は内部ステート(PID/ソケット)用なので常に所有権を変更
chown -R "${USER_NAME}:${GROUP_NAME}" /var/lib/syslog-ng

# マウントされていない場合 (コンテナ内部ストレージ) のみ所有権を変更
if ! grep -qs " /config " /proc/mounts; then
    chown -R "${USER_NAME}:${GROUP_NAME}" /config
fi
if ! grep -qs " /var/log/syslog-ng " /proc/mounts; then
    chown -R "${USER_NAME}:${GROUP_NAME}" /var/log/syslog-ng
fi

# /config ディレクトリ自体の書き込み権限チェック
if ! gosu "${USER_NAME}:${GROUP_NAME}" test -w /config; then
    echo "[ERROR] /config ディレクトリにユーザー ${USER_NAME} (UID: ${PUID}) で書き込む権限がありません。" >&2
    echo "        マウントしたボリュームの権限を確認してください。" >&2
    # 確実に動かないので終了する
    exit 1
fi

# /var/log/syslog-ng ディレクトリの書き込み権限チェック
if ! gosu "${USER_NAME}:${GROUP_NAME}" test -w /var/log/syslog-ng; then
    echo "[ERROR] /var/log/syslog-ng ディレクトリにユーザー ${USER_NAME} (UID: ${PUID}) で書き込む権限がありません。" >&2
    echo "        マウントしたボリュームの権限を確認してください。" >&2
    exit 1
fi

# 初期設定ファイルの生成と使用する設定ファイルの決定
CONFIG_FILE="/config/syslog-ng.conf"

if [ -f "$CONFIG_FILE" ]; then
    # 設定ファイルが存在する場合
    echo "既存の設定ファイルを使用します: $CONFIG_FILE"
else
    # 設定ファイルが存在しない場合はデフォルトファイルを読む
    echo "[WARNING] /config/syslog-ng.conf が見つかりません。" >&2
    echo "          内部のデフォルト設定を使用します。" >&2
    CONFIG_FILE="/usr/local/share/syslog-ng/default.conf"
fi

# ファイルへの書き込み権限チェック
for file in syslog-ng.persist syslog-ng.pid syslog-ng.ctl; do
    if [ -f "/config/$file" ]; then
        if ! gosu "${USER_NAME}:${GROUP_NAME}" test -w "/config/$file"; then
            echo "[ERROR] ファイル /config/$file は存在しますが、ユーザー ${USER_NAME} で書き込みできません。" >&2
        fi
    fi
done

# デーモン(syslog-ng)自身の起動ログやエラーメッセージを
# docker logs (標準出力/標準エラー出力) に正しく表示させるために権限を調整
if [ -t 1 ]; then
  TTY_DEV=$(readlink -f /proc/self/fd/1)
  chown "${USER_NAME}:${GROUP_NAME}" "$TTY_DEV" || true
fi
if [ -t 2 ]; then
  TTY_DEV_ERR=$(readlink -f /proc/self/fd/2)
  chown "${USER_NAME}:${GROUP_NAME}" "$TTY_DEV_ERR" || true
fi



# 指定ユーザーへ切り替えて syslog-ng 実行
# Dockerの標準出力へログを転送するリレープロセスをバックグラウンドで開始
# 非rootユーザーで動作するsyslog-ngが、root所有の /dev/stdout に書き込めない権限問題を回避します
PIPE_FILE="/var/lib/syslog-ng/docker.stdout"
if [ ! -p "$PIPE_FILE" ]; then
    mkfifo "$PIPE_FILE"
fi
chown "${USER_NAME}:${GROUP_NAME}" "$PIPE_FILE"

# パイプから読み出して標準出力に書き込むバックグラウンド処理
(
    while true; do
        cat < "$PIPE_FILE" || sleep 1
    done
) &

# 常に必要なオプション (-F, -f, -R, --stderr) を付与して実行し、ユーザー引数 ($@) を追加する
exec gosu "${USER_NAME}:${GROUP_NAME}" /usr/local/sbin/syslog-ng -F -f "$CONFIG_FILE" -R /config/syslog-ng.persist --stderr "$@"
