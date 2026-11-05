# rhkcs-mcp-setup

Red Hat ナレッジベース（KCS）を検索する MCP サーバーを、このリポジトリの Claude Code で使えるようにするスキルです。MCP サーバーには、[cldmnky/mcp-servers](https://github.com/cldmnky/mcp-servers) の rhkcs-mcp（Apache-2.0）を使います。

導入すると、Claude Code が次のツールを使えるようになります（ログインが必要な記事も読めます）。各スキルでの使い方は、[ルートの README](../../../README.md) を参照してください。

| ツール | 内容 |
| --- | --- |
| `mcp__rhkcs__search_kcs` | ナレッジベースの solution と article を検索する（ID、題名、URL） |
| `mcp__rhkcs__get_kcs` | ID を指定して読む。solution は環境・事象・解決策・根本原因、article は要約だけ（返るコマンドは空白が抜けるので、そのままでは実行できない） |

## 前提条件

- Go 1.25.0 以上と git が入っている（スキルは入れません。macOS なら `brew install go`、Linux なら配布元のパッケージか <https://go.dev/dl/>）。
- Red Hat アカウントで、offline token を作れる（<https://access.redhat.com/management/api>）。

## 使い方

```text
/rhkcs-mcp-setup
```

次の順に進みます。

1. 導入の状況を確認する（`rhkcs.sh check`）。
2. 固定したコミットのソースを取得し、ビルドする（`rhkcs.sh build`）。
3. offline token を、別のターミナルで、画面に表示せずに保存してもらう（`rhkcs.sh token`。token は引数に付けない）。
4. MCP サーバーを起動して、1 件検索できるかを確かめる（`rhkcs.sh test`）。
5. Claude Code を起動し直し（会話を続けるなら `claude --continue`）、`.mcp.json` の `rhkcs` の使用を承認する。スキルが、Claude Code から検索と読み取りができるかを確かめる。

## 新しい版にする

ビルドに使うソースは、確かめたコミット（`rhkcs.sh` の `PIN`）に固定しています。確かめていないコードに token を渡さないためです。

新しい版にしたいときは、`/rhkcs-mcp-setup 更新` のように、更新したいことを伝えて実行します。

1. 固定したコミットから最新までの変更を表示する（`rhkcs.sh update`）。増えたコミット、変わったファイル、特に気をつける変更（通信先の URL、token・認証、環境変数、ツールの名前と引数を含む行）、必要な Go の版が出ます。
2. スキルが要点を添えて、上げてよいかを聞く。
3. 了承すると、スキルが `PIN` を書き換え、ビルドし直して、検索できるかを確かめる。
4. Claude Code を起動し直す。`PIN` の書き換えは共有のファイルの変更なので、コミットして共有します。

## 仕組み

リポジトリのルートの `.mcp.json` に、次のように `rhkcs` を登録しています。

```json
{
  "mcpServers": {
    "rhkcs": {
      "command": "bash",
      "args": [".claude/skills/rhkcs-mcp-setup/scripts/rhkcs.sh", "run"]
    }
  }
}
```

- Claude Code は起動するときに `rhkcs.sh run` を実行し、stdio で MCP サーバーとやり取りします（ネットワークで待ち受けません）。プロジェクトの MCP サーバーなので、初めて使うときに Claude Code が承認を求めます。
- `rhkcs.sh run` は、`.rhkcs/token` から token を読み、環境変数 `RH_API_OFFLINE_TOKEN` にしてバイナリを起動します。token は `.mcp.json` にも `~/.claude.json` にも書きません。`.claude/settings.json` で、`.rhkcs/token` を Read ツールで読めないようにしています（Bash では防げないため、スキルの決まりでも禁止しています）。
- rhkcs-mcp が通信するのは、`sso.redhat.com`（token の交換）と `access.redhat.com`（検索）だけです。
- ビルドに使うリポジトリは `rhkcs.sh` の `REPO_URL` で固定しています。`rhkcs.sh run` は、`PIN` のコミットでビルドしたバイナリだけを起動します（`PIN` を変えたら、`rhkcs.sh build` でビルドし直すまで起動しません）。

## データの置き場所

すべて、リポジトリの中の `.rhkcs/`（Git の管理対象外）に置きます。リポジトリの外には書き込みません。

```text
.rhkcs/
├── src/      ソース（固定したコミット）
├── bin/      rhkcs-mcp と、ビルドしたコミット（rhkcs-mcp.commit）
├── go/       Go のモジュールとビルドのキャッシュ、ビルド中の HOME と一時ファイル（Go のテレメトリなどを ~ に書かないため）
├── log/      MCP サーバーのログ
└── token     offline token（権限 600）
```

## 止める、戻す、消す

- 一時的に止める・戻す: Claude Code の `/mcp` で `rhkcs` を選び、無効（Disable）・有効（Enable）にします。止めている間、ほかのスキルはナレッジベースの MCP を使わずに進みます。
- token の失効: offline token は、30 日に 1 回以上使っていれば失効しません（[Getting started with Red Hat APIs](https://access.redhat.com/articles/3626371)）。失効したら作り直し、別のターミナルで `rhkcs.sh token` を実行し直します。
- 消す: Claude Code を終了してから `.rhkcs/` を消します。`.mcp.json` は共有の設定なので残ります。そのままだと `rhkcs` が接続に失敗した状態で表示されるため、`/mcp` で無効にしておきます。

## 構成

```text
rhkcs-mcp-setup/
├── SKILL.md            # 進め方
└── scripts/rhkcs.sh    # 確認、ビルド、token の保存、動作の確認、新しい版の確認、MCP サーバーの起動（使い方は bash .claude/skills/rhkcs-mcp-setup/scripts/rhkcs.sh で表示）
```
