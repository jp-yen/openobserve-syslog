# vim: set tabstop=4 fileencoding=utf-8 fileformat=unix filetype=make :# モードライン
SHELL = /bin/bash

help:
	@echo "  Usage:"
	@echo ""
	@echo "    make up            (-) 起動 - 起動時は何もしない"
	@echo "    make down          (-) 停止"
	@echo "    make restart       (-) 停止して起動"
	@echo "    make ps            (-) 起動状況を確認"
	@echo "    make clean         (*) データ、ログの削除"
	@echo "    make update-image  (-) イメージを更新して再起動 (ログは保持)"
	@echo "    make conf_check    (-) config ファイルのチェック"
	@echo "    make show_version  (-) コンテナのバージョン表示"
	@echo "    make flood_syslog  (*) ダミーの syslog メッセージを送信"
	@echo "    make syslog_s      (*) Docker 内の syslog-ng へ直接 syslog を送信"
	@echo ""
	@echo "                       (-) : 一般ユーザで実行"
	@echo "                       (*) : root ユーザで実行"

up: NO_ROOT
	@docker compose up -d

restart: NO_ROOT
	@docker compose down && docker compose up -d

down:
	@docker compose down

ps: NO_ROOT
	@docker compose ps

update-image: NO_ROOT
	@echo "Performing version upgrade: stopping containers, removing old images, and then starting new containers..."
	@docker compose down --rmi all
	@docker compose up -d

# 実行時の user/uid は以下のようなコマンドで確認
clean: NEED_ROOT down
	@find ./syslog-ng/conf/   -mindepth 1 \! -name 'syslog-ng.conf' -print -delete || true
	@find ./openobserve/data/ -mindepth 1 \! -name '.gitkeep'       -print -delete || true
	@install -d -m 777 -o 1000 -g 1000 ./syslog-ng/conf/log/
	@install -d -m 777 -o 0    -g 0    ./openobserve/data/

# syslog-ng の設定ファイルをチェックする
conf_check: NO_ROOT
	@echo "=================================="
	@echo "==== syslog-ng config check ======"
	@echo "=================================="
	@docker run -it --rm --name syslog-ng-conf_check \
	  -v ./syslog-ng/conf:/config \
	  lscr.io/linuxserver/syslog-ng \
	  /usr/sbin/syslog-ng -s -f /config/syslog-ng.conf |\
	  grep -A 1000 ls.io-init || true
	@echo ""

show_version: NO_ROOT
	@echo "=================================="
	@echo "==== syslog-ng version ==========="
	@echo "=================================="
	@docker run -it --rm --name syslog-ng-version \
	  lscr.io/linuxserver/syslog-ng \
	  /usr/sbin/syslog-ng --version |\
	  grep -A 1000 ls.io-init || true
	@echo "=================================="
	@echo "==== OpenObserve version ========="
	@echo "=================================="
	@docker run -it --rm --name openobserve_version \
	  public.ecr.aws/zinclabs/openobserve:latest \
	  /openobserve --version || true


# syslog-ng に直接 syslog メッセージを送信する
syslog_s: NEED_ROOT flo_syslog flood_syslog


flo_syslog:
	$(eval syslog_srv  := `docker exec -it syslog-ng hostname -i | tr -d '\r\n'`)
	$(eval syslog_port := `docker exec -it syslog-ng netstat -una | awk '$$$$1 == "udp" && $$$$4 ~ /^0.0.0.0:/{sub(".*:","",$$$$4); print $$$$4}'`)
	@echo "直接 syslog-ng へ syslog メッセージを送信します"

flood_syslog:
	@syslog_srv=$(syslog_srv) syslog_port=$(syslog_port) ../gen


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
.PHONY: help up restart down ps clean update-image conf_check syslog_s flo_syslog flood_syslog NO_ROOT NEED_ROOT
