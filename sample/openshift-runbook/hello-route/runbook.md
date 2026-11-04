# Route を使用した nginx の公開

nginx を 1 つの Pod で実行し、Service と Route（edge TLS 終端）を使用してクラスタ外部に HTTPS で公開します。

> **注記**
>
> この手順は 2026-11-04 10:16、OpenShift 4.22.20 で検証済みです（詳細: run/result.md）。

## 前提条件

- Namespace を作成する権限を持つユーザーとしてクラスタにアクセスできる。
- クラスタから quay.io のイメージを取得できる。
- コマンドは、この手順書があるディレクトリ (manifests/ と scripts/ がある場所) で実行する。

## パラメータ

| 項目 | 値 | ファイル |
|---|---|---|
| Namespace | hello-route | 全ファイル |
| イメージ | quay.io/nginx/nginx-unprivileged:1.27 | manifests/02-deployment.yaml |

## 手順

1. Namespace を作成します。

   1. 次の YAML を使用して `manifests/01-namespace.yaml` ファイルを作成します。

      ```yaml
      apiVersion: v1
      kind: Namespace
      metadata:
        name: hello-route
      ```

   2. 次のコマンドを実行して、マニフェストを適用します。

      ```terminal
      $ oc apply -f manifests/01-namespace.yaml
      ```

      **出力例**

      ```terminal
      namespace/hello-route created
      ```

   3. 次のコマンドを実行して、Namespace が Active になっていることを確認します。

      ```terminal
      $ oc wait --for=jsonpath='{.status.phase}'=Active namespace/hello-route --timeout=60s
      ```

      **出力例**

      ```terminal
      namespace/hello-route condition met
      ```

2. nginx の Deployment を作成します。

   1. 次の YAML を使用して `manifests/02-deployment.yaml` ファイルを作成します。

      ```yaml
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: hello
        namespace: hello-route
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
      ```

   2. 次のコマンドを実行して、マニフェストを適用します。

      ```terminal
      $ oc apply -f manifests/02-deployment.yaml
      ```

      **出力例**

      ```terminal
      deployment.apps/hello created
      ```

   3. Pod が Ready になり、nginx が起動していることを確認します。

      1. 次のコマンドを実行して、Pod が Ready になるまで待機します。

         ```terminal
         $ oc wait pod -l app=hello -n hello-route --for=create --timeout=60s
         $ oc wait pod -l app=hello -n hello-route --for=condition=Ready --timeout=120s
         ```

         **出力例**

         ```terminal
         pod/hello-656fb99587-zxpns condition met
         pod/hello-656fb99587-zxpns condition met
         ```

      2. 次のコマンドを実行して、Pod の STATUS が Running であることを確認します。

         ```terminal
         $ oc get pods -l app=hello -n hello-route -o wide
         ```

         **出力例**

         ```terminal
         NAME                     READY   STATUS    RESTARTS   AGE   IP             NODE         NOMINATED NODE   READINESS GATES
         hello-656fb99587-zxpns   1/1     Running   0          1s    10.128.0.135   <ノード名>   <none>           <none>
         ```

      3. 次のコマンドを実行して、nginx が起動したことをログで確認します。

         ```terminal
         $ oc logs deployment/hello -n hello-route --tail=3
         ```

         **出力例**

         ```terminal
         2026/11/04 01:16:29 [notice] 1#1: start worker process 36
         2026/11/04 01:16:29 [notice] 1#1: start worker process 37
         2026/11/04 01:16:29 [notice] 1#1: start worker process 38
         ```

