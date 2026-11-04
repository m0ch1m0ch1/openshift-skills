#!/usr/bin/env bash
# Pod が Ready になり、nginx が起動している
set -euo pipefail
# Pod が Ready になるまで待機する
oc wait pod -l app=hello -n hello-route --for=create --timeout=60s
oc wait pod -l app=hello -n hello-route --for=condition=Ready --timeout=120s

# Pod の STATUS が Running であることを確認する
oc get pods -l app=hello -n hello-route -o wide

# nginx が起動したことをログで確認する
oc logs deployment/hello -n hello-route --tail=3
