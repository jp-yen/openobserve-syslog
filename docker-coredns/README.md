# CoreDNS Docker Image

このディレクトリには、CoreDNS を Docker で実行するための設定ファイルと、カスタム Docker イメージをビルドするための手順が含まれています。

## CoreDNS の使い方 (docker-compose を利用)

`docker-compose.yml` を使用して CoreDNS サービスを起動できます。

1.  **設定ファイルの準備:**
    *   `./config/Corefile`: CoreDNS のメイン設定ファイル。必要に応じて編集してください。
    *   `./config/hosts`: CoreDNS が名前解決に使用するホストファイル。`/etc/hosts` と同じフォーマットで記載、あるいは /etc/hosts にハードリンクするとホストと同期され便利な場面もあるでしょう。

2.  **CoreDNS サービスの起動:**
    `docker-coredns` ディレクトリで以下のコマンドを実行します。
    ```sh
    docker-compose up -d
    ```

3.  **動作確認:**
    CoreDNS は以下のポートでリッスンします。
    *   TCP: 53
    *   UDP: 53

    `dig` コマンドなどで名前解決をテストできます。
    ```sh
    dig @localhost <ドメイン名>
    ```

4.  **ログの確認:**
    ```sh
    docker-compose logs dns
    ```

5.  **サービスの停止:**
    ```sh
    docker-compose down
    ```


## Docker イメージのビルド方法

CoreDNS のカスタム Docker イメージをビルドする手順です。

1.  **Go言語のインストール:**
    Go言語がインストールされていない場合は、[公式ドキュメント](https://go.dev/doc/install)に従ってインストールしてください。

2.  **CoreDNS ソースコードのクローン:**
    ```sh
    git clone https://github.com/coredns/coredns.git
    cd coredns
    ```
    - 特定のブランチ,タグ (例: v1.12.2) をクローンする場合は以下のように指定する
        ```sh
        git clone https://github.com/coredns/coredns.git -b v1.12.2
        ```

3.  **ビルドオプションの設定 (任意):**

    *   **バイナリサイズの削減:** `-ldflags="-s -w"` を使用すると、デバッグ情報を削除し実行ファイルのサイズが小さくなります。
        ```sh
        go build -ldflags="-s -w"
        ```

    *   **AMD64マイクロアーキテクチャレベルの指定:**
        `amd64` 環境でビルドする場合 `GOAMD64` 環境変数を設定し、ターゲットCPUのマイクロアーキテクチャレベルに応じた最適化されたコードを生成させることができます。
        ご自身のCPUでサポートされている最大の `GOAMD64` レベルは、ターミナルで以下のコマンドを実行することで確認できます。
        ```sh
        go env GOAMD64
        ```
        出力された値 (例: `v1`, `v2`, `v3`, `v4`) を `GOAMD64` 環境変数に設定します。レベルが高いほど新しいCPU機能を活用できますが、古いCPUでは動作しない可能性があります。

    環境変数を設定しこれらのフラグを設定できます。

    `make` コマンド実行時に環境変数を設定し `go build` コマンドへフラグを渡すことができます。

    例 (sh/bash の場合):
    ```sh
    export GOAMD64=v3 # CPUがサポートするレベルを指定 (例: v3)
    export BUILDOPTS="-ldflags='-s -w'"
    make
    ```
    または、makeコマンド実行時に直接指定することも可能です。
    ```sh
    make GOAMD64=v3 BUILDOPTS="-ldflags='-s -w'"
    ```

1.  **CoreDNS のビルド:**
    ```sh
    make
    ```

2.  **Dockerfile の編集:**
    ビルドされた CoreDNS を使用するように Dockerfile を更新します。
    ```sh
    echo 'VOLUME ["/etc/coredns"]' >> Dockerfile
    echo 'CMD ["-conf", "/etc/coredns/Corefile"]' >> Dockerfile
    ```

3.  **Docker イメージのビルド:**
    Git のコミットハッシュを取得し、それを使って Docker イメージにタグを付けます。
    ```sh
    HASH=$(git log | awk 'NR==1{print $2}')
    docker buildx build . -t 1yen00docker/coredns:$HASH -t 1yen00docker/coredns:1yen00_v1.12.2
    ```

4.  **Docker イメージのプッシュ (任意):**
    ビルドしたイメージを Docker Hub にプッシュします。
    ```sh
    # docker push 1yen00docker/coredns:$HASH
    docker push 1yen00docker/coredns:1yen00_v1.12.2
    ```

