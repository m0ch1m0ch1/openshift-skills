#!/usr/bin/env bash
# IP アドレスプールと L2 アドバタイズメントが作成されている
set -euo pipefail
# IP アドレスプールが作成されていることを確認する
oc get ipaddresspool -n metallb-system

# L2 アドバタイズメントが作成されていることを確認する
oc get l2advertisement -n metallb-system
