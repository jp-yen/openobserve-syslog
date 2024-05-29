SHELL = /bin/bash


help:
	@echo make up            起動
	@echo make down          停止
	@echo make ps            起動状況を確認
	@echo make clean         データ、ログの削除
	@echo make flood_syslog  syslog メッセージを送信
	@echo make syslog_s      docker の中の syslog-ng へ直接 syslog を送信
	@echo make syslog_f      docker の中の fluentd へ直接 syslog を送信

up: NO_ROOT
	@docker compose down && docker compose up -d

down:
	@docker compose down

ps: NO_ROOT
	@docker compose ps

clean: NEED_ROOT down
	@find ./syslog-ng/conf/   -mindepth 1 \! -name 'syslog-ng.conf' -print -delete || true
	@find ./fluentd/log       -mindepth 1 \! -name '.gitkeep'       -print -delete || true
	@find ./openobserve/data/ -mindepth 1 \! -name '.gitkeep'       -print -delete || true


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

