#!/usr/bin/env bash
# 切り戻し。この手順で作成するものはすべて YAML のため、rollback.sh で戻すものはありません (YAML のリソースは cleanup が逆順に削除します)
set -euo pipefail
