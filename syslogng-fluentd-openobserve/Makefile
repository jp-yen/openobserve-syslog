SHELL = /bin/bash

SYSLOG_NG      = /usr/sbin/syslog-ng
FLUENTD        = /usr/sbin/fluentd
SYSLOG_NG_CONF = ./syslog-ng/conf/syslog-ng.conf
FLUENTD_CONF   = ./fluentd/conf/fluent.conf

help:
	@echo "  Usage:"
	@echo ""
	@echo "    make up            (-) 起動 - 起動時は何もしない"
	@echo "    make down          (-) 停止"
	@echo "    make restart       (-) 停止して起動"
	@echo "    make ps            (-) 起動状況を確認"
	@echo "    make clean         (*) データ、ログの削除"
	@echo "    make conf_check    (-) config ファイルのチェック"
	@echo "                           ホスト環境に fluentd, syslog-ng をインストールしていること"
	@echo "    make flood_syslog  (*) ダミーの syslog メッセージを送信"
	@echo "    make syslog_s      (*) docker の中の syslog-ng へ直接 syslog を送信"
	@echo "    make syslog_f      (*) docker の中の fluentd   へ直接 syslog を送信"
	@echo ""
	@echo "                       (-) : 一般ユーザで起動"
	@echo "                       (*) : root ユーザで起動"

up: NO_ROOT
	@docker compose up -d

restart: NO_ROOT
	@docker compose down && docker compose up -d

down:
	@docker compose down

ps: NO_ROOT
	@docker compose ps

# 実行時の user/uid は以下のようなコマンドで確認
# docker exec -it fluentd ps -a
# docker exec -it fluentd cat /etc/passwd
clean: NEED_ROOT down
	@find ./syslog-ng/conf/   -mindepth 1 \! -name 'syslog-ng.conf' -print -delete || true
	@find ./fluentd/log/      -mindepth 1 \! -name '.gitkeep'       -print -delete || true
	@find ./openobserve/data/ -mindepth 1 \! -name '.gitkeep'       -print -delete || true
	@install -d -m 777 -o 100  -g 101  ./fluentd/log/
	@install -d -m 777 -o 1000 -g 1000 ./syslog-ng/conf/log/
	@install -d -m 777 -o 0    -g 0    ./openobserve/data/

# ローカル環境にインストールしているなら事前に syntax-error をチェックすることは可能
# syslog-ng : apt install syslog-ng
# fluentd   : see  https://docs.fluentd.org/installation/install-by-deb
#             curl -fsSL https://toolbelt.treasuredata.com/sh/install-debian-bullseye-fluent-package5.sh | sh
conf_check:
	@echo ==================================
	@echo ==== syslog-ng config check ======
	@echo ==================================
	@test -x $(SYSLOG_NG) && $(SYSLOG_NG) -s -f $(SYSLOG_NG_CONF)    || true
	@echo ""
	@echo ==================================
	@echo ==== fluentd config check ========
	@echo ==================================
	@test -x $(FLUENTD)   && $(FLUENTD) --dry-run -c $(FLUENTD_CONF) || true

# fluentd に直接 syslog を投げる
syslog_f: NEED_ROOT flo_fluentd flood_syslog

# syslog-ng に直接 syslog を投げる
syslog_s: NEED_ROOT flo_syslog flood_syslog


flo_fluentd:
	$(eval syslog_srv  := `docker exec -it fluentd hostname -i | tr -d '\r\n'`)
	$(eval syslog_port := `sed -rne '/\s*port (\d*)/{s//\1/p}' fluentd/conf/fluent.conf`)
	@echo "直接 fluentd へ syslog メッセージを送信します"

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

