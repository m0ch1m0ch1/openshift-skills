# openshift-skills

OpenShift で実現したいことを伝えると、YAML と確認スクリプトを作成し、実クラスタで検証（切り戻し・クリーンアップ込み）してから手順書 `runbook.md` を生成する Claude Code 用のスキルです。

## 前提条件

- クラスタと同じバージョンの `oc` がインストールされている（確認スクリプトで `oc wait --for=create` を使うため、古い `oc` では動かない）。
- 作業対象のクラスタに、kubeconfig を使って `oc login` 済みである。
- 作成するリソースに応じた権限がある（Operator のインストールなどには cluster-admin が必要）。
- macOS または Linux の bash で実行する。手順書（runbook.md）は日本語で生成される。

## 使い方

このリポジトリをクローンし、ルートで Claude Code を起動して実行します。

```
/openshift-runbook                     # 手順の一覧（検証結果・リソースの状態）を表示し、次に何をするかを聞く
/openshift-runbook <実現したいこと>    # 新しい手順を作り、実クラスタで検証して runbook.md を生成する
/openshift-runbook plan <name>         # 成功条件と、作成するリソースを表示する（クラスタは変更しない）
/openshift-runbook run <name>          # 実クラスタで再検証し、runbook.md を更新する
/openshift-runbook cleanup <name>      # 検証で残したリソースを元に戻す
/openshift-runbook doc <name>          # runbook.md を作り直す（クラスタに接続しない）
```

例: `/openshift-runbook MetalLB を L2 モードで導入して LoadBalancer Service に外部 IP を割り当てたい`

- 作業の前に、アクセス先のクラスタ（ユーザー、API サーバー、バージョン）を確認します。
- 検証の前に、適用してよいかと、検証後にクリーンアップするか作成したリソースを残すかを確認します。

## 構成

```
.
├── .claude/
│   ├── settings.json                     # 共有の権限設定（クラスタを変更しないスクリプトのコマンドと、oc の読み取り系コマンドを許可。run と cleanup は毎回承認を求める）
│   └── skills/openshift-runbook/         # スキル本体
│       ├── SKILL.md                      # 進め方
│       ├── references/writing-guide.md   # 手順ファイルの書き方（lint で判定できないこと）
│       ├── templates/                    # 新しい手順のひな形
│       └── scripts/runbook.sh            # 処理の本体（一覧・ひな形・lint・適用内容の表示・検証・クリーンアップ・手順書の生成）
└── runbooks/<name>/                      # 作成した手順（Git 管理対象外）
    ├── spec.md                           # 仕様（概要・成功条件・前提条件・パラメータ）
    ├── manifests/NN-*.yaml               # 適用する YAML（YAML だけを置く）
    ├── scripts/                          # 確認スクリプト、YAML で書けない作業、切り戻し (rollback.sh)
    ├── runbook.md                        # 生成された手順書
    └── run/                              # 実クラスタでの検証結果とログ
```

手順は Git リポジトリのルートの `runbooks/` に置かれます（環境変数 `RUNBOOK_DIR` で変えられます）。`.claude/settings.json` の許可設定は、スキルをこのリポジトリの `.claude/skills/` に置いて使う前提で書いています。スクリプト単体の使い方は `bash .claude/skills/openshift-runbook/scripts/runbook.sh` で表示されます。
