# openshift-skills

OpenShift の作業を支援する Claude Code 用のスキル集です。

## スキル

| スキル | 内容 |
|---|---|
| [openshift-runbook](.claude/skills/openshift-runbook/README.md) | 実現したいことを聞き、YAML と確認スクリプトを作って実クラスタで検証し（切り戻し・クリーンアップ込み）、手順書 runbook.md を生成する |

各スキルの前提条件と使い方は、それぞれの README を参照してください。

## 前提条件

- macOS または Linux で Claude Code を使える。
- `oc` がインストールされ、作業対象のクラスタに kubeconfig を使って `oc login` 済みである。

## 使い始め方

このリポジトリをクローンし、ルートで Claude Code を起動します。スキルは `/<スキル名>` で実行します（例: `/openshift-runbook`）。

## 構成

```
.
├── .claude/
│   ├── settings.json         # 共有の権限設定（各スキルのクラスタを変更しない操作と、oc の読み取り系コマンドを許可。クラスタを変更する操作は毎回承認を求める）
│   └── skills/<skill-name>/  # 各スキル（SKILL.md と README.md など）
└── runbooks/                 # openshift-runbook が作成した手順（Git 管理対象外）
```

`.claude/settings.json` の許可設定は、スキルをこのリポジトリの `.claude/skills/` に置いて使う前提で書いています。
