# MetalLB Operator のインストールと L2 モードの設定

MetalLB Operator をインストールし、L2 モードで LoadBalancer タイプの Service に外部 IP アドレスを割り当てます。これにより、ベアメタル環境でもクラスタ外部から Service に直接アクセスできるようになります。

> **注記**
>
> この手順は 2026-11-08 20:16、OpenShift 4.22.21 で検証済みです（詳細: run/result.md）。

## 前提条件

- cluster-admin ロールを持つユーザーとしてクラスタにアクセスできる。
- クラスタから redhat-operators カタログと quay.io のイメージを取得できる。
- IP アドレスプールに割り当てるアドレスが、ノードと同じ L2 セグメントにあり、ほかの機器で使用されていない。
- 作業端末から IP アドレスプールのアドレスに HTTP でアクセスできる。
- この手順で作成するリソースが、まだ存在しない。存在する場合は実行しない（切り戻しで消えるため）。
- manifests/ と scripts/ (rollback.sh を含む) をこの手順書と同じディレクトリにあらかじめ配置し、コマンドはそのディレクトリで実行する。

## パラメータ

| 項目 | 値 | ファイル |
| --- | --- | --- |
| IP アドレスプール | 192.0.2.150-192.0.2.180 | manifests/03-l2.yaml |
| 動作確認用 Namespace | metallb-test | manifests/04-test-app.yaml |

## 手順

### 事前確認

次のコマンドを実行して、manifests/ のすべての YAML の対象リソースについて、何も表示されないことを確認します。リソース名が表示された場合は、既存リソースがあるため中止します。no matches for kind / resource mapping not found（CRD がまだ登録されていない）は、そのリソースがまだ存在しないものとして続行します。それ以外のエラー（権限・通信など）で確認できない場合は中止し、以降の手順へ進まないでください。

```terminal
$ oc get -f manifests/01-operator.yaml --ignore-not-found -o name
$ oc get -f manifests/02-metallb.yaml --ignore-not-found -o name
$ oc get -f manifests/03-l2.yaml --ignore-not-found -o name
$ oc get -f manifests/04-test-app.yaml --ignore-not-found -o name
```

### 作業

1. MetalLB Operator をインストールします。

   > **注記**
   >
   > インストールが完了するまで、通常 1〜2 分かかります。

   1. あらかじめ配置した `manifests/01-operator.yaml` ファイルの内容が、次の YAML と一致することを確認します。

      ```yaml
      apiVersion: v1
      kind: Namespace
      metadata:
        name: metallb-system
      ---
      apiVersion: operators.coreos.com/v1
      kind: OperatorGroup
      metadata:
        name: metallb-operator
        namespace: metallb-system
      ---
      apiVersion: operators.coreos.com/v1alpha1
      kind: Subscription
      metadata:
        name: metallb-operator-sub
        namespace: metallb-system
      spec:
        channel: stable
        name: metallb-operator
        source: redhat-operators
        sourceNamespace: openshift-marketplace
      ```

      ここでは、以下のようになります。

      - `channel: stable`: Operator の更新チャネルを指定します。
      - `source: redhat-operators`: redhat-operators を指定する必要があります。

   2. 次のコマンドを実行して、マニフェストを適用します。

      ```terminal
      $ oc apply -f manifests/01-operator.yaml
      ```

      **出力例**

      ```terminal
      namespace/metallb-system created
      operatorgroup.operators.coreos.com/metallb-operator created
      subscription.operators.coreos.com/metallb-operator-sub created
      ```

   3. CSV の PHASE が Succeeded になり、InstallPlan が承認されていることを確認します。

      1. 次のコマンドを実行して、Operator のインストールが完了するまで待機します。

         ```terminal
         $ oc wait subscriptions.operators.coreos.com/metallb-operator-sub -n metallb-system --for=jsonpath='{.status.state}'=AtLatestKnown --timeout=300s
         $ csv=$(oc get subscriptions.operators.coreos.com/metallb-operator-sub -n metallb-system -o jsonpath='{.status.installedCSV}')
         $ oc wait csv/"$csv" -n metallb-system --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s
         ```

         **出力例**

         ```terminal
         subscription.operators.coreos.com/metallb-operator-sub condition met
         clusterserviceversion.operators.coreos.com/metallb-operator.v4.22.0-202611031655 condition met
         ```

      2. 次のコマンドを実行して、CSV の PHASE が Succeeded であることを確認します。

         ```terminal
         $ oc get csv -n metallb-system -o custom-columns=Name:.metadata.name,Phase:.status.phase
         ```

         **出力例**

         ```terminal
         Name                                    Phase
         metallb-operator.v4.22.0-202611031655   Succeeded
         ```

      3. 次のコマンドを実行して、InstallPlan が承認されていることを確認します。

         ```terminal
         $ oc get installplan -n metallb-system
         ```

         **出力例**

         ```terminal
         NAME            CSV                                     APPROVAL    APPROVED
         install-slg84   metallb-operator.v4.22.0-202611031655   Automatic   true
         ```

