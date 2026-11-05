# must-gather の調べ方と報告書の書き方

`mg.sh` は `bash .claude/skills/openshift-must-gather-analysis/scripts/mg.sh` の略。パスは must-gather のルート（`cluster-scoped-resources` があるディレクトリ）からの相対パス。

## 原因の深掘り

起点から「なぜそうなったか」を 1 段ずつさかのぼる。各段に must-gather の根拠を 1 つ以上付け、根拠が無い段は推定として確度（高・中・低）を付ける。

```text
<起点>（例: Pod が Error で終了した、ClusterOperator が Degraded）
→ なぜ: <直接の理由>（終了メッセージ、ログの最後のエラー、条件の message）
→ なぜ: <その理由が起きた条件>（同じ時刻のほかのコンポーネントのログ、イベント、ノードのログ）
→ なぜ: <さらにその背景>（直前の変更、アップデートの履歴、設定）
→ 原因: <must-gather で確かめられる、いちばん奥の理由>
```

- 時刻を手がかりにする。ある段の時刻の前後に、次の段の候補（アップデート、再起動、エラーの急増、設定の変更）が無いかを見る。まず overview の「最近のアップデート」と重なっていないかを見る。
- 道筋から外れた異常は追わない。原因に着いた、または must-gather にそれ以上の情報が無いところで止める。
- must-gather に無いもの（ノード上のファイル、取得後の状態、取得されていないログ）は、推測で補わず「未確認事項」に回す。

### 確認事項と調査項目

事象を聞いたら、確認事項のファイル（`checklist.md`。`mg.sh plan` で作る）に、まず「この調査で答えること」を確認事項として番号付きで並べ、確認事項ごとに、答えるために調べることを調査項目として並べる。調査中は調査項目をチェックし、最後に報告書（`report.md`）で確認事項ごとに答える。`checklist.md` の節は「事象」「確認事項」「調査項目」で、報告書の「事象」と「確認事項」は `mg.sh report` が `checklist.md` から写す。事象や確認事項は `checklist.md` だけを直し、`mg.sh report` を実行して報告書に写し直す（報告書の側は直接直さない）。

```markdown
## 確認事項

1. <事象> の原因
2. 対処が必要か
3. <問い合わせの質問>（そのまま）

## 調査項目

- [x] 1-1. <対象> が失敗した時刻と、直接の理由（mg.sh pod、mg.sh logs） → 事実 1
- [x] 1-2. その時刻に、<対象が依存するもの> は正常だったか（そのログ、ノードのログ） → 事実 3
- [ ] 1-3. その前後に、変更やアップデートがあったか（overview の最近のアップデート）
- [x] 2-1. 取得時点で、失敗が続いているか（mg.sh pod、mg.sh cond） → 事実 4
- [x] 3-1. <質問に答えるために必要なこと> → 未確認事項（must-gather に情報が無い）
```

- 「事象」には、ユーザーから聞いたこと、ユーザーに確認したこと（分からないと答えた点も）、貼られた出力と must-gather の時点の違いを書く。
- 確認事項は、事象の原因（契機が複数あれば契機ごと）、影響や対処が必要か、問い合わせの質問（そのまま 1 つずつ）にする。
- 調査項目は `確認事項の番号-連番.` で書き、must-gather で「はい / いいえ」か値が分かる問いにして、見る場所を添える。起点を決めたら具体的な名前を入れ、調査中に新しい「なぜ」が出たら、関係する確認事項の項目として足す。事象とつながらないことは項目にしない。
- 結果は「→ 事実 N」か「→ 未確認事項（理由）」で書く。
- 回答は「原因」か「対処案」に「確認事項 N」と書いて示す。
- 進み具合は `mg.sh items` で表示する。

### overview に起点が無い事象

「設定どおりに動かない」「リソースを消しても、外部の装置に残る」のように、異常として現れない事象（設定や運用の問題）は、関係するリソース（StorageClass、PV、Service、Route など）の設定と状態を起点にする。

