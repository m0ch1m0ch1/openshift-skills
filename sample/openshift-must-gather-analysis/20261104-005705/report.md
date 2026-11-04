# 調査報告: kube-apiserver の installer Pod (installer-10) が Error になっている

- 調査日: 2026-11-04
- must-gather: `must-gather-analyses/20261104-005705/must-gather/must-gather.local.<番号>/quay-io-openshift-release-dev-ocp-v4-0-art-dev-sha256-<ダイジェスト>`（取得日時: 2026-11-03 15:57:05.95425792 +0000 UTC）
- クラスタのバージョン: 4.22.20
- 根拠のパスは、must-gather のルート（上記）からの相対パスで、`ファイル:行` の形で示す。
- 時刻は、特に断らない限り UTC（日本時間は +9 時間）。
- 調べたこと（調査項目）と、その結果は `checklist.md` にある。

## 概要

- 事象: Namespace `openshift-kube-apiserver` の installer Pod（installer-10）が Error のまま残っていて、コンソールに表示されている。失敗したのは 2026-11-02 08:15:56 UTC（日本時間 17:15:56）で、4.22.20 へのアップデートの途中だった。
- 原因: アップデートで SNO の 1 台だけの etcd が入れ替わり、kube-apiserver が応答しない間に、installer の API 要求がタイムアウトした（確度: 高）。
- 影響: いまの動作への影響は無い。revision 10 は飛ばされ、その次の revision 11 が 08:20 に入った。取得時点で kube-apiserver は正常（Degraded=False、Progressing=False）。ただし、失敗の記録（`lastFailedRevision: 10`）が残っている間は、古い revision の ConfigMap と Secret が消されずに増えていく。
- 推奨する対処: 当面は何もしない。Error の Pod は過去の失敗の記録として残っているだけ。古い revision が増えてきたら、status の失敗の記録を消す（対処案 2）。

## 事象

- ユーザーから: Pod `installer-10-<ノード名>` がエラーになっている。
- ユーザーに確認したが分からない点: Namespace、始まった時刻、エラーメッセージ、直前の変更。
- ユーザーに確認したこと: 2026-11-02 08:13〜09:07 UTC（日本時間 17:13〜18:07）の 4.22.20 へのアップデートは、把握している作業と合っている。エラーにはコンソールで気づいた。ほかに困っていることは無い。
- must-gather では、この Pod は Namespace `openshift-kube-apiserver` にあり、取得時点で `0/1 Error`、AGE は約 1 日（`omc get pods -A`）。

## 確認事項

1. installer-10 Pod が Error になった原因
2. 影響と対処が必要か（kube-apiserver の revision 10 への切り替えは、その後に済んでいるか）

## 時系列

| 時刻 | 出来事 | 事実 |
| --- | --- | --- |
| 2026-11-02 08:13:51 | 4.22.20 へのアップデートが始まる | 事実 1 |
| 08:14:39 | kube-apiserver の revision 10 が作られる（kube-apiserver-pod が変わった） | 事実 2 |
| 08:14:45 | etcd の installer-2 が動き始める | 事実 3 |
| 08:15:00 | kube-apiserver の revision 11 が作られる（config が変わった） | 事実 2 |
| 08:15:12 | installer-10 が起動する | 事実 5 |
| 08:15:16 | etcd の static Pod が置き換えられ、古い etcd Pod が止められる | 事実 3 |
| 08:15:38〜08:19 | kubelet から API への要求がタイムアウトし続ける | 事実 6 |
| 08:15:56 | installer-10 が API 要求のタイムアウトで終了する（exit code 1）。**事象** | 事実 5 |
| 08:18:52 | 新しい etcd Pod が Ready になる | 事実 4 |
| 08:19:52 | operator が revision 10 を InstallerFailed として記録する | 事実 7 |
| 08:20:12〜08:20:50 | revision 11 の installer-11 が正常に終わる | 事実 8 |
| 08:21:59 | kube-apiserver Pod（revision 11）が Ready になる | 事実 8 |
| 08:23:17 | ClusterOperator kube-apiserver が Progressing=False になる（1 node is at revision 11） | 事実 9 |
| 09:07:17 | 4.22.20 へのアップデートが終わる | 事実 1 |