2. MetalLB のインスタンスを作成します。

   1. あらかじめ配置した `manifests/02-metallb.yaml` ファイルの内容が、次の YAML と一致することを確認します。

      ```yaml
      apiVersion: metallb.io/v1beta1
      kind: MetalLB
      metadata:
        name: metallb
        namespace: metallb-system
      ```

   2. 次のコマンドを実行して、マニフェストを適用します。

      ```terminal
      $ oc apply -f manifests/02-metallb.yaml
      ```

      **出力例**

      ```terminal
      metallb.metallb.io/metallb created
      ```

   3. controller と speaker の Pod が Running になっていることを確認します。

      > **注記**
      >
      > speaker の Pod の数は、クラスタのノード数と同じになります。シングルノードの場合は 1 つです。

      1. 次のコマンドを実行して、controller と speaker の Pod が Ready になるまで待機します。

         ```terminal
         $ oc wait pod -l component=controller -n metallb-system --for=create --timeout=180s
         $ oc wait pod -l component=controller -n metallb-system --for=condition=Ready --timeout=300s
         $ oc wait pod -l component=speaker -n metallb-system --for=create --timeout=180s
         $ oc wait pod -l component=speaker -n metallb-system --for=condition=Ready --timeout=300s
         ```

         **出力例**

         ```terminal
         pod/controller-6c6b7c9c86-rsg62 condition met
         pod/controller-6c6b7c9c86-rsg62 condition met
         pod/speaker-kzjt4 condition met
         pod/speaker-kzjt4 condition met
         ```

      2. 次のコマンドを実行して、controller の Deployment が AVAILABLE になっていることを確認します。

         ```terminal
         $ oc get deployment controller -n metallb-system
         ```

         **出力例**

         ```terminal
         NAME         READY   UP-TO-DATE   AVAILABLE   AGE
         controller   1/1     1            1           13s
         ```

      3. 次のコマンドを実行して、speaker の DaemonSet の READY がノード数と同じであることを確認します。

         ```terminal
         $ oc get daemonset speaker -n metallb-system
         ```

         **出力例**

         ```terminal
         NAME      DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
         speaker   1         1         1       1            1           kubernetes.io/os=linux   13s
         ```

      4. 次のコマンドを実行して、Pod の STATUS が Running であることを確認します。

         ```terminal
         $ oc get pods -n metallb-system -l 'component in (controller,speaker)' -o wide
         ```

         **出力例**

         ```terminal
         NAME                          READY   STATUS    RESTARTS   AGE   IP              NODE                          NOMINATED NODE   READINESS GATES
         controller-6c6b7c9c86-rsg62   2/2     Running   0          14s   10.128.0.13     <ノード名>                    <none>           <none>
         speaker-kzjt4                 2/2     Running   0          14s   192.0.2.83      <ノード名>                    <none>           <none>
         ```