- 「設定から、通常ならこう動くはず」を示し（「リソースの見方」の担当のコントローラーをたどる）、そこから外れる条件（操作の順番、手作業での変更、外部の障害）を候補として挙げる。must-gather で特定できない候補は、推定として確度を付け、特定する方法を「未確認事項」に書く。
- 関係する Namespace（OpenShift 本体以外の製品など）の Pod とログが must-gather にあるかを `mg.sh ns` で確かめる。

### ユーザーが貼った出力と比べる

問い合わせに `oc get …` の出力が貼られていれば、must-gather と時点が違うことが多い（`AGE` と取得日時から推定する）。名前を比べると、取得後に消えたもの・作られたものが分かり、消えたものは事象の具体例の候補になる。名前が同じものは、状態・容量・紐づき先などの値の違いも見る。時点の違いは `checklist.md` の「事象」に書く。

## コマンド

状態 → 詳細 → ログの順に狭め、各段で次の段の手がかりを 1 つ見つける。

| 見たいもの | コマンド |
| --- | --- |
| 異常の概要、最近のアップデート | `mg.sh overview <case>` |
| Namespace に何が含まれているか（Pod とログの有無） | `mg.sh ns <case> [<ns>]` |
| ClusterOperator・ノード・MCP などの条件（理由と message） | `mg.sh cond <case> cluster-scoped-resources/config.openshift.io/clusteroperators/<name>.yaml` |
| Pod とコンテナの状態、終了の理由、再起動、ログの期間 | `mg.sh pod <case> <ns> <pod>` |
| コンテナのログ（末尾か検索）、取得されていなければ終了メッセージ | `mg.sh logs <case> <ns> <pod> [<container>] ['<regex>'] [--previous]`（コンテナが 1 つなら省略できる） |
| エラーの種類と件数 | `mg.sh errors <case> <ログのファイル>` |
| 時刻ごとの件数（始まった・増えた時刻） | `mg.sh count <case> '<regex>' <ログのファイル> [minute]` |
| イベント | `mg.sh events <case> [<ns> \| -A] ['<regex>']`（全 Namespace を regex で絞るときは `-A` を書く） |
| 根拠の行番号と前後 | `mg.sh grep <case> '<regex>' [<subpath>]`、`mg.sh show <case> <file> <line>` |
| リソースの一覧（PV、StorageClass、CSIDriver、static Pod の revision など） | `omc get <resource> [-n <ns>]`（`-o yaml` には必ず `\| grep` を付ける） |

主なファイル:

| もの | ファイル |
| --- | --- |
| ClusterOperator | `cluster-scoped-resources/config.openshift.io/clusteroperators/<name>.yaml` |
| アップデートの履歴 | `cluster-scoped-resources/config.openshift.io/clusterversions/version.yaml`（`history`） |
| static Pod の revision | `cluster-scoped-resources/operator.openshift.io/<kubeapiservers など>/cluster.yaml`（`nodeStatuses`） |
| ノード | `cluster-scoped-resources/core/nodes/<name>.yaml` |
| PV、StorageClass | `cluster-scoped-resources/core/persistentvolumes/<pv>.yaml`、`cluster-scoped-resources/storage.k8s.io/storageclasses/` |
| Pod、コンテナのログ | `namespaces/<ns>/pods/<pod>/<pod>.yaml`、`namespaces/<ns>/pods/<pod>/<c>/<c>/logs/current.log`（再起動前は `previous.log`） |
| イベント | `namespaces/<ns>/core/events.yaml` |
| ノードのサービスログ | `host_service_logs/masters/kubelet_service.log`、`crio_service.log` など |

### コマンドの書き方

CLAUDE.md の「コマンドの実行」に従ったうえで、次を守る。

- `mg.sh` を優先する。`omc` は一覧を見るときだけ使い、出力を `grep` / `head` / `cut` で絞る。
- must-gather のファイルを `ls`、`cat`、`head` に絶対パスで渡さない。`mg.sh ns` / `grep` / `show` を使う。

## ログの読み方

