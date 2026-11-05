# 手順ファイルの書き方

ファイルの中身は、そのまま手順書 runbook.md に載る。形式の誤り（ファイル名、`set -euo pipefail`、namespace、タグの固定、Secret、`oc wait` の timeout など）は lint が検出するので、ここでは lint で判定できないことだけを書く。

```text
runbooks/<name>/
├── spec.md                  # 仕様（タイトル・概要・成功条件・前提条件など）。ひな形の TODO を埋める
├── manifests/               # YAML だけを置く（ここだけを参照・適用に使える）
│   └── 01-xxx.yaml          # oc apply するマニフェスト（1 ファイルに複数オブジェクト可）
├── scripts/
│   ├── 01-xxx.check.sh      # ステップ 01 の確認。期待する状態になったら exit 0
│   ├── 02-yyy.sh            # YAML で書けない作業のときだけ
│   ├── 02-yyy.check.sh
│   └── rollback.sh          # 切り戻し
├── runbook.md               # 生成される手順書（編集しない）
└── run/                     # 検証の記録（編集しない）
```

ステップは `NN-name` で表し、`manifests/NN-name.yaml` か `scripts/NN-name.sh` のどちらか一方と、`scripts/NN-name.check.sh` で構成する。順番は `NN` で決まる。

## spec.md

手順の仕様。runbook.md の冒頭（タイトル・概要・前提条件・パラメータ）と「成功条件 (DoD)」「関連情報」の節になる。

Red Hat 公式ドキュメントの手順モジュールに合わせる。

- タイトルは「〜の作成」「〜のインストール」のような名詞の形。続けて、何をするか・なぜするか（効果）を「〜します」で 1〜2 文書く。
- `## 成功条件 (DoD)` は `- [ ] 状態（確認: NN-name）` のチェックリストで、完了したときに観測できる状態を書く。`NN-name` のステップの check.sh がその状態を確かめる。チェックは付けない（`run` で確認できた項目に、検証結果と手順書で [x] が付く）。
- `## 前提条件` の各項目は、満たしている状態を「〜がある。」「〜できる。」で書く。
- 環境ごとに変える値があれば `## パラメータ` に表で書く（任意）。
- 手順を実行した後にアクセスするもの（Route で公開する Web コンソールなど）があれば、`## アクセス情報` に表で書く（任意。Route を作るときに無いと lint が `[WARN]` を出す）。手順書の冒頭（概要の次）に載る。列は「対象 | URL | ユーザー名 | パスワード」を基本にする。パスワードの列には値を書かず、`CHANGE_ME` と、値を読むコマンド（例: `` `oc extract secret/<名前> -n <namespace> --keys=<キー> --to=-` ``）を書く。

  ```markdown
  | 対象 | URL | ユーザー名 | パスワード |
  | --- | --- | --- | --- |
  | <対象> の Web コンソール | https://<ホスト名> | `<ユーザー名>` | `CHANGE_ME`（`oc extract secret/<名前> -n <namespace> --keys=<キー> --to=-`） |
  ```
- `## 関連情報` に、読んだ章のリンクを載せる。URL は日本語版の `docs.redhat.com/ja/…/openshift_container_platform/<x.y>/html/<guide>/<章>` の形でバージョンを固定する（`cluster` が表示する目次は英語版）。反映した Red Hat ナレッジベースの記事も、`[<題名>](<URL>)` の形で載せる（URL は `get_kcs` が返すもの。solution と article で形が違う）。

## 内容

- 依頼を満たす最小のリソースだけを作る。成功条件に必要な設定やデータは省かない。
- YAML は公式ドキュメントの例に合わせる。違う書き方をしたときは、理由を `# 注記:` に書く。
- イメージは、設定なしで起動して応答するものを選び、`oc image info` で存在・起動コマンド・ポート・アーキテクチャを確かめる。
- CRD を作るもの（Operator など）とその CR は、別のステップにする。
- 本番でそのまま使える形にする（Secret の値は `CHANGE_ME`）。
- クラスタに元からあるリソース（`cluster` という名前の設定、既存の Namespace など）は YAML ステップで変えない（cleanup で削除されるため）。`.sh` ステップで `oc patch` し、rollback.sh で元に戻す。

## コメント

