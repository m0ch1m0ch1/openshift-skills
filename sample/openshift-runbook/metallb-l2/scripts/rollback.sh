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