## 確認した事実

1. 4.22.20 へのアップデートが 2026-11-02 08:13:51 に始まり、09:07:17 に終わった。
   - 根拠: `cluster-scoped-resources/config.openshift.io/clusterversions/version.yaml:190-192` 「completionTime: "2026-11-02T09:07:17Z"」…「startedTime: "2026-11-02T08:13:51Z"」
2. kube-apiserver の revision 10 は 08:14:39 に作られた。理由は「required configmap/kube-apiserver-pod has changed」。revision 11 は 08:15:00 に作られた。理由は「required configmap/config has changed」。
   - 根拠: `namespaces/openshift-kube-apiserver/core/configmaps.yaml:4637-4643` 「reason: required configmap/kube-apiserver-pod has changed」「revision: "10"」「creationTimestamp: "2026-11-02T08:14:39Z"」
   - 根拠: `namespaces/openshift-kube-apiserver/core/configmaps.yaml:4670-4676` 「reason: required configmap/config has changed」「revision: "11"」「creationTimestamp: "2026-11-02T08:15:00Z"」
3. 同じ時間帯に etcd の installer（installer-2）が 08:14:45 から 08:15:30 まで動いた。08:15:16 に etcd の static Pod のマニフェストが置き換えられ、古い etcd Pod が止められた。
   - 根拠: `namespaces/openshift-etcd/pods/installer-2-<ノード名>/installer-2-<ノード名>.yaml:365-367` 「finishedAt: "2026-11-02T08:15:30Z"」「reason: Completed」「startedAt: "2026-11-02T08:14:45Z"」
   - 根拠: `host_service_logs/masters/kubelet_service.log:94520` 「I1102 08:15:16.467003 … "SyncLoop REMOVE" source="file" pods=["openshift-etcd/etcd-<ノード名>"]」
4. 新しい etcd Pod が Ready になったのは 08:18:52 だった。
   - 根拠: `host_service_logs/masters/kubelet_service.log:95029` 「Nov 02 08:18:52 … "SyncLoop (probe)" probe="readiness" status="ready" pod="openshift-etcd/etcd-<ノード名>"」
5. installer-10 の installer コンテナは 08:15:12 に起動し、08:15:56 に exit code 1 で終了した。最後の行は、kube-apiserver（`172.30.0.1:443`）へ installer Pod の一覧を取りに行った要求のタイムアウトによる致命的エラー（`F`）だった。
   - 根拠: `namespaces/openshift-kube-apiserver/pods/installer-10-<ノード名>/installer-10-<ノード名>.yaml:396-397` 「exitCode: 1」「finishedAt: "2026-11-02T08:15:56Z"」、同 `:427` 「startedAt: "2026-11-02T08:15:12Z"」
   - 根拠: `namespaces/openshift-kube-apiserver/pods/installer-10-<ノード名>/installer-10-<ノード名>.yaml:424-425` 「I1102 08:15:42.852746 … Getting installer pods for node …」「`F1102 08:15:56.856324 … Get "https://172.30.0.1:443/api/v1/namespaces/openshift-kube-apiserver/pods?labelSelector=app%3Dinstaller": net/http: request canceled (Client.Timeout exceeded while awaiting headers)`」
6. 同じ時間帯に、kubelet から API への要求も失敗していた。`mg.sh count '<Nov 02 08:1.*(Client.Timeout|request did not complete within requested timeout|connect: connection refused)>' host_service_logs/masters/kubelet_service.log minute` で数えると、08:15 から 08:19 まで毎分 5〜25 件あった。
   - 根拠: `host_service_logs/masters/kubelet_service.log:94613` 「`E1102 08:15:38.769821 … "Failed to update lease" err="Put \"https://api-int.…:6443/apis/coordination.k8s.io/v1/…`」
   - 根拠: `host_service_logs/masters/kubelet_service.log:94690` 「E1102 08:15:50.500001 … "Server rejected event (will not retry!)" err="Timeout: request did not complete within requested timeout - context deadline exceed…」