- ステップの 1 行目は `# 〜する`（作業名）。check.sh の 1 行目は「〜ことを確認します」に続く形（例: `# Pod が Ready になっている`）。
- `# 注記:` / `# 重要:`（データ損失・停止のおそれ）/ `# 警告:`（取り返しがつかない）は、手順書の注記になる。検証で分かった待ち時間や挙動も `# 注記:` に書く。Red Hat ナレッジベースの記事を反映したときは、該当するステップの `# 注記:` に、何をなぜするかと記事の ID を書く（例: `# 注記: <バージョン> では <事象> のため、<対処> する（Red Hat ナレッジベース <ID>）`）。記事へのリンクは spec.md の `## 関連情報` に載せる。
- YAML のフィールドの説明は、`key: value # 説明` のようにキーの行末に書く。手順書では「ここでは、以下のようになります。」に続けて「`key: value`: 説明」のリストになる。説明は、その値で何をするかを「〜します。」の文で書く（例: `namespace: openshift-operators # 全 Namespace を対象とする OperatorGroup がある Namespace にインストールします。`）。

## スクリプト

- `set -euo pipefail` より後を、空行で区切った「ブロック」に分ける。手順書では、ブロックごとに「コマンド → 出力例」になる。
  - 1 ブロックには、出力をまとめて見せたいコマンドだけを入れる。1 行目に `# 〜する` で説明を書く。
  - ループ、if、ヒアドキュメントの途中に空行を入れない。
  - シェル変数はブロックをまたいで使える（1 つのスクリプトとして実行される）。
- 人が読んで打てる、短く素直なコマンドにする。
- 出力は判断に必要な要点だけにする。期待値を判定し、表示するだけで成功扱いにしない。出力の整形で元のコマンドの失敗を隠さない。

## check.sh

期待する状態になったかを確かめる（適用したかどうかではない）。公式ドキュメントの Verification を元に、「待つ」ブロックと「状態を表示する」ブロックに分ける。

| 対象 | 待つ | 状態を表示する |
| --- | --- | --- |
| Pod | `oc wait pod -l <ラベル> -n <ns> --for=create --timeout=…` の後に `--for=condition=Ready` | `oc get pods -l <ラベル> -n <ns> -o wide`、`oc logs deployment/<名前> -n <ns> --tail=5` |
| Operator | `oc wait subscription/<名前> -n <ns> --for=jsonpath='{.status.state}'=AtLatestKnown --timeout=…` と CSV の Succeeded | `oc get csv -n <ns> -o custom-columns=NAME:.metadata.name,PHASE:.status.phase`、`oc get pods -n <ns>` |
| Service / Route | `--for=jsonpath=…` で外部 IP などを待つ | `oc get service` / `oc get route` と `curl` の応答 |

- Pod は、先に `--for=create` で作られるのを待つ（いきなり `--for=condition=Ready` だと、Pod が無いときに即失敗する）。
- `oc rollout status` は使わない（進み具合しか出ず、Pod の状態が分からない）。アプリケーションは、起動したことが分かるログも表示する。

## scripts/rollback.sh

- 実行される順序: run（`--cleanup`）と cleanup は、rollback.sh を実行してから、適用した YAML を逆順に削除する（適用したときの内容で削除する）。何も適用していないときは実行されない。
- 対象が無ければ何もしない（途中で失敗したときや cleanup から何度でも実行される）。
- 今回作成・変更したと確認できるものだけを扱う。存在するだけで削除しない（run は、YAML のリソースが既にあると開始しないが、`.sh` ステップで作るものは rollback.sh 自身で確かめる）。
- 戻すもの: `.sh` ステップで作ったもの、変更した既存リソース（元の値に戻す）、削除だけでは戻らないもの（MachineConfig、NNCP など）。
- 順序が必要なものは rollback.sh の中で順に戻す。Operator は、その CR（YAML で作ったものを含む）→ Subscription → CSV → CRD の順に削除する。Operator を先に消すと、finalizer の付いた CR と Namespace の削除が止まる。
- CRD の削除や `--all` での削除のように、この手順で作っていないものまで消える操作の前には、そうしたもの（ほかのユーザーの CR など）が無いことを確かめる。あれば何も削除せずに止める（検証・cleanup は失敗として止まり、ユーザーが判断する）。
  - 確かめるコマンドの結果は変数に入れてから判定する。コマンドが失敗したとき（通信・権限）は、確認できなかったものとして止まるようにする（`2>/dev/null` や `|| true` で失敗を隠さない）。
  - 止めるときは、`echo` で理由と「止めます」を表示してから `false` を実行する（`exit` は使わない。手順書を見て手で実行する人の端末を閉じないため）。
- 削除するかどうかの判断の根拠は、rollback.sh を何度実行しても同じ結果になるものにする（rollback.sh の途中で消えるものを根拠にしない）。途中で失敗しても、cleanup で同じ rollback.sh をもう一度実行するため。
- cleanup は、その時点の rollback.sh を実行する（YAML は適用したときの内容で削除する）。
- 何もしなくてよいときは、ブロックを書かない（案内を表示するだけの処理を書かない）。
