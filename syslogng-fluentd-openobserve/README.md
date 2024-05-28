日々、syslog サーバがあると便利だねぇと思いつつ放置していたので docker-compose の勉強がてら
よく聞く syslog-ng ➡ Fluentd ➡ OpenObserve という構成の syslog サーバを立ててみた。

実際作ってみたら、ログ出力から表示まで10秒～1分以上かかり、順番も入れ替わってしまうため
リアルタイムでの確認用途には向いていないですねぇ。
ospf で neighbor down とか、VRRP が切り替わりましたとか、試験紙ながら見るには遅すぎる。

syslog-ng でファイルに吐かせて、tail -f の方がずっと良い。

もう少し高速化の方法はないものか。

- (linuxserver/syslog-ng)[https://docs.linuxserver.io/images/docker-syslog-ng/]


fluentd は Dockerfile の EXPOSE の関係で docker ps で 5140/tcp, 24224/tcp を
使っているように見えるが、今回は使っていない。