7. kube-apiserver-operator は、revision 10 を installer の失敗（InstallerFailed）として 08:19:52 に記録した。取得時点では、ノードは revision 11（最新）で動いている。
   - 根拠: `cluster-scoped-resources/operator.openshift.io/kubeapiservers/cluster.yaml:1066-1071` 「latestAvailableRevision: 11」「currentRevision: 11」「lastFailedCount: 1」「lastFailedReason: InstallerFailed」「lastFailedRevision: 10」
   - 根拠: `cluster-scoped-resources/operator.openshift.io/kubeapiservers/cluster.yaml:1101` 「lastFailedTime: "2026-11-02T08:19:52Z"」
8. 続く revision 11 の installer（installer-11）は、08:20:12 に起動し、08:20:50 に正常に終了した。kube-apiserver Pod は 08:21:59 に Ready になった。
   - 根拠: `namespaces/openshift-kube-apiserver/pods/installer-11-<ノード名>/installer-11-<ノード名>.yaml:399-401` 「finishedAt: "2026-11-02T08:20:50Z"」「reason: Completed」「startedAt: "2026-11-02T08:20:12Z"」
   - 根拠: `host_service_logs/masters/kubelet_service.log:95594` 「Nov 02 08:21:59 … "SyncLoop (probe)" probe="readiness" status="ready" pod="openshift-kube-apiserver/kube-apiserver-<ノード名>"」
9. 取得時点で、ClusterOperator kube-apiserver は Degraded=False で、Progressing=False（2026-11-02 08:23:17 から）だった。message は「NodeInstallerProgressing: 1 node is at revision 11」。
   - 根拠: `cluster-scoped-resources/config.openshift.io/clusteroperators/kube-apiserver.yaml:98-106` 「message: 'NodeControllerDegraded: All master nodes are ready'」…「type: Degraded」「lastTransitionTime: "2026-11-02T08:23:17Z"」「message: 'NodeInstallerProgressing: 1 node is at revision 11'」…「type: Progressing」
10. 取得時点で、`openshift-kube-apiserver` には revision 6〜11 の ConfigMap `revision-status-<N>` が残っている（1〜5 は無い）。ノードの記録には `lastFailedRevision: 10` が残っている（事実 7）。
    - 根拠: `namespaces/openshift-kube-apiserver/core/configmaps.yaml:4664` 「name: revision-status-10」、同 `:4697` 「name: revision-status-11」、同 `:4730` 「name: revision-status-6」、同 `:4829` 「name: revision-status-9」（`mg.sh grep '^    name: revision-status-[0-9]+$'` の結果は 6〜11 の 6 件）
    - revision-pruner Pod も、revision 6〜11 の分が作られている（`mg.sh grep 'revision-pruner-[0-9]+-' namespaces/openshift-kube-apiserver/pods` の結果）。

## 原因

確認事項 1 への回答:

```text
installer-10 Pod が Error で終了した（2026-11-02 08:15:56）（事実 5）
→ なぜ: installer が kube-apiserver（172.30.0.1:443）に installer Pod の一覧を取りに行き、応答が無いままタイムアウトした（事実 5）
→ なぜ: 08:15 から 08:19 の間、kube-apiserver が応答していなかった。kubelet の API 要求も同じ時間帯にタイムアウトしている（事実 6）
→ なぜ: 08:15:16 に、アップデートのために etcd の static Pod が入れ替えられ、新しい etcd が Ready になる 08:18:52 まで etcd が使えなかった（事実 3、事実 4）。シングルノード（SNO）では etcd が 1 台しか無いため、この間は kube-apiserver が要求に答えられない（推定。確度: 高）
→ 原因: 4.22.20 へのアップデートの途中で、kube-apiserver の revision 10 の installer と etcd の入れ替えが重なった（事実 1、事実 2、事実 3）
```

