#!/usr/bin/env bash
# 切り戻し。対象が無ければ何もしない (何度実行しても安全にする)。適用した YAML は、この後に cleanup が削除する
# TODO: .sh の変更、既存リソースの変更、YAML の削除だけでは戻らない設定を戻す。Operator は YAML の CR も先に削除し、Subscription → CSV → CRD の順で戻す。該当するものが全く無い場合だけ、この行を消す
set -euo pipefail