3. IP アドレスプールと L2 アドバタイズメントを作成します。

   1. あらかじめ配置した `manifests/03-l2.yaml` ファイルの内容が、次の YAML と一致することを確認します。

      ```yaml
      apiVersion: metallb.io/v1beta1
      kind: IPAddressPool
      metadata:
        name: l2-pool
        namespace: metallb-system
      spec:
        addresses:
          - 192.0.2.150-192.0.2.180
      ---
      apiVersion: metallb.io/v1beta1
      kind: L2Advertisement
      metadata:
        name: l2-adv
        namespace: metallb-system
      spec:
        ipAddressPools:
          - l2-pool
      ```

      ここでは、以下のようになります。

      - `ipAddressPools`: L2 モードでアドバタイズする IP アドレスプールを指定します。

   2. 次のコマンドを実行して、マニフェストを適用します。

      ```terminal
      $ oc apply -f manifests/03-l2.yaml
      ```

      **出力例**

      ```terminal
      ipaddresspool.metallb.io/l2-pool created
      l2advertisement.metallb.io/l2-adv created
      ```

   3. IP アドレスプールと L2 アドバタイズメントが作成されていることを確認します。

      1. 次のコマンドを実行して、IP アドレスプールが作成されていることを確認します。

         ```terminal
         $ oc get ipaddresspool -n metallb-system
         ```

         **出力例**

         ```terminal
         NAME      AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
         l2-pool   true          false             ["192.0.2.150-192.0.2.180"]
         ```

      2. 次のコマンドを実行して、L2 アドバタイズメントが作成されていることを確認します。

         ```terminal
         $ oc get l2advertisement -n metallb-system
         ```

         **出力例**

         ```terminal
         NAME     IPADDRESSPOOLS   IPADDRESSPOOL SELECTORS   INTERFACES
         l2-adv   ["l2-pool"]                                
         ```

4. 動作確認用のアプリケーションを LoadBalancer タイプの Service で公開します。

   1. あらかじめ配置した `manifests/04-test-app.yaml` ファイルの内容が、次の YAML と一致することを確認します。

      ```yaml
      apiVersion: v1
      kind: Namespace
      metadata:
        name: metallb-test
      ---
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: hello
        namespace: metallb-test
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: hello
        template:
          metadata:
            labels:
              app: hello
          spec:
            containers:
              - name: nginx
                image: quay.io/nginx/nginx-unprivileged:1.27
                ports:
                  - containerPort: 8080
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: hello
        namespace: metallb-test
      spec:
        type: LoadBalancer
        selector:
          app: hello
        ports:
          - name: http
            port: 8080
            targetPort: 8080
      ```

      ここでは、以下のようになります。

      - `type: LoadBalancer`: MetalLB が IP アドレスプールから外部 IP アドレスを割り当てます。

   2. 次のコマンドを実行して、マニフェストを適用します。

      ```terminal
      $ oc apply -f manifests/04-test-app.yaml
      ```

      **出力例**

      ```terminal
      namespace/metallb-test created
      deployment.apps/hello created
      service/hello created
      ```

## 検証