- エラーは klog 形式の `(^| )[EF][0-9]{4}[ ]` で探す（`E1103` がエラー、`F1103` が致命的エラー）。`error|failed` では取りこぼす。`mg.sh` の regex は、どのサブコマンドでも `grep -E` の書き方で解釈される。
- `mg.sh logs` / `pod` / `errors` / `count` が出すログの期間に、調べたい時刻が入っていなければ、そのログでは確かめられない（「該当なし」でも、事象が無かったことにはならない）。
- Pod のログは、再起動前のものが `previous.log` に 1 世代だけ残る。ノードの再起動やアップデートの後や、イベントが消えた後は、ノードのサービスログ（kubelet）を見る。期間が長く残っていることが多い。

kubelet のログで Pod の動きを追う語:

| 語 | 意味 |
| --- | --- |
| `"SyncLoop ADD" source="api"` / `"SyncLoop DELETE"` | Pod が作られた / 削除された |
| `"SyncLoop REMOVE" source="file"` | static Pod（etcd、kube-apiserver など）のマニフェストが置き換えられ、古い Pod が止められた |
| `Killing container with a grace period` | コンテナを止めた |
| `"SyncLoop (PLEG)"` の `ContainerStarted` / `ContainerDied` | コンテナが起動した / 終了した |
| `"SyncLoop (probe)" probe="readiness" status="ready"` | Pod が Ready になった |
| `request did not complete within requested timeout`、`Client.Timeout exceeded` | API への要求がタイムアウトした |

kubelet のログの行は `Mon DD HH:MM:SS` で始まるので、regex の先頭に時刻を入れて範囲を絞る（例: `'<Mon> <DD> <HH>:<M>.*(SyncLoop (ADD|REMOVE)|Killing container)'` を `mg.sh grep` に、`'<Mon> <DD> <HH>:.*Client.Timeout'` を `mg.sh count … minute` に渡す）。

シングルノード（SNO）では、etcd と kube-apiserver が 1 台ずつしかないため、static Pod が入れ替わる間（アップデートなど）は API が応答しない。

## リソースの見方

### 担当のコントローラーをたどる

OpenShift では、コントローラー（Operator、CSI Driver、kubelet など）が、実際の状態を望む状態（spec や設定）に合わせ続ける。事象の多くは、この合わせ込みが止まったか、ずれたまま残ったもの。次の順にたどる。

| 順 | 見ること | 見る場所の例 |
| --- | --- | --- |
| 1 | 望む状態（何をするはずだったか） | spec、設定のリソース（StorageClass、MachineConfig、Operator の設定のリソース） |
| 2 | 実際の状態（どこまで進んだか） | `status.conditions`、`phase`、Operator が書く進み具合（`nodeStatuses` など） |
| 3 | 担当のコントローラー（誰が合わせるか） | StorageClass の `provisioner`、`ownerReferences`、`managedFields` の `manager`。名前から推測しない |
| 4 | 担当が、その時刻に動いていたか | 担当の Pod の状態、リースの `renewTime`（取得時点で動いていたか） |
| 5 | 担当が何を試み、なぜ失敗したか | 担当の Pod のログ、イベント |

- 状態がずれたまま残るのは、担当が動いていない間に、変更や削除が起きたとき。例えば、担当を先に止めた・uninstall した、クラスタごと消した、finalizer を手で外した、担当を通さずに手で変えた、のような場合。
- finalizer が付いたまま `deletionTimestamp` のあるリソース（Terminating）は、担当が後始末を終えていない。担当のログに理由がある。
- 失敗の記録（Error の Pod、`lastFailedRevision` など）は、回復した後も残る。いまの状態（conditions、現在の revision）と分けて、失敗が続いているのか、過去の 1 回なのかを判断する。

### must-gather で言えないこと

- must-gather は、取得した時点の写し。取得後の操作と状態は分からない。
- クラスタの外の状態は分からない。例えば、ストレージ装置、ロードバランサー、DNS、認証の基盤、ほかのクラスタ。外の装置は、ほかのクラスタやホストと共有されていることがあるので、「このクラスタに無いものは不要」とは言えない。どちらも、確かめる方法を添えて「未確認事項」に回す。
- クラスタが作り直されているかは、ClusterVersion の `history` が 1 件だけか、ClusterVersion の `creationTimestamp` で分かる。作り直すと、前のクラスタが外に作ったもの（Volume、ロードバランサー、DNS のレコードなど）を消す者がいなくなる。

### 種類ごとの要点

