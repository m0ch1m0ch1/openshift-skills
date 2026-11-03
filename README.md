# openshift-skills

OpenShift の作業を支援する Claude Code 用のスキル集です。

## スキル

| スキル | 使う場面 | やること | できあがるもの |
|---|---|---|---|
| [openshift-runbook](.claude/skills/openshift-runbook/README.md) | 設定や構築をしたい | 公式ドキュメントをもとに YAML と確認スクリプトを作り、承認を得てから、接続中のクラスタで適用から切り戻しまで試す | 検証済みの手順書（`runbook.md`） |
| [openshift-must-gather-analysis](.claude/skills/openshift-must-gather-analysis/README.md) | 起きた事象の原因を知りたい | must-gather を omc で調べ、事象から原因へさかのぼる。クラスタには接続しない | 原因と対処案の報告書（`report.md`。根拠のファイルと行、情報元付き） |

各スキルの前提条件と使い方は、それぞれの README を参照してください。

## 前提条件

- macOS または Linux で Claude Code を使える。
- そのほかの前提条件（`oc` や `omc` など）は、各スキルの README を参照する。

## 使い始め方

このリポジトリをクローンし、ルートで Claude Code を起動します。スキルは `/<スキル名>` で実行します（例: `/openshift-runbook`）。

## 構成

```
.
├── .claude/
│   ├── settings.json         # 共有の設定（権限: 各スキルのクラスタを変更しない操作と、oc・omc の読み取り系コマンドを許可。クラスタを変更する操作は毎回承認を求める。env: omc の設定ファイルをリポジトリ内に置く）
│   └── skills/<skill-name>/  # 各スキル（SKILL.md と README.md など）
├── CLAUDE.md                 # このリポジトリで作業するときの Claude Code への指示
├── runbooks/                 # openshift-runbook が作成した手順（Git 管理対象外）
└── must-gather-analyses/     # openshift-must-gather-analysis のケース（must-gather、checklist.md、report.md。Git 管理対象外）
```

`.claude/settings.json` の許可設定は、スキルをこのリポジトリの `.claude/skills/` に置いて使う前提で書いています。
