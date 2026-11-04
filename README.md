# openshift-skills

OpenShift の作業を支援する Claude Code 用のスキル集です。

## スキル

| スキル | 使う場面 | やること | できあがるもの |
|---|---|---|---|
| [openshift-runbook](.claude/skills/openshift-runbook/README.md) | 設定や構築をしたい | 公式ドキュメントをもとに YAML と確認スクリプトを作り、承認を得てから、接続中のクラスタで適用から切り戻しまで試す | 検証済みの手順書（`runbook.md`） |
| [openshift-must-gather-analysis](.claude/skills/openshift-must-gather-analysis/README.md) | 起きた事象の原因を知りたい | must-gather を omc で調べ、事象から原因へさかのぼる。クラスタには接続しない | 原因と対処案の報告書（`report.md`。根拠のファイルと行、情報元付き） |
| [rhkcs-mcp-setup](.claude/skills/rhkcs-mcp-setup/README.md)（任意） | 上の 2 つのスキルで、Red Hat ナレッジベースも参照したい | ナレッジベースを検索する MCP サーバーを導入し、Red Hat の token を設定する | Claude Code から使えるナレッジベースの検索ツール |

各スキルの前提条件と使い方は、それぞれの README を参照してください。

## Red Hat ナレッジベースの利用（任意）

`/rhkcs-mcp-setup` で導入すると、ログインが必要なナレッジベースの記事も、スキルが読めるようになります。

| スキル | ナレッジベースを使う場面 |
|---|---|
| openshift-runbook | 手順を作るときに、そのバージョンの既知の問題を確かめる。検証が失敗したときに、エラーメッセージで探す |
| openshift-must-gather-analysis | 対処案の情報元を確かめる |

導入していなくても、どちらのスキルもそのまま使えます（ナレッジベースを使わずに進みます）。導入には、Go と git と、Red Hat アカウントの offline token が必要です。

## 前提条件

- macOS または Linux で Claude Code を使える。
- そのほかの前提条件（`oc` や `omc` など）は、各スキルの README を参照する。

## 使い始め方

このリポジトリをクローンし、ルートで Claude Code を起動します。スキルは `/<スキル名>` で実行します（例: `/openshift-runbook`）。

## 構成

```
.
├── .claude/
│   ├── settings.json         # 共有の設定（下を参照）
│   └── skills/<skill-name>/  # 各スキル（SKILL.md と README.md など）
├── .mcp.json                 # MCP サーバーの登録（下を参照）
├── CLAUDE.md                 # このリポジトリで作業するときの Claude Code への指示
│
│   # 以下は、スキルが作るもの（Git 管理対象外）
├── runbooks/                 # openshift-runbook の手順
├── must-gather-analyses/     # openshift-must-gather-analysis のケース（must-gather、checklist.md、report.md）
└── .rhkcs/                   # rhkcs-mcp-setup が導入した MCP サーバー（ソース、バイナリ、token など）
```

共有の設定:

- `.claude/settings.json`
  - クラスタを変更しない操作（各スキルの確認系のコマンド、`oc`・`omc` の読み取り、ナレッジベースの MCP のツール）は、確認なしで実行できます。クラスタを変更する操作は、毎回承認を求めます。
  - omc の設定ファイルをリポジトリの中に置きます。
  - token のファイル（`.rhkcs/token`）を、Claude Code の Read ツールで読めないようにしています（Bash のコマンドまでは防げないため、スキルの決まりでも禁止しています）。
  - スキルをこのリポジトリの `.claude/skills/` に置いて使う前提で書いています。
- `.mcp.json`: ナレッジベースの MCP サーバー（rhkcs）を登録しています。token は書いていません。初めて使うときに、Claude Code が承認を求めます。導入していない場合は、`/mcp` で無効にできます。