| 種類 | 見ること |
| --- | --- |
| static Pod（etcd、kube-apiserver、kube-controller-manager、kube-scheduler） | Operator のリソース（`cluster-scoped-resources/operator.openshift.io/<kubeapiservers など>/cluster.yaml`）の `latestAvailableRevision` と `nodeStatuses`（`currentRevision`、`targetRevision`、`lastFailedRevision`、`lastFailedReason`）。`installer-<N>-<ノード>` Pod の終了の理由。revision を作った契機は、ConfigMap `revision-status-<N>` の `reason`。`lastFailedRevision` が残っていれば、古い revision の ConfigMap や Secret が消されずに残っていないか（revision-pruner への影響はナレッジベースで確かめる） |
| Operator（OLM） | Subscription、InstallPlan、ClusterServiceVersion の `phase` と conditions |
| ノード、MachineConfig | MachineConfigPool の conditions。ノードの annotation `machineconfiguration.openshift.io/state`、`currentConfig`、`desiredConfig`、`reason` |
| ストレージ（CSI） | StorageClass の `provisioner`（担当の CSI Driver）。PV の `persistentVolumeReclaimPolicy`（`Delete` なら、PV と一緒にストレージ側の Volume も消す）と finalizer `external-provisioner.volume.kubernetes.io/finalizer`（ストレージ側の Volume を消し終えるまで PV を残す）。ストレージ側の Volume との対応は、PV の `spec.csi.volumeHandle` と `volumeAttributes` で見る（形は CSI Driver ごとに違う）。`Released`、`Failed`、`Terminating` のまま残る PV は、CSI Driver の `provisioner` コンテナのログを見る |

## 対処案と情報元

- 情報元の優先順: 1. クラスタと同じバージョンの Red Hat 公式ドキュメント、2. Red Hat ナレッジベース、3. バグ報告（OCPBUGS、Bugzilla）と修正されたバージョン、4. アップストリームのドキュメントや Issue。
- 実際に開いて確かめたものだけを書く。URL を推測で作らない。ログインが必要で読めない記事は「内容は確認していない」と書く。
- 検索語には、エラーメッセージのクラスタ固有でない部分とコンポーネント名を使う。クラスタ名、ホスト名、IP アドレスは入れない。見つからなければ語を変えて探す（must-gather で見つけたリソースの項目名や理由（`<項目名>`）でも探す）。
- 検索結果の題名だけで決めず、本文を読んで事象と合うかを確かめる。本文が別の記事や文書を参照していれば、それも読む。
- 情報元が示す原因・影響・条件が、このクラスタに当てはまるかは、must-gather で確かめてから書く。
- Red Hat ナレッジベースの MCP（`mcp__rhkcs__*`）が使えるときは、ナレッジベースは `mcp__rhkcs__search_kcs` で探し、`mcp__rhkcs__get_kcs` で読む（ログインが必要な記事も読める）。
  - 情報元には、ID、題名、`get_kcs` が返す URL と、`get_kcs` で取得したことを書く。
  - article は要約しか読めないので、要約で確かめた範囲だけを書く。
  - 購読者向けの内容なので、引用は根拠に必要な短い文にとどめる。改行を詰めて引用したときは、そう書く。
  - 返るコマンドは空白が抜けているので、そのまま写さない。公式ドキュメントに同じ操作があればその書き方に合わせ、無ければ空白を補って書き直し、そう書く。
- Red Hat ドキュメントの MCP（`mcp__rhdocs__*`）が使えるときは、公式ドキュメントは `mcp__rhdocs__redhat_docs_search` で探し、`mcp__rhdocs__redhat_docs_fetch` で読む（本文は要約されずに返る）。
  - 検索語は英語にし、`OpenShift Container Platform <x.y>` とコンポーネント名を入れる。検索結果の `abstract` は `<…>` が抜けるので、引用は `fetch` で読んだ本文からする。
  - `fetch` の `query` に節の名前を渡すと、その節だけが返る。合う節が無いと先頭の節が返るので、返った見出しを確かめる。
  - 情報元の URL は、`fetch` が返す `url` を書く。
