#!/usr/bin/env bash
# Namespace が Active になっている
set -euo pipefail
oc wait --for=jsonpath='{.status.phase}'=Active namespace/hello-route --timeout=60s
