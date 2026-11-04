#!/usr/bin/env bash
# CSV の PHASE が Succeeded になり、InstallPlan が承認されている
set -euo pipefail
# Operator のインストールが完了するまで待機する
oc wait subscription/metallb-operator-sub -n metallb-system --for=jsonpath='{.status.state}'=AtLatestKnown --timeout=300s
csv=$(oc get subscription/metallb-operator-sub -n metallb-system -o jsonpath='{.status.installedCSV}')
oc wait csv/"$csv" -n metallb-system --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s

# CSV の PHASE が Succeeded であることを確認する
oc get csv -n metallb-system -o custom-columns=Name:.metadata.name,Phase:.status.phase

# InstallPlan が承認されていることを確認する
oc get installplan -n metallb-system
