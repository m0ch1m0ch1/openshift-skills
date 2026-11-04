#!/usr/bin/env bash
# Service に外部 IP アドレスが割り当てられ、ノードが L2 モードでアナウンスし、作業端末からアクセスすると 200 が返る
set -euo pipefail
# Pod が Ready になるまで待機する
oc wait pod -l app=hello -n metallb-test --for=create --timeout=120s
oc wait pod -l app=hello -n metallb-test --for=condition=Ready --timeout=180s

# Pod の STATUS が Running であることを確認する
oc get pods -l app=hello -n metallb-test -o wide

# nginx が起動したことをログで確認する
oc logs deployment/hello -n metallb-test --tail=3

# Service に外部 IP アドレスが割り当てられるまで待機する
oc wait service/hello -n metallb-test --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' --timeout=120s

# EXTERNAL-IP に IP アドレスプールのアドレスが表示されることを確認する
oc get service hello -n metallb-test

# 作業端末から外部 IP アドレスにアクセスし、200 が返ることを確認する
ip=$(oc get service hello -n metallb-test -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s --retry 10 --retry-delay 3 --retry-all-errors --fail -o /dev/null -w "http://$ip:8080/ -> %{http_code}\n" "http://$ip:8080/"

# IP アドレスが割り当てられ、ノードが layer2 でアナウンスしていることをイベントで確認する
oc get events -n metallb-test --field-selector involvedObject.kind=Service,involvedObject.name=hello -o custom-columns=REASON:.reason,FROM:.source.component,MESSAGE:.message