- 確度: 高。時刻がそろっている（etcd の入れ替え 08:15:16 → installer の API 要求 08:15:42 → タイムアウト 08:15:56 → etcd が Ready 08:18:52）。同じ時間帯にほかのクライアント（kubelet）も API のタイムアウトを出している。kube-apiserver 自身のログでは確かめられていない（未確認事項 1）。
- SNO のアップデートには API の停止が伴う（情報元 2）。SNO で installer Pod が API に接続できずに Error になる事例も報告されていて、次の installer は成功している（情報元 1）。今回も、operator は失敗を記録したうえで次の revision（11）を入れ、正常に終わっている（事実 7、事実 8）。

## 対処案

確認事項 2 への回答: いまの動作への影響は無く、急ぎの対処は不要。ただし、失敗の記録（`lastFailedRevision: 10`）が残っている間は、古い revision の ConfigMap と Secret が消されずに増えていく（情報元 3）。

1. 何もしない（推奨。当面）
   - 根拠: revision 10 は飛ばされ、その次の revision 11 がノードに入っている（事実 7、事実 8）。取得時点で、ClusterOperator kube-apiserver は Degraded=False、Progressing=False（事実 9）。コンソールに見える Error の Pod は、2026-11-02 08:15 の失敗の記録として残っているだけで、いまの動作には関わらない。SNO のアップデートでは API が止まる時間がある（情報元 2）。
   - いまの状態を確かめるコマンド（クラスタを変更しない）:
     - `oc get co kube-apiserver`（AVAILABLE=True、PROGRESSING=False、DEGRADED=False であること）
     - `oc get kubeapiserver cluster -o jsonpath='{.status.latestAvailableRevision}{"\n"}{.status.nodeStatuses[*].currentRevision}{"\n"}'`（2 つの値が同じであること）
   - 次のアップデートでも、同じように installer Pod が Error で残ることがある。上の 2 つが正常なら、同じく対処は不要。
2. 古い revision が増えてきたら、失敗の記録を消す（任意。クラスタを変更する）
   - 内容: revision-pruner は、`lastFailedRevision` から 5 を引いた revision より後を残し続ける（情報元 3）。取得時点で残っているのは revision 6〜11 の 6 件で（事実 10）、今後 revision が増えると、残る数も増える。情報元 3 の手順では、失敗の記録（`lastFailedCount`、`lastFailedReason`、`lastFailedRevision`、`lastFailedRevisionErrors`、`lastFailedTime`）を status から消すと、次の revision-pruner の実行で古い revision が消される。
   - 手順の前の確認（対象を誤らないため）: `oc get kubeapiserver cluster -o jsonpath='{range .status.nodeStatuses[*]}{.nodeName}{" "}{.currentRevision}{" "}{.lastFailedRevision}{"\n"}{end}'` で、ノードが 1 つだけであること（SNO なので、配列の位置は 0）と、`currentRevision` が `lastFailedRevision` より大きいことを確かめる。
   - コマンド（情報元 3 の手順を、位置 0 で書いたもの。記事の本文は空白が抜けて取得されたため、空白を補っている）:

     ```shell
     oc patch kubeapiserver cluster --subresource=status --type=json -p='[{"op":"remove","path":"/status/nodeStatuses/0/lastFailedCount"},{"op":"remove","path":"/status/nodeStatuses/0/lastFailedReason"},{"op":"remove","path":"/status/nodeStatuses/0/lastFailedRevision"},{"op":"remove","path":"/status/nodeStatuses/0/lastFailedRevisionErrors"},{"op":"remove","path":"/status/nodeStatuses/0/lastFailedTime"}]'
     ```

   - 影響: status の記録だけを消す。kube-apiserver は入れ替わらない。情報元 3 には、すぐに消すために kube-apiserver の入れ替え（`forceRedeploymentReason`）を起こす手順もあるが、SNO では API が止まるため勧めない（次の revision-pruner の実行を待つ）。
   - 切り戻し: 消した記録は戻せない（失敗の内容は、この報告書の事実 5、事実 7 に残っている）。

