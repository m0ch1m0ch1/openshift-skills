#!/usr/bin/env bash
# Route の URL に HTTPS でアクセスすると HTTP 200 が返る
# 注記: Route は edge TLS 終端でクラスタの既定の証明書を使用するため、curl の -k オプションで証明書の検証を省略しています。
# 注記: Route を作成した直後は、Ingress Controller に反映されるまで HTTP 503 が返ることがあるため、再試行しています。
set -euo pipefail

# Route の URL に HTTPS でアクセスし、HTTP ステータスコードが 200 であることを確認する
host=$(oc -n hello-route get route hello -o jsonpath='{.spec.host}')
code=$(curl -sk --retry 10 --retry-delay 3 --retry-all-errors --fail -o /dev/null -w '%{http_code}' "https://${host}/")
echo "https://${host}/ -> ${code}"
[ "$code" = 200 ]
