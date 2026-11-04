# Route を使用した nginx の公開

nginx を 1 つの Pod で実行し、Service と Route（edge TLS 終端）を使用してクラスタ外部に HTTPS で公開します。

## 成功条件 (DoD)

- [ ] nginx の Pod が Ready になり、起動ログが出力されている。（確認: 02-deployment）
- [ ] Route の URL に HTTPS でアクセスすると HTTP 200 が返る。（確認: 04-route）

## 前提条件

- Namespace を作成する権限を持つユーザーとしてクラスタにアクセスできる。
- クラスタから quay.io のイメージを取得できる。

## パラメータ

| 項目 | 値 | ファイル |
|---|---|---|
| Namespace | hello-route | 全ファイル |
| イメージ | quay.io/nginx/nginx-unprivileged:1.27 | manifests/02-deployment.yaml |

## 関連情報

- [ルート（OpenShift Container Platform 4.22「Ingress およびロードバランシング」）](https://docs.redhat.com/ja/documentation/openshift_container_platform/4.22/html/ingress_and_load_balancing/routes)
