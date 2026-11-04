# 確認事項: kube-apiserver の installer Pod (installer-10) が Error になっている

- must-gather の取得日時: 2026-11-03 15:57:05.95425792 +0000 UTC（日本時間: 2026-11-04 00:57:05）
- クラスタのバージョン: 4.22.20

## 事象

- ユーザーから: Pod `installer-10-<ノード名>` がエラーになっている。
- ユーザーに確認したが分からない点: Namespace、始まった時刻、エラーメッセージ、直前の変更。
- ユーザーに確認したこと: 2026-11-02 08:13〜09:07 UTC（日本時間 17:13〜18:07）の 4.22.20 へのアップデートは、把握している作業と合っている。エラーにはコンソールで気づいた。ほかに困っていることは無い。
- must-gather では、この Pod は Namespace `openshift-kube-apiserver` にあり、取得時点で `0/1 Error`、AGE は約 1 日（`omc get pods -A`）。

## 確認事項

1. installer-10 Pod が Error になった原因
2. 影響と対処が必要か（kube-apiserver の revision 10 への切り替えは、その後に済んでいるか）

## 調査項目

- [x] 1-1. installer-10 Pod が終了した時刻と、終了の理由（mg.sh pod、mg.sh logs） → 事実 5
- [x] 1-2. installer のログの最後のエラーは何か（終了メッセージ。ログ自体は取得されていない） → 事実 5
- [x] 1-3. その時刻に、installer が依存するもの（kube-apiserver への接続、ノード）は正常だったか（kubelet のログ） → 事実 6
- [x] 1-4. その前後に、アップデートや設定の変更（revision 10 を作った契機）があったか（overview の最近のアップデート、revision-status） → 事実 1、事実 2
- [x] 1-5. API が応答しなかった時刻に、SNO で 1 台だけの etcd が入れ替わっていたか（kubelet のログ、etcd の installer Pod） → 事実 3、事実 4
- [x] 1-6. その時刻の kube-apiserver 自身のログに、etcd への接続エラーがあるか（mg.sh pod） → 未確認事項（ログは 08:59 以降の分しか無い）
- [x] 2-1. 取得時点で、ノードの kube-apiserver の revision は 10 以降になっているか（kubeapiservers/cluster.yaml の nodeStatuses） → 事実 7
- [x] 2-2. 取得時点で、ClusterOperator kube-apiserver は Degraded / Progressing か（mg.sh cond） → 事実 9
- [x] 2-3. installer-10 の後に、次の installer Pod が作られ、成功しているか（omc get pods） → 事実 8
- [x] 2-4. 失敗の記録（lastFailedRevision）が残っていることで、古い revision が消されずに残っていないか（revision-status の ConfigMap） → 事実 10
