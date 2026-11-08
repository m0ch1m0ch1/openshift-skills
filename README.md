# openshift-skills

OpenShift の作業を支援する Claude Code 用のスキル集です。

## スキル

| スキル | 使う場面 | やること | できあがるもの |
| --- | --- | --- | --- |
| [openshift-runbook](.claude/skills/openshift-runbook/README.md) | 設定や構築をしたい | 公式ドキュメントをもとに成功条件（DoD）を決め、YAML と確認スクリプトを作る。承認を得てから、接続中のクラスタで適用・確認・切り戻しまで試し、失敗したら原因を調べて直す | 検証済みの手順書（`runbook.md`）。公式ドキュメントの手順の形式で、日本語で書き、検証結果と出力例が付く |
| [openshift-must-gather-analysis](.claude/skills/openshift-must-gather-analysis/README.md) | 起きた事象の原因を知りたい | must-gather を omc で調べ、事象が現れている場所から原因へさかのぼる。調べることを `checklist.md` で示しながら進める。クラスタには接続しない | 原因と対処案の報告書（`report.md`）。事実には must-gather のファイルと行の根拠が、対処案には情報元が付く |
| [openshift-gws-doc-review](.claude/skills/openshift-gws-doc-review/README.md) | 資料（Google ドキュメント・スライド）の技術的な内容を確かめたい | 資料を gws で読み取り、技術的な正しさとサポートの範囲を、公式ドキュメントやナレッジベースと突き合わせる | レビュー結果の Markdown。誤りと懸念点を、場所・内容・根拠の表で書く |

前提条件と使い方は各スキルの README を、できあがるものの例は [sample/](sample/README.md) を参照してください。

## 使い始め方

macOS または Linux で、このリポジトリをクローンし、ルートで Claude Code を起動します。スキルは `/<スキル名>` で実行します（例: `/openshift-runbook`）。

## Red Hat の情報源をつなぐ（任意）

つなぐと、スキルが Red Hat の公式ドキュメントとナレッジベースを直接読みます。つながなくても、どのスキルも使えます（つながっていないときは、つながずに進めてよいかをスキルが確認します）。

| 情報源 | つなぎ方 | できるようになること |
| --- | --- | --- |
| 公式ドキュメント（rhdocs） | `/mcp` で `rhdocs` を選び、Authenticate を選んで、Red Hat アカウントでログインする | ドキュメントを、要約されずに読む |
| ナレッジベース（rhkcs） | `/rhkcs-mcp-setup` を実行する（[README](.claude/skills/rhkcs-mcp-setup/README.md)） | ログインが必要な記事も読む |

- rhdocs は、Red Hat が提供する [MCP server for Red Hat Documentation](https://docs.redhat.com/en/documentation/mcp_server_for_red_hat_documentation/current) です。認証の token は Claude Code が保存し、リポジトリには書きません。
- どちらも、検索語が Red Hat に送られます。スキルは、検索語にクラスタ固有の値（クラスタ名、ホスト名、IP アドレスなど）を入れません。
- 使わないものは、`/mcp` で無効（Disable）にできます。

## 構成

```text
.
├── .claude/
│   ├── settings.json         # 共有の設定。クラスタを変更しない操作は確認なしで実行し、変更する操作は毎回承認を求める
│   └── skills/<skill-name>/  # 各スキル（SKILL.md と README.md など）
├── .github/                  # CI（検査は scripts/check.sh）、Issue と PR のテンプレート
├── .mcp.json                 # MCP サーバー（rhdocs、rhkcs）の登録。token は書いていない
├── CLAUDE.md                 # このリポジトリで作業するときの Claude Code への指示
├── sample/                   # スキルが作るものの例
│
│   # 以下は、スキルが作るもの（Git 管理対象外）
├── runbooks/                 # openshift-runbook の手順
├── must-gather-analyses/     # openshift-must-gather-analysis のケース
├── gws-doc-reviews/          # openshift-gws-doc-review のレビュー結果
└── .rhkcs/                   # rhkcs-mcp-setup が導入した MCP サーバー（token を含む）
```

`.claude/settings.json` の許可は、スキルをこのリポジトリの `.claude/skills/` に置き、リポジトリのルートから実行する前提で書いています。

## 検査

`bash .github/scripts/check.sh` で、CI と同じ検査を手元で実行できます。

## ライセンス

[MIT](LICENSE)。引用した外部の文書（Red Hat のドキュメント、ナレッジベースの記事など）の権利は、それぞれの権利者にあります。
