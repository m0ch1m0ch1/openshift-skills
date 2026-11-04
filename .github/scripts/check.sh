#!/usr/bin/env bash
# CI の検査。スキル (.claude/skills/*/) を自動で見つけて、すべてに同じ検査をかける (.github/workflows/ci.yml から実行する)
#
# 検査:
#   skills  SKILL.md と README.md があり、name がディレクトリ名と同じで、description に半角スペースが無い
#   shell   すべての .sh に bash -n と ShellCheck (warning 以上) をかける (ShellCheck が無ければ省く。CI では必須)
#
# 終了コード: 0=OK 1=NG
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
NG=0
ng() { echo "[NG] $*"; NG=1; }
ok() { echo "[OK] $*"; }

echo "== skills =="
# front <SKILL.md> <キー>: 先頭の --- と --- の間にある "キー: 値" の値
front() { awk -v k="$2" 'NR == 1 && $0 != "---" {exit} NR > 1 && $0 == "---" {exit} NR > 1 && index($0, k ": ") == 1 {print substr($0, length(k) + 3); exit}' "$1"; }
for d in .claude/skills/*/; do
  s="$(basename "$d")"
  if [ ! -f "$d/SKILL.md" ]; then ng "$s: SKILL.md がありません"; continue; fi
  name="$(front "$d/SKILL.md" name)"; desc="$(front "$d/SKILL.md" description)"
  bad=0
  [ "$name" = "$s" ] || { ng "$s: SKILL.md の name ($name) がディレクトリ名と違います"; bad=1; }
  case "$desc" in
    "")    ng "$s: SKILL.md に description がありません"; bad=1 ;;
    *" "*) ng "$s: SKILL.md の description に半角スペースがあります"; bad=1 ;;
  esac
  [ -f "$d/README.md" ] || { ng "$s: README.md がありません"; bad=1; }
  [ $bad = 1 ] || ok "$s"
done

echo; echo "== shell =="
# Git の管理対象と、無視していない新しいファイル
SH="$(git ls-files --cached --others --exclude-standard -- '*.sh' | LC_ALL=C sort -u)"
bad=0
for f in $SH; do bash -n "$f" 2>/dev/null || { ng "$f: bash の構文エラー"; bad=1; }; done
[ $bad = 1 ] || ok "bash -n"
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086  # ファイル名に空白は無い
  if shellcheck -S warning $SH; then ok "ShellCheck"; else ng "ShellCheck の指摘があります"; fi
elif [ "${CI:-}" = true ]; then ng "ShellCheck がありません"
else echo "[SKIP] ShellCheck がありません (入れると検査します)"; fi

echo
if [ $NG = 0 ]; then echo "[OK] すべての検査を通りました"; else echo "[NG] 通らない検査があります"; fi
exit $NG
