# MetalLB Operator のインストールと L2 モードの設定

MetalLB Operator をインストールし、L2 モードで LoadBalancer タイプの Service に外部 IP アドレスを割り当てます。これにより、ベアメタル環境でもクラスタ外部から Service に直接アクセスできるようになります。

## 成功条件 (DoD)

- [ ] MetalLB Operator の CSV の PHASE が Succeeded になっている。（確認: 01-operator）
- [ ] controller と speaker の Pod が Running になっている。（確認: 02-metallb）
- [ ] LoadBalancer タイプの Service に IP アドレスプールの外部 IP アドレスが割り当てられ、ノードが layer2 でアナウンスし、作業端末からアクセスすると HTTP 200 が返る。（確認: 04-test-app）

## 前提条件

- cluster-admin ロールを持つユーザーとしてクラスタにアクセスできる。
- クラスタから redhat-operators カタログと quay.io のイメージを取得できる。
- IP アドレスプールに割り当てるアドレスが、ノードと同じ L2 セグメントにあり、ほかの機器で使用されていない。
- 作業端末から IP アドレスプールのアドレスに HTTP でアクセスできる。

## パラメータ

| 項目 | 値 | ファイル |
| --- | --- | --- |
| IP アドレスプール | 192.0.2.150-192.0.2.180 | manifests/03-l2.yaml |
| 動作確認用 Namespace | metallb-test | manifests/04-test-app.yaml |

## 関連情報

- [MetalLB Operator（OpenShift Container Platform 4.22「ネットワーク Operator」）](https://docs.redhat.com/ja/documentation/openshift_container_platform/4.22/html/networking_operators/metallb-operator)
- [MetalLB を使用した負荷分散（OpenShift Container Platform 4.22「Ingress およびロードバランシング」）](https://docs.redhat.com/ja/documentation/openshift_container_platform/4.22/html/ingress_and_load_balancing/load-balancing-with-metallb)