- Service に外部 IP アドレスが割り当てられ、ノードが L2 モードでアナウンスし、作業端末からアクセスすると 200 が返ることを確認します。

   1. 次のコマンドを実行して、Pod が Ready になるまで待機します。

      ```terminal
      $ oc wait pod -l app=hello -n metallb-test --for=create --timeout=120s
      $ oc wait pod -l app=hello -n metallb-test --for=condition=Ready --timeout=180s
      ```

      **出力例**

      ```terminal
      pod/hello-656fb99587-l5vxp condition met
      pod/hello-656fb99587-l5vxp condition met
      ```

   2. 次のコマンドを実行して、Pod の STATUS が Running であることを確認します。

      ```terminal
      $ oc get pods -l app=hello -n metallb-test -o wide
      ```

      **出力例**

      ```terminal
      NAME                     READY   STATUS    RESTARTS   AGE   IP            NODE                          NOMINATED NODE   READINESS GATES
      hello-656fb99587-l5vxp   1/1     Running   0          20s   10.128.0.14   <ノード名>                    <none>           <none>
      ```

   3. 次のコマンドを実行して、nginx が起動したことをログで確認します。

      ```terminal
      $ oc logs deployment/hello -n metallb-test --tail=3
      ```

      **出力例**

      ```terminal
      2026/11/08 11:15:48 [notice] 1#1: start worker process 34
      2026/11/08 11:15:48 [notice] 1#1: start worker process 35
      2026/11/08 11:15:48 [notice] 1#1: start worker process 36
      ```

   4. 次のコマンドを実行して、Service に外部 IP アドレスが割り当てられるまで待機します。

      ```terminal
      $ oc wait service/hello -n metallb-test --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' --timeout=120s
      ```

      **出力例**

      ```terminal
      service/hello condition met
      ```

   5. 次のコマンドを実行して、EXTERNAL-IP に IP アドレスプールのアドレスが表示されることを確認します。

      ```terminal
      $ oc get service hello -n metallb-test
      ```

      **出力例**

      ```terminal
      NAME    TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)          AGE
      hello   LoadBalancer   172.30.96.181   192.0.2.150      8080:31356/TCP   21s
      ```

   6. 次のコマンドを実行して、作業端末から外部 IP アドレスにアクセスし、200 が返ることを確認します。

      ```terminal
      $ ip=$(oc get service hello -n metallb-test -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
      $ curl -s --retry 10 --retry-delay 3 --retry-all-errors --fail -o /dev/null -w "http://$ip:8080/ -> %{http_code}\n" "http://$ip:8080/"
      ```

      **出力例**

      ```terminal
      http://192.0.2.150:8080/ -> 200
      ```

   7. 次のコマンドを実行して、IP アドレスが割り当てられ、ノードが layer2 でアナウンスしていることをイベントで確認します。

      ```terminal
      $ oc get events -n metallb-test --field-selector involvedObject.kind=Service,involvedObject.name=hello -o custom-columns=REASON:.reason,FROM:.source.component,MESSAGE:.message
      ```

      **出力例**

      ```terminal
      REASON         FROM                 MESSAGE
      IPAllocated    metallb-controller   Assigned IP ["192.0.2.150"]
      nodeAssigned   metallb-speaker      announcing from node "<ノード名>" with protocol "layer2"
      ```

## 成功条件 (DoD)

2026-11-08 20:16 の検証で確認できた成功条件に [x] を付けています。

- [x] MetalLB Operator の CSV の PHASE が Succeeded になっている。（手順 1）
- [x] controller と speaker の Pod が Running になっている。（手順 2）
- [x] LoadBalancer タイプの Service に IP アドレスプールの外部 IP アドレスが割り当てられ、ノードが layer2 でアナウンスし、作業端末からアクセスすると HTTP 200 が返る。（検証）

成功条件をすべて満たしています（3/3）。

## 切り戻し

この手順で作成・変更したものを削除し、手順を実行する前の状態に戻します。

> **重要**
>
> 切り戻すと、MetalLB が割り当てた外部 IP アドレスを使用しているすべての Service にアクセスできなくなります。この手順で作成していない MetalLB のリソースがある場合は、何も削除せずに止まります。

> **注記**
>
> Operator を先に削除すると MetalLB のリソースの削除が終わらなくなるため、MetalLB のリソースを先に削除してから、Operator の Subscription、CSV、CRD の順に削除します。Namespace などのその他のリソースは、この後に YAML の逆順で削除します。

> **注記**
>
> frrk8s.metallb.io の CRD は OpenShift の Network Operator が管理しているため、削除しません。

### 手順

