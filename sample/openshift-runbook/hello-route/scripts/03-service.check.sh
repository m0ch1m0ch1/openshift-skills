#!/usr/bin/env bash
# Service が作成されている
set -euo pipefail
oc -n hello-route get service hello
