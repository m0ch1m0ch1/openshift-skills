# openshift-runbook

OpenShift で実現したいことを伝えると、YAML と確認スクリプトを作り、実クラスタで検証（切り戻し・クリーンアップ込み）してから、手順書 `runbook.md` を作るスキルです。手順書は、Red Hat 公式ドキュメントの手順モジュールの形式で、日本語で書きます。

## 前提条件

- クラスタと同じバージョンの `oc` がインストールされている（確認スクリプトで `oc wait --for=create` を使うため、古い `oc` では動かない）。
- 作成するリソースに応じた権限がある（Operator のインストールなどには cluster-admin が必要）。
- （任意）Red Hat ドキュメントの MCP（rhdocs）。`/mcp` で `rhdocs` を認証すると、公式ドキュメントを要約されずに読みます。
- （任意）Red Hat ナレッジベースの MCP（rhkcs）。[rhkcs-mcp-setup](../rhkcs-mcp-setup/README.md) で導入すると、手順を作るときに、そのバージョンの既知の問題も確かめます。

## 使い方

```text
# 実現したいことを聞いてから始める
/openshift-runbook

# 実現したいことを指定して始める
/openshift-runbook <実現したいこと>
```

例: `/openshift-runbook MetalLB を L2 モードで導入して LoadBalancer Service に外部 IP を割り当てたい`

次の順に進みます。

1. アクセス先のクラスタ（ユーザー、API サーバー、バージョン）を確認する。
2. Red Hat ドキュメントの MCP（rhdocs）とナレッジベースの MCP（rhkcs）が使えるかを確かめる。使えないものがあれば、導入せずに進めてよいかを確認する。
3. 公式ドキュメントを読み（rhdocs が使えればそれで読む。rhkcs が使えれば、ナレッジベースで既知の問題も確かめ）、成功条件（DoD）を決めて、内容でよいかを確認する。
4. YAML と確認スクリプトを作る。
5. 適用してよいかと、検証後にクリーンアップするか作成したリソースを残すかを確認してから、実クラスタで検証する（失敗したら原因を調べて直す。rhkcs が使えれば、エラーメッセージでナレッジベースも探す）。
6. 検証結果と出力例を含む手順書（runbook.md）を生成する。Web コンソールなどアクセスするものがあれば、URL・ユーザー名・パスワードの確かめ方を冒頭の「アクセス情報」に載せる。

リソースを残した場合は、runbook.md の「切り戻し」の手順で元に戻せます。

## 構成

```text
openshift-runbook/
├── SKILL.md                      # 進め方
├── references/writing-guide.md   # 手順ファイルの書き方（lint で判定できないこと）
├── templates/                    # 新しい手順のひな形
└── scripts/runbook.sh            # 処理の本体（スキルが内部で使う。クラスタの確認・ひな形・lint・適用内容の表示・検証・クリーンアップ・手順書の生成）
```

作成した手順は、Git リポジトリのルートの `runbooks/<name>/` に置かれます（環境変数 `RUNBOOK_DIR` で変えられます）。

```text
runbooks/<name>/
├── spec.md                       # 仕様（概要・成功条件・前提条件・パラメータ・アクセス情報）
├── manifests/NN-*.yaml           # 適用する YAML（YAML だけを置く）
├── scripts/                      # 確認スクリプト、YAML で書けない作業、切り戻し (rollback.sh)
├── runbook.md                    # 生成された手順書
└── run/                          # 実クラスタでの検証結果とログ
```

スクリプトの使い方は `bash .claude/skills/openshift-runbook/scripts/runbook.sh` で表示されます。