- WebFetch の答えは要約されることがある。報告書に引用する文は、「原文を一字一句そのまま写す」よう指示して取り直す。
- WebFetch は一度に約 10 万字までしか読まない。docs.redhat.com は章のページ（`…/<x.y>/html/<ガイド>/<章>`）を開き、1 回目で節の名前を確かめ、`offset` を進めて引用させる。クラスタのバージョンのページが見つからなければ、古いバージョンの同じ節を見つけ、URL のバージョンを変えて確かめる。
- 同じ症状の事例は、この事象と一致する点と違う点（当てはまらない条件を含む）を書く。
- 対処案は推奨する順に書き、クラスタを変更するものには影響と切り戻しを書く。元に戻せない操作は、対象を誤らないための確認を手順の前に書く。
- 対処が不要なら「何もしない」を推奨し、根拠（いまの状態）を示す。
- 対処案は「確認事項 N への回答」として確認事項ごとに書く（原因を問う確認事項は「原因」の節で答える）。認識を問われたら「合っている / 合っていない / 条件付きで合っている」を先に書く。
- OpenShift 本体以外の製品の操作は、情報元が無ければ推測で書かず「提供元に確認する」と書く。

## 報告書

概要だけを読めば結論と次の行動が分かり、詳細を読めば根拠をたどれるように書く。同じことは 1 か所にだけ書き、ほかの節からは番号（事実 N、情報元 N）で示す。

| 節 | 書くこと |
| --- | --- |
| 概要 | 事象・原因（確度）・影響・推奨する対処を 1〜2 文ずつ |
| 事象、確認事項 | `mg.sh report` が `checklist.md` から写す（直すときは `checklist.md` を直して写し直す） |
| 時系列 | 事象の前後の出来事を時刻の順に表にし、根拠は事実の番号で示す |
| 確認した事実 | 番号付きで、1 項目に 1 つの事実と根拠。推定は書かない |
| 原因 | 原因を問う確認事項への回答として、「なぜ」の連なりと各段の事実の番号。確度とその理由 |
| 対処案 | 確認事項ごとの回答として、推奨する順に、コマンド・影響・切り戻し・情報元の番号 |
| 未確認事項 | 何が / なぜ確認できないか / 確かめるコマンドと、その結果で何が分かるか |
| 情報元 | 番号付きで、題名・URL（`<https://…>` の形）・確かめた内容（引用）・この事象との一致と違い |

- 根拠は `パス:行` と、その行の要点の引用で書く（長い行は「…」で省略してよい）。行番号は `mg.sh` の出力で確かめた値だけを使う。URL や `*`・`_` を含む行は、Markdown として解釈されないよう、引用の中身を `` ` `` で囲む（「`…`」。lint は `` ` `` を除いて比べる）。

  ```markdown
  1. <事実を 1〜2 文で>。
     - 根拠: `namespaces/<ns>/pods/<pod>/<c>/<c>/logs/current.log:120-122` 「<その行の要点>…<続きの要点>」
  ```

- 集計で分かることは、使ったコマンドを書き、代表的な行を根拠に添える。
- 確かめるコマンドは、ユーザーがそのまま実行できる形で書く（例: `oc logs -n <ns> <pod> -c <container> --since=1h`、`oc adm inspect ns/<ns>`、製品の must-gather があれば `oc adm must-gather --image=<製品の must-gather イメージ>`）。名前は must-gather で分かっていれば実際の名前を入れる。コマンドが分からないもの（OpenShift 本体以外の製品の操作など）は、誰に何を確かめるかを書く。
- 時刻は UTC にそろえる（ノードのサービスログが UTC でなければ換算する）。ユーザーが日本時間で話していれば、事象の節に日本時間も添える。
- 書き終えたら `mg.sh lint` で確かめる（確かめる内容は、`mg.sh` を引数なしで実行したときの使い方に書いてある）。
- lint は形と根拠の行しか確かめない。次は自分で見直す: 「なぜ」の各段が事実から言えるか、引用した行がその事実の根拠になっているか、情報元を開いて確かめた内容と書いたことが合っているか、対処案のコマンドがそのまま実行できる書き方か（オプションや `custom-columns` の書き方など）、根拠の無い一般論を断定していないか。
