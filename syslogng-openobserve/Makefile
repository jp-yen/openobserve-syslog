# vim: set tabstop=4 fileencoding=utf-8 fileformat=unix filetype=make :# モードライン
SHELL = /bin/bash

# Load .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Default values if not in .env
UID ?= 1000
GID ?= 1000

help:
	@echo "  Usage:"
	@echo ""
	@echo "    make up            (-) 起動 - 起動時は何もしない"
	@echo "    make down          (-) 停止"
	@echo "    make restart       (-) 停止して起動 (コンテナを再作成する)"
	@echo "    make reload        (-) Fluent Bit の設定リロード (コンテナ再起動)"
	@echo "    make ps            (-) 起動状況を確認"
	@echo "    make clean         (*) データ、ログの削除"
	@echo "    make update-image  (-) イメージを更新して再起動 (ログは保持)"
	@echo "    make conf_check    (-) config ファイルのチェック"
	@echo "    make show_version  (-) コンテナのバージョン表示"
	@echo "    make test_syslog   (-) 各パーサーへテスト syslog を送信 (各機器・形式の検証)"
	@echo "    make flood_syslog  (*) ダミーの syslog メッセージを送信 (負荷試験)"
	@echo "    make syslog_s      (*) Docker 内の Fluent Bit へ直接 syslog を送信 (負荷試験)"
	@echo ""
	@echo "                       (-) : 一般ユーザで実行"
	@echo "                       (*) : root ユーザで実行"

up: NO_ROOT
	@docker compose up -d

restart: NO_ROOT
	@echo "Pulling new images..."
	@docker compose pull
	@docker compose down && docker compose up -d

reload: NO_ROOT
	@echo "Restarting fluent-bit container..."
	@docker compose restart fluent-bit
	@echo "Done."

down:
	@docker compose down

ps: NO_ROOT
	@docker compose ps

# :latest でアップデートしたい場合など
update-image: NO_ROOT
	@echo "ローカルイメージを削除し新しいイメージを取得・起動します..."
	@docker compose down --rmi all
	@docker compose up -d

clean: NEED_ROOT down
	@find ./fluent-bit/buffer/ -mindepth 1 \! -name '.keepme'       -print -delete || true
	@find ./openobserve/data/  -mindepth 1 \! -name '.gitkeep'      -print -delete || true
	@install -d -m 777 -o $(UID) -g $(GID) ./fluent-bit/buffer/
	@install -d -m 777 -o $(UID) -g $(GID) ./openobserve/data/

# Fluent Bit の設定ファイルをチェックする
conf_check: NO_ROOT
	@echo "=================================="
	@echo "==== Fluent Bit config check ====="
	@echo "=================================="
	@docker compose run --rm --no-deps fluent-bit \
	  /fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit.conf --dry-run
	@echo ""

show_version: NO_ROOT
	@echo "=================================="
	@echo "==== Fluent Bit version =========="
	@echo "=================================="
	@docker compose exec fluent-bit /fluent-bit/bin/fluent-bit --version 2>/dev/null || \
	  docker compose run --rm --no-deps fluent-bit /fluent-bit/bin/fluent-bit --version
	@echo "=================================="
	@echo "==== OpenObserve version ========="
	@echo "=================================="
	@docker compose exec OpenObserve /openobserve --version 2>/dev/null || \
	  docker compose run --rm --no-deps OpenObserve /openobserve --version

# 各パーサーへのテスト syslog 送信
test_syslog: NO_ROOT
	@echo "Sending test syslog messages..."
	@echo '<30>1 2026-08-22T11:00:00+09:00 myhost testapp 123 - - test RFC5424' | nc -u -w1 127.0.0.1 514
	@MSG='<30>1 2026-08-22T11:00:00+09:00 myhost testapp 123 - - test RFC5424 octet-counted'; printf '%s %s' "$${#MSG}" "$$MSG" | nc -w1 127.0.0.1 2514
	@echo '<30>Aug 22 11:00:00 myhost sshd[123]: test RFC3164' | nc -u -w1 127.0.0.1 4514
	@echo '<30>2026/08/22 11:00:00 [PPPoE] test YAMAHA' | nc -u -w1 127.0.0.1 514
	@echo '<189>101: switch1: [syslog@9 s_sn="111"]: 201: *Aug 22 11:00:00.001 JST: %SYS-5-CONFIG_I: Cisco_PRI_Seq_Host_SD_Seq test' | nc -u -w1 127.0.0.1 3514
	@echo '<189>102: switch2: [syslog@9 s_sn="222"]: *Aug 22 11:00:00.002 JST: %SYS-5-CONFIG_I: Cisco_PRI_Seq_Host_SD test' | nc -u -w1 127.0.0.1 3514
	@echo '<189>103: switch3: *Aug 22 11:00:00.003 JST: %LINK-3-UPDOWN: Cisco_PRI_Seq_Host test' | nc -u -w1 127.0.0.1 3514
	@echo 'date=2026-08-22 time=11:00:00 devname="FGT-01" devid="FGT60E" type="traffic" level="notice" msg="test fortigate"' | nc -u -w1 127.0.0.1 5514
	@echo '1,2026/08/22 11:00:00,0123456789,SYSTEM,general,0,2026/08/22 11:00:00,vsys1,general,,0,0,general,informational,test panos,0' | nc -u -w1 127.0.0.1 5515
	@echo 'LOG 08/22 11:00:00 I001 SYSTEM test alaxala' | nc -u -w1 127.0.0.1 7514
	@echo 'CEF:0|Security|ThreatManager|1.0|100|worm connection|10|src=10.0.0.1 msg=test cef' | nc -w1 127.0.0.1 999
	@echo '{"system":"web","program":"nginx","message":"test json","date":1787361389}' | nc -w1 127.0.0.1 6514
	@echo 'plain text non-json fallback test' | nc -w1 127.0.0.1 6514
	@echo "All test messages sent."

# Fluent Bit に直接 syslog メッセージを送信する
syslog_s: NEED_ROOT flo_syslog flood_syslog

flo_syslog:
	$(eval syslog_srv  := `docker compose exec -T fluent-bit hostname -i 2>/dev/null | tr -d '\r\n'`)
	$(eval syslog_port := `docker compose exec -T fluent-bit netstat -una 2>/dev/null | awk '$$$$1 == "udp" && $$$$4 ~ /^0.0.0.0:/{sub(".*:","",$$$$4); print $$$$4}'`)
	@echo "直接 fluent-bit へ syslog メッセージを送信します (Server: $(syslog_srv), Port: $(syslog_port))"

flood_syslog:
	@test -f ../gen && syslog_srv=$(syslog_srv) syslog_port=$(syslog_port) ../gen || echo "generator ../gen not found."

NO_ROOT:
	@test `id -u` -eq 0 && echo "Usually do not use root user!!!" ; true

NEED_ROOT:
	@if [ `id -u` -ne 0 ]; then \
		echo "一部のファイルが削除できません" ;\
		echo "或いはパケットが送れません" ;\
		echo "you must run as root user"  ;\
		exit 255 ;\
	fi

# ファイルがあっても実行する疑似ターゲット
.PHONY: help up restart reload down ps clean update-image conf_check show_version test_syslog syslog_s flo_syslog flood_syslog NO_ROOT NEED_ROOT