1. 次のコマンドを実行して、切り戻しスクリプトを実行します。

   ```terminal
   $ bash scripts/rollback.sh
   ```

   「止めます」と表示された場合や、コマンドが失敗した場合は、次の YAML の削除に進まないでください。

   **出力例**

   ```terminal
   l2advertisement.metallb.io "l2-adv" deleted from metallb-system namespace
   ipaddresspool.metallb.io "l2-pool" deleted from metallb-system namespace
   metallb.metallb.io "metallb" deleted from metallb-system namespace
   subscription.operators.coreos.com "metallb-operator-sub" deleted from metallb-system namespace
   clusterserviceversion.operators.coreos.com "metallb-operator.v4.22.0-202611031655" deleted from metallb-system namespace
   customresourcedefinition.apiextensions.k8s.io "bfdprofiles.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "bgpadvertisements.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "bgppeers.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "communities.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "configurationstates.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "ipaddresspools.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "l2advertisements.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "metallbs.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "servicebgpstatuses.metallb.io" deleted
   customresourcedefinition.apiextensions.k8s.io "servicel2statuses.metallb.io" deleted
   ```

   **参考: scripts/rollback.sh の内容**

   ```bash
   #!/usr/bin/env bash
   # MetalLB の設定と Operator を削除する
   # 重要: 切り戻すと、MetalLB が割り当てた外部 IP アドレスを使用しているすべての Service にアクセスできなくなります。この手順で作成していない MetalLB のリソースがある場合は、何も削除せずに止まります。
   # 注記: Operator を先に削除すると MetalLB のリソースの削除が終わらなくなるため、MetalLB のリソースを先に削除してから、Operator の Subscription、CSV、CRD の順に削除します。Namespace などのその他のリソースは、この後に YAML の逆順で削除します。
   # 注記: frrk8s.metallb.io の CRD は OpenShift の Network Operator が管理しているため、削除しません。
   set -euo pipefail
   
   # この手順で作成していない MetalLB のリソースが無いことを確認する
   if oc get crd metallbs.metallb.io >/dev/null 2>&1; then
     all=$(oc get metallb,ipaddresspool,l2advertisement,bgppeer,bgpadvertisement,bfdprofile,community --all-namespaces --no-headers -o custom-columns=KIND:.kind,NS:.metadata.namespace,NAME:.metadata.name)
     others=$(printf '%s\n' "$all" | grep -vE '^(MetalLB +metallb-system +metallb|IPAddressPool +metallb-system +l2-pool|L2Advertisement +metallb-system +l2-adv)$' | grep . || true)
     if [ -n "$others" ]; then
       echo "この手順で作成していない MetalLB のリソースがあるため、止めます:"
       echo "$others"
       false
     fi
   fi
   
   # この手順で作成した MetalLB のリソースを削除する
   if oc get crd metallbs.metallb.io >/dev/null 2>&1; then
     oc delete l2advertisement l2-adv -n metallb-system --ignore-not-found --timeout=300s
     oc delete ipaddresspool l2-pool -n metallb-system --ignore-not-found --timeout=300s
     oc delete metallb metallb -n metallb-system --ignore-not-found --timeout=300s
   fi
   
   # MetalLB Operator の Subscription と CSV を削除する
   oc delete subscriptions.operators.coreos.com metallb-operator-sub -n metallb-system --ignore-not-found
   oc delete csv -n metallb-system -l operators.coreos.com/metallb-operator.metallb-system --ignore-not-found
   
   # MetalLB Operator の CRD を削除する
   crds=$(oc get crd -l operators.coreos.com/metallb-operator.metallb-system -o name | grep -v '\.frrk8s\.metallb\.io$' || true)
   if [ -n "$crds" ]; then
     oc delete $crds
   fi
   ```

2. 次のコマンドを実行して、作成したリソースを、適用したときと逆の順序で削除します。

   ```terminal
   $ oc delete -f manifests/04-test-app.yaml --ignore-not-found
   $ oc delete -f manifests/03-l2.yaml --ignore-not-found
   $ oc delete -f manifests/02-metallb.yaml --ignore-not-found
   $ oc delete -f manifests/01-operator.yaml --ignore-not-found
   ```

   **出力例**

   ```terminal
   namespace "metallb-test" deleted
   deployment.apps "hello" deleted from metallb-test namespace
   service "hello" deleted from metallb-test namespace
   namespace "metallb-system" deleted
   operatorgroup.operators.coreos.com "metallb-operator" deleted from metallb-system namespace
   ```

## 関連情報

- [MetalLB Operator（OpenShift Container Platform 4.22「ネットワーク Operator」）](https://docs.redhat.com/ja/documentation/openshift_container_platform/4.22/html/networking_operators/metallb-operator)
- [MetalLB を使用した負荷分散（OpenShift Container Platform 4.22「Ingress およびロードバランシング」）](https://docs.redhat.com/ja/documentation/openshift_container_platform/4.22/html/ingress_and_load_balancing/load-balancing-with-metallb)
