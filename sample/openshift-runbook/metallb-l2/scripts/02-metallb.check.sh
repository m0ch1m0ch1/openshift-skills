#!/usr/bin/env bash
# controller と speaker の Pod が Running になっている
# 注記: speaker の Pod の数は、クラスタのノード数と同じになります。シングルノードの場合は 1 つです。
set -euo pipefail
# controller と speaker の Pod が Ready になるまで待機する
oc wait pod -l component=controller -n metallb-system --for=create --timeout=180s
oc wait pod -l component=controller -n metallb-system --for=condition=Ready --timeout=300s
oc wait pod -l component=speaker -n metallb-system --for=create --timeout=180s
oc wait pod -l component=speaker -n metallb-system --for=condition=Ready --timeout=300s

# controller の Deployment が AVAILABLE になっていることを確認する
oc get deployment controller -n metallb-system

# speaker の DaemonSet の READY がノード数と同じであることを確認する
oc get daemonset speaker -n metallb-system

# Pod の STATUS が Running であることを確認する
oc get pods -n metallb-system -l 'component in (controller,speaker)' -o wide