## 未確認事項

1. 08:15〜08:19 の kube-apiserver 自身のログ（etcd に接続できなかったことを示すエラー）
   - なぜ確認できないか: must-gather の kube-apiserver のログは、ノードの再起動後の 2026-11-02T08:59:29 からの分だけで、previous.log も無い。
   - 確かめる方法: いまは取得できない（コンテナのログは入れ替わりで消えている）。今後のアップデートで同じことが起きたら、その直後に `oc adm inspect ns/openshift-kube-apiserver ns/openshift-etcd` を取る。kube-apiserver のログに etcd への接続エラー（例: `etcdserver: request timed out`、`connection refused` で `:2379` を含む行）があれば、原因の最後の段が確かめられる。

## 情報元

1. Bug 1950019 - installer pod in openshift-kube-controller-manager (or openshift-kube-apiserver) namespace is in error state upon deployment
   - URL: <https://bugzilla.redhat.com/show_bug.cgi?id=1950019>
   - 確かめた内容: SNO（4.8）で、installer Pod が API サーバーからリソースを取りに行って失敗し、Error になる。ログは「dial tcp [fd02::1]:443: connect: connection refused」。後続の installer（retry）は成功し、kube-apiserver は Running になる。「The issue is probably intermittent - doesn't always reproduce.」とされ、WONTFIX で閉じられている。
   - 一致する点: SNO で、kube-apiserver の installer Pod が API に接続できずに Error になり、後続の installer で回復している。
   - 違う点: インストール時の事例で、今回はアップデート中。エラーは `connection refused` で、今回は `Client.Timeout exceeded`（API が応答しなかった）。バージョンが 4.8。
2. OpenShift Container Platform 4.22 Updating clusters「3.1.1. About updating single node OpenShift Container Platform」
   - URL: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/updating_clusters/performing-a-cluster-update>
   - 確かめた内容: 「Updating a single-node OpenShift Container Platform cluster requires downtime and can include an automatic reboot.」「If the update payload does not contain an operating system update or machine configuration changes, a short API outage occurs」
   - 一致する点: クラスタは SNO で、4.22 のアップデートの途中に API が応答しない時間があった（事実 6）。
   - 違う点: ドキュメントは、installer Pod が失敗して残ることには触れていない。
3. Red Hat ナレッジベース Solution 7105585「Old configmap and secret revisions in "openshift-kube-*" namespaces are not deleted by the revision pruner」
   - URL: <https://access.redhat.com/solutions/7105585>
   - 確かめた内容（ナレッジベースの MCP の `get_kcs` で取得）: 根本原因は「The revision-pruner pods works as expected as the pruner will keep `lastFailedRevision - 5` revisions.」（取得した本文の途中の改行は詰めた）。解決策は、失敗した revision の記録がもう関係ないこと（すべてのノードが、より新しい revision にあること）を確かめてから、`kubeapiservers` などの status の `lastFailed` の項目を消す。
   - 一致する点: このクラスタでも、ノードに `lastFailedRevision: 10` が残っていて、すべてのノード（1 台）が、より新しい revision 11 にある（事実 7）。
   - 違う点: 記事の事象（期限切れの証明書を持つ古い `serving-cert-*` の Secret が残る）は、このクラスタでは確かめていない。
4. Red Hat ナレッジベース Solution 7114336「The revision-pruner pods are not created when the lastFailedRevision of any node is less than 6」
   - URL: <https://access.redhat.com/solutions/7114336>
   - 確かめた内容（`get_kcs` で取得）: `lastFailedRevision` が 6 より小さいと revision-pruner Pod が作られない。6 より大きいときは Solution 7105585 を見る、とある。
   - 一致する点: `lastFailedRevision` の記録が revision-pruner に影響する点。
   - 違う点: このクラスタは `lastFailedRevision: 10` で、この記事の条件（6 より小さい）には当たらない。revision-pruner Pod は作られている（事実 10）。