3. Service を作成します。

   1. 次の YAML を使用して `manifests/03-service.yaml` ファイルを作成します。

      ```yaml
      apiVersion: v1
      kind: Service
      metadata:
        name: hello
        namespace: hello-route
      spec:
        selector:
          app: hello
        ports:
          - name: http
            port: 8080
            targetPort: 8080
      ```

   2. 次のコマンドを実行して、マニフェストを適用します。

      ```terminal
      $ oc apply -f manifests/03-service.yaml
      ```

      **出力例**

      ```terminal
      service/hello created
      ```

   3. 次のコマンドを実行して、Service が作成されていることを確認します。

      ```terminal
      $ oc -n hello-route get service hello
      ```

      **出力例**

      ```terminal
      NAME    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
      hello   ClusterIP   172.30.185.236   <none>        8080/TCP   0s
      ```

4. Route（edge TLS）で公開します。

   > **注記**
   >
   > Route のホスト名は、クラスタの Ingress ドメインから自動で設定されます。証明書を指定しないため、Ingress Controller の既定の証明書が使われます。

   1. 次の YAML を使用して `manifests/04-route.yaml` ファイルを作成します。

      ```yaml
      apiVersion: route.openshift.io/v1
      kind: Route
      metadata:
        name: hello
        namespace: hello-route
      spec:
        to:
          kind: Service
          name: hello
        port:
          targetPort: http
        tls:
          termination: edge
          insecureEdgeTerminationPolicy: Redirect
      ```

      ここでは、以下のようになります。

      - `termination: edge`: TLS を Ingress Controller で終端します。
      - `insecureEdgeTerminationPolicy: Redirect`: HTTP のアクセスを HTTPS にリダイレクトします。

   2. 次のコマンドを実行して、マニフェストを適用します。

      ```terminal
      $ oc apply -f manifests/04-route.yaml
      ```

      **出力例**

      ```terminal
      route.route.openshift.io/hello created
      ```

## 検証

> **注記**
>
> Route は edge TLS 終端でクラスタの既定の証明書を使用するため、curl の -k オプションで証明書の検証を省略しています。

> **注記**
>
> Route を作成した直後は、Ingress Controller に反映されるまで HTTP 503 が返ることがあるため、再試行しています。

- 次のコマンドを実行して、Route の URL に HTTPS でアクセスすると HTTP 200 が返ることを確認します。

   ```terminal
   $ host=$(oc -n hello-route get route hello -o jsonpath='{.spec.host}')
   $ code=$(curl -sk --retry 10 --retry-delay 3 --retry-all-errors --fail -o /dev/null -w '%{http_code}' "https://${host}/")
   $ echo "https://${host}/ -> ${code}"
   $ [ "$code" = 200 ]
   ```

   **出力例**

   ```terminal
   https://hello-hello-route.apps.<クラスタのドメイン>/ -> 200
   ```

## 成功条件 (DoD)

2026-11-04 10:16 の検証で確認できた成功条件に [x] を付けています。

- [x] nginx の Pod が Ready になり、起動ログが出力されている。（手順 2）
- [x] Route の URL に HTTPS でアクセスすると HTTP 200 が返る。（検証）

成功条件をすべて満たしています（2/2）。

## 切り戻し

この手順で作成・変更したものを削除し、手順を実行する前の状態に戻します。

### 手順

1. 次のコマンドを実行して、作成したリソースを、適用したときと逆の順序で削除します。

   ```terminal
   $ oc delete -f manifests/04-route.yaml --ignore-not-found
   $ oc delete -f manifests/03-service.yaml --ignore-not-found
   $ oc delete -f manifests/02-deployment.yaml --ignore-not-found
   $ oc delete -f manifests/01-namespace.yaml --ignore-not-found
   ```

   **出力例**

   ```terminal
   route.route.openshift.io "hello" deleted from hello-route namespace
   service "hello" deleted from hello-route namespace
   deployment.apps "hello" deleted from hello-route namespace
   namespace "hello-route" deleted
   ```

## 関連情報

- [ルート（OpenShift Container Platform 4.22「Ingress およびロードバランシング」）](https://docs.redhat.com/ja/documentation/openshift_container_platform/4.22/html/ingress_and_load_balancing/routes)
