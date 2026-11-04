#!/usr/bin/env bash
# OpenShift の手順を実クラスタで検証し、手順書 (runbook.md) を作る
#
# openshift-runbook スキルが、次の順で使う (cluster → new → lint → plan → run。失敗してやり直すときは cleanup)
#
# 使い方:
#   runbook.sh cluster                  接続先のクラスタを確認する (読み取りのみ)。公式ドキュメントの URL も表示する
#                                       終了コード: 0=OK 10=oc が無い 20=未ログイン/認証切れ 30=接続できない
#   runbook.sh new     <name>           ひな形から手順のディレクトリを作る
#   runbook.sh lint    <name>           静的チェック (クラスタは変更しない)
#   runbook.sh plan    <name>           成功条件、パラメータ、適用するリソース、既に存在するもの、前回から残っているものを表示する (読み取りのみ)
#   runbook.sh run     <name> --cleanup|--keep
#                                       実クラスタで手順を実行して検証し、検証結果と runbook.md を書く。どちらかの指定が必須
#                                       終了コード: 0=PASS 1=手順が失敗 2=切り戻し/クリーンアップに問題 3=開始できない (何も変更していない) 130=中断
#                                       --cleanup: rollback.sh と cleanup で元に戻す
#                                       --keep:    作成したリソースを残す (rollback.sh は検証されない)
#   runbook.sh cleanup <name>           検証で残ったリソースを元に戻す (rollback.sh を実行し、適用した YAML を削除する)
#                                       終了コード: 0=完了 1=削除できない/確認できない 3=開始できない (接続先が検証したときと違うなど)
#   runbook.sh doc     <name>           runbook.md を作り直す (run の最後にも実行される。クラスタに接続しない)
#   (lint と plan は、[NG] があると 1 を返す。どのコマンドも、引数の誤りは 3)
#
# 環境変数:
#   RUNBOOK_DIR      手順を置くディレクトリ (既定: Git リポジトリのルートの runbooks/。Git の外ならカレントディレクトリの runbooks/)
#   RUNBOOK_TIMEOUT  削除を待つ時間の上限 (既定: 300s)
#   OCP_VERSION      lint で確認するドキュメントのバージョン (既定: 接続中のクラスタのバージョン)
#
# 検証の記録 (<RUNBOOK_DIR>/<name>/run/):
#   result.md    検証結果。1 行目のコメントに result / date / version / fp / keep を持つ
#   applied.txt  適用した YAML (run/applied/ に保存した、適用したときの内容)。cleanup で逆順に削除する
#   server       検証した API サーバーとプロジェクト。cleanup は同じクラスタ・プロジェクトでしか実行しない
#   touched      .sh ステップを実行した (rollback.sh で戻すものがある)
#   pending      クラスタにリソースが残っている可能性がある。ステップの実行前に作り、元に戻せたら消す
#   logs/        ステップ・rollback・cleanup のログ
set -uo pipefail
TIMEOUT="${RUNBOOK_TIMEOUT:-300s}"
# 手順の置き場所: 既定は Git リポジトリのルート (Git の外ならカレントディレクトリ) の runbooks/。作業中にカレントディレクトリが変わっても同じ場所を使う
DIR="${RUNBOOK_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/runbooks}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- 共通 ---
die()     { echo "[NG] $*"; exit 3; }   # 開始できない (何も変更していない)
# has <grep の引数>: 標準入力に一致する行があるか。pipefail のもとで grep -q は偽になることがあるため、入力を最後まで読む
has()     { grep "$@" >/dev/null; }
title()   { sed -n 's/^# //p' "$1" | head -1; }
# 手順のファイル構成: manifests/NN-name.yaml (oc apply する YAML)、scripts/NN-name.sh (YAML で書けない作業)、
# scripts/NN-name.check.sh (各ステップの確認)。ステップの順番は NN で決まる
# by_name: パスの一覧をファイル名の順に並べる
by_name() { awk -F/ '{print $NF "\t" $0}' | LC_ALL=C sort | cut -f2; }   # ロケールによらず同じ順にする
# steps: ステップのファイル (manifests/NN-name.yaml か scripts/NN-name.sh) を順に出す
# shellcheck disable=SC2010  # ls の結果は、名前を ^[0-9]{2}-[a-z0-9-]+ に絞ってから使う (空白などを含む名前は通らない)
steps() {
  { ls manifests 2>/dev/null | grep -E '^[0-9]{2}-[a-z0-9-]+\.yaml$' | sed 's|^|manifests/|'
    ls scripts 2>/dev/null | grep -E '^[0-9]{2}-[a-z0-9-]+\.sh$' | sed 's|^|scripts/|'
  } | by_name
}
sid()     { local b="${1##*/}"; echo "${b%.*}"; }   # ステップ名: manifests/01-namespace.yaml → 01-namespace
chk()     { echo "scripts/$1.check.sh"; }          # ステップの確認スクリプト
version() { oc get clusterversion version -o jsonpath='{.status.desired.version}' --request-timeout=10s 2>/dev/null; }
minor()   { local v; v="$(version)"; v="${v%%-*}"; echo "${v%.*}"; }   # 4.22.18 → 4.22
# 手順の指紋 (ファイルのコメントを除いた中身と、spec.md の成功条件・パラメータ)。検証後に手順が変わったかを判定する
# shellcheck disable=SC2010,SC2046  # manifests/ と scripts/ のファイル名は lint で NN-name の形に限っている (空白を含まない)
fingerprint() {
  local sum="shasum -a 256"; command -v sha256sum >/dev/null 2>&1 && sum=sha256sum   # Linux / macOS
  { cat $(ls manifests/* scripts/* 2>/dev/null | grep -vx scripts/rollback.sh | by_name) scripts/rollback.sh 2>/dev/null | grep -v '^[[:space:]]*#' | sed "s@$KEYDOC@\\1@"
    spec_section "成功条件 (DoD)"; spec_section パラメータ
  } | $sum | cut -c1-12
}
# YAML のキー行の行末にある説明コメント (" # 説明")。手順書では「ここでは、以下のようになります。」のリストになる
KEYDOC='^\([[:space:]-]*[A-Za-z0-9_./-]\{1,\}:\(.*[^[:space:]]\)\{0,1\}\)[[:space:]]\{1,\}# \([^"'"'"']*\)$'
# スクリプトのブロック: "set -euo pipefail" より後を空行で区切った単位。手順書では、ブロックごとに
# 「コマンド → 出力例」を載せる。ブロック先頭の "# 〜する" は、そのブロックの説明になる
# instrument <ファイル> <タグ>: 各ブロックの前に "--- <タグ>:<番号>" を出力する行を入れたスクリプトを出す
instrument() {
  awk -v tag="$2" '
    !body { print; if ($0 ~ /^set -euo pipefail$/) { body = 1; nb = 1 }; next }
    /^[[:space:]]*$/ { nb = 1; print; next }
    nb { print "echo \"--- " tag ":" (++n) "\""; nb = 0 }
    { print }' "$1"
}
# blocks <ファイル>: ブロックの数
blocks() { awk '!body { if ($0 ~ /^set -euo pipefail$/) { body = 1; nb = 1 }; next } /^[[:space:]]*$/ { nb = 1; next } nb { n++; nb = 0 } END { print n + 0 }' "$1"; }
# block_part <ファイル> <番号> desc|code: ブロックの説明 (先頭のコメント。注記は除く) / コマンド
#   コメントとして扱うのはブロック先頭の "#" 行だけ (コマンドの後の "#" 行は、ヒアドキュメントの中身などとして残す)
block_part() {
  awk -v want="$2" -v part="$3" '
    !body { if ($0 ~ /^set -euo pipefail$/) { body = 1; nb = 1 }; next }
    /^[[:space:]]*$/ { nb = 1; next }
    nb { cur++; nb = 0; coded = 0 }
    cur != want { next }
    /^#/ && !coded { if (part == "desc" && $0 !~ /^# (注意|注記|重要|警告):/) { sub(/^# */, ""); print }; next }
    { coded = 1 }
    part == "code"' "$1"
}
meta()    { sed -n "1s/.* $1=\([^ ]*\).*/\1/p" run/result.md 2>/dev/null; }   # result.md の 1 行目の値
# spec.md の "## 成功条件 (DoD)" の項目の書式: "- [ ] 状態（確認: NN-name）"。NN-name は、その状態を確かめる check.sh のステップ
DOD_ITEM='^- \[ \] .+（確認: [0-9]{2}-[a-z0-9-]+）$'
# criteria: 成功条件を "<ステップ名>|<状態>" で出す
criteria() { spec_section "成功条件 (DoD)" | grep -E "$DOD_ITEM" | sed 's/^- \[ \] \(.*\)（確認: \([^）]*\)）$/\2|\1/'; }
# step_status <ステップ名>: run/result.md に記録したステップの結果 (OK / NG / SKIP)
step_status() { awk -F' *[|] *' -v b="$1" '$2 == b {print $4}' run/result.md 2>/dev/null; }
# checklist <ラベル>: 成功条件を DoD のチェックリストにする。標準入力は "<ステップ名>|<状態>|<結果>"
#   結果が OK の項目に [x] を付け、最後に達成数を出す。<ラベル> は "step" (ステップ名) か "index" (手順の番号)
checklist() {
  local b d st ref n=0 ok=0 judged=0
  while IFS='|' read -r b d st; do
    n=$((n + 1)); ref="$b"
    if [ "$1" = index ]; then
      # 最後のステップの確認は、手順書の「検証」に載る
      if [ "$b" = "$(for f in $(steps); do sid "$f"; done | tail -1)" ]; then ref="検証"
      else ref="手順 $(for f in $(steps); do sid "$f"; done | grep -nx "$b" | cut -d: -f1)"; fi
    fi
    case "$st" in OK|NG|SKIP) judged=$((judged + 1));; esac
    if [ "$st" = OK ]; then ok=$((ok + 1)); echo "- [x] ${d}（${ref}）"
    else echo "- [ ] ${d}（${ref}${st:+: ${st}}）"; fi
  done
  # 検証していないときは達成数を出さない
  [ $judged = $n ] || return 0
  echo
  [ $ok = $n ] && echo "成功条件をすべて満たしています（${ok}/${n}）。" || echo "満たしている成功条件: ${ok}/${n}"
}
leftover() { [ -f run/pending ] || [ -s run/applied.txt ]; }                    # リソースが残っている可能性
rollback_needed() { [ -s run/applied.txt ] || [ -f run/touched ]; }               # 適用・実行したものがある
# rollback_summary: rollback.sh が行うこと (ブロックの説明と、重要・警告の注記)
rollback_summary() {
  local k d
  sed -nE 's/^# (重要|警告): *(.*)$/[\1] \2/p' scripts/rollback.sh
  for ((k = 1; k <= $(blocks scripts/rollback.sh); k++)); do
    [ -n "$(block_part scripts/rollback.sh $k code)" ] || continue
    d="$(block_part scripts/rollback.sh $k desc | head -1)"; echo "- ${d:-（説明なし）}"
  done
}
# target: 今の接続先 ("API サーバー プロジェクト")。namespace を書いていないオブジェクトはプロジェクトに作られるので、両方を記録する
#   (コンテキストに namespace が無いときは、namespace を書いていないオブジェクトは default に作られる)
target()   { local s p; s="$(oc whoami --show-server --request-timeout=10s 2>/dev/null)" || return 0; [ -n "$s" ] || return 0
             p="$(oc config view --minify -o jsonpath='{.contexts[0].context.namespace}' 2>/dev/null)"; echo "$s ${p:-default}"; }
# same_target: 検証したとき (run/server) と今の接続先が同じか。記録が無いときは「違う」とみなす
same_target() { [ -s run/server ] && [ "$(cat run/server)" = "$(target)" ]; }
target_ng() { local r; r="$(cat run/server 2>/dev/null)"; echo "[NG] 検証したときの接続先 (${r:-記録なし}) と、今の接続先 ($(target)) が違います"; echo "案内: 検証したクラスタとプロジェクトに切り替えてから実行する (oc config use-context … / oc project …)"; }
# pin_kubeconfig: 実行中に接続先が変わらないように、今のコンテキストを一時ファイルに固定する (終了時に消す)
pin_kubeconfig() {
  PINNED="$(mktemp "${TMPDIR:-/tmp}/runbook-kubeconfig.XXXXXX")" || return 1
  chmod 600 "$PINNED"
  oc config view --minify --flatten > "$PINNED" 2>/dev/null && [ -s "$PINNED" ] || { echo "[NG] 接続先を固定できません"; return 1; }
  export KUBECONFIG="$PINNED"
}
PINNED=""; trap '[ -z "$PINNED" ] || rm -f "$PINNED"' EXIT
# existing <ファイル>: クラスタに既にあるオブジェクトを出す。確認できないとき (権限・通信) は 2 を返す
#   (CRD がまだ無い kind のオブジェクトは「無い」とみなす)
existing() {
  local out err rc
  err="$(mktemp)"
  out="$(oc get -f "$1" --ignore-not-found -o name --request-timeout=30s 2>"$err")"; rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ $rc -ne 0 ] && grep -vqE 'no matches for kind|resource mapping not found|ensure CRDs are installed first|^[[:space:]]*$' "$err"; then
    sed 's/^/  /' "$err" >&2; rm -f "$err"; return 2
  fi
  rm -f "$err"
}

# --- cluster / new / lint / plan ---

# 終了コード: 0=OK 10=oc が無い 20=未ログイン/認証切れ 30=到達不可・TLS・その他
cmd_cluster() {
  local out
  if ! command -v oc >/dev/null 2>&1; then
    echo "[NG] oc がありません"
    echo "案内: Web コンソールの「?」→「Command line tools」、または https://mirror.openshift.com/pub/openshift-v4/clients/ocp/ から oc をインストールする"
    return 10
  fi
  local login="案内: Web コンソールの「Copy login command」で取得した oc login --token=… --server=… を実行する"
  [ -n "$(oc config current-context 2>/dev/null)" ] || { echo "[NG] 未ログイン"; echo "$login"; return 20; }
  if ! out="$(oc whoami --request-timeout=10s 2>&1)"; then
    echo "[NG] $out"
    case "$out" in *Unauthorized*|*"must be logged in"*) echo "$login"; return 20;; esac
    echo "案内: 実行環境 (sandbox) の通信制限を先に確認する。端末側でも接続できない場合は VPN、DNS、API ポート、証明書 (--certificate-authority) を確認する"
    return 30
  fi
  echo "[OK] $out @ $(oc whoami --show-server)"
  echo "[OK] OpenShift $(version || echo '(バージョン取得不可)')"
  [ -z "$(minor)" ] || echo "ドキュメント (英語版の目次。spec.md の関連情報には /ja/ の URL を載せる): https://docs.redhat.com/en/documentation/openshift_container_platform/$(minor)/html/<guide>/index"
}

# new <name>: ひな形から手順のディレクトリを作る
cmd_new() {
  [ ! -e "$DIR/$SLUG" ] || { echo "[NG] $DIR/$SLUG は既にあります"; echo "案内: 別の手順名にする (既存の手順は再利用しない)"; exit 3; }
  mkdir -p "$DIR/$SLUG/manifests" "$DIR/$SLUG/scripts"
  local v; v="$(minor)"
  sed "s/VERSION/${v:-TODO}/" "$SKILL_DIR/templates/spec.md" > "$DIR/$SLUG/spec.md"
  cp "$SKILL_DIR/templates/rollback.sh" "$DIR/$SLUG/scripts/rollback.sh"
  echo "[OK] $DIR/$SLUG/ を作りました"
  echo "次: spec.md の '## 成功条件 (DoD)' を書いて合意を得る。合意したら、spec.md の残りと scripts/rollback.sh の TODO を埋め、manifests/NN-name.yaml (YAML で書けない作業は scripts/NN-name.sh) と scripts/NN-name.check.sh を作って、runbook.sh lint $SLUG"
}

cmd_lint() {
  local f b img d k fail=0
  ng() { echo "[NG] $*"; fail=1; }
  [ -f spec.md ] || ng "spec.md がありません"
  head -1 spec.md 2>/dev/null | has '^# ' || ng "spec.md の 1 行目に '# タイトル' が必要"
  grep -qx '## 前提条件' spec.md 2>/dev/null || echo "[WARN] spec.md に '## 前提条件' がありません"
  grep '^## ' spec.md 2>/dev/null | grep -vxE '## (成功条件 \(DoD\)|前提条件|パラメータ|関連情報)' | sed "s|^|[WARN] spec.md: 想定外の節です (手順に関わる補足はステップの '# 注記:' に書く): |"
  # 成功条件 (DoD): チェックリストの各項目に、それを確かめる check.sh のステップを付ける
  if ! grep -qx '## 成功条件 (DoD)' spec.md 2>/dev/null; then ng "spec.md に '## 成功条件 (DoD)' が必要"
  else
    [ -n "$(criteria)" ] || ng "spec.md の '## 成功条件 (DoD)' に '- [ ] 状態（確認: NN-name）' の項目が必要"
    while IFS= read -r d; do ng "spec.md: 成功条件の書式は '- [ ] 状態（確認: NN-name）' (チェックは付けない): $d"
    done < <(spec_section "成功条件 (DoD)" | grep '^- ' | grep -vE "$DOD_ITEM")
    while IFS= read -r d; do ng "spec.md: 成功条件に '|' は使わない: $d"
    done < <(spec_section "成功条件 (DoD)" | grep '^- ' | grep -F '|')
    for d in $(criteria | cut -d'|' -f1); do
      [ -f "$(chk "$d")" ] || ng "spec.md: 成功条件のステップ $(chk "$d") がありません"
    done
  fi
  # YAML は、クラスタと同じバージョンの公式ドキュメントを確認して作る。確認した章を関連情報に載せる
  #   (OpenShift のドキュメントに載っていないもの (Red Hat 以外の Operator など) は、提供元のドキュメントへのリンクでよい)
  local ver; ver="${OCP_VERSION:-$(minor)}"
  if ! spec_section 関連情報 2>/dev/null | has -E 'https?://'; then
    echo "[WARN] spec.md の '## 関連情報' に、読んだドキュメントへのリンクがありません"
  elif [ -n "$ver" ] && grep -q 'docs\.redhat\.com/[a-z-]*/documentation/openshift_container_platform/' spec.md 2>/dev/null &&
       ! grep -q "docs\.redhat\.com/[a-z-]*/documentation/openshift_container_platform/$ver/" spec.md 2>/dev/null; then
    echo "[WARN] spec.md の '## 関連情報' の OpenShift のドキュメントが、接続中のクラスタのバージョン ($ver) と違います"
  fi
  # YAML の確認には oc が必要 (クラスタには接続しない)
  local has_oc=1; command -v oc >/dev/null 2>&1 || { has_oc=0; ng "oc がありません (YAML の確認に必要)"; }
  # クラスタにある種類を "グループ/Kind" で集める (接続できないときは空。namespace の確認を省く)
  local nsd cls key
  kinds() { oc api-resources --namespaced="$1" --no-headers --request-timeout=10s 2>/dev/null | awk '{v = $(NF-2); sub(/\/?[^\/]*$/, "", v); printf "%s/%s ", v, $NF}'; }
  [ $has_oc = 1 ] && { nsd=" $(kinds true)"; cls=" $(kinds false)"; } || { nsd=" "; cls=" "; }
  if [ "$nsd" = " " ] && [ $has_oc = 1 ]; then
    [ "$CMD" = run ] && ng "クラスタの API 情報を取得できないため、namespace の要否を確認できません" || echo "[WARN] クラスタの API 情報を取得できないため、namespace の要否を確認していません"
  fi
  for f in $(grep -l TODO spec.md manifests/* scripts/* 2>/dev/null); do ng "$f: TODO が残っています"; done
  [ -n "$(steps)" ] || ng "manifests/ か scripts/ にステップがありません"
  [ -f scripts/rollback.sh ] || ng "scripts/rollback.sh がありません"
  for f in manifests/* scripts/*; do
    [ -e "$f" ] || continue
    case "$f" in *.sh)
      bash -n "$f" 2>/dev/null || ng "$f: bash 構文エラー"
      grep -qx 'set -euo pipefail' "$f" || ng "$f: 'set -euo pipefail' の行が必要 (この行より後がブロックになる)"
      for ((k = 1; k <= $(blocks "$f"); k++)); do
        block_part "$f" $k code | bash -n 2>/dev/null ||
          ng "$f: ブロック $k だけでは構文が完結しない (ループやヒアドキュメントの途中に空行を入れない)"
        d="$(block_part "$f" $k desc | head -1)"
        [ -z "$d" ] || [[ $d == *する ]] || echo "[WARN] $f: ブロック $k の説明は「〜する」の形にする: $d"
      done;;
    esac
    case "$f" in
      scripts/rollback.sh) ;;
      manifests/*.sh|scripts/*.yaml|scripts/*.yml) ng "$f: YAML は manifests/、スクリプトは scripts/ に置く";;
      scripts/*.check.sh)
        b="$(basename "$f" .check.sh)"; [ -f "manifests/$b.yaml" ] || [ -f "scripts/$b.sh" ] || ng "$f: 対応するステップがありません"
        [ -n "$(title "$f")" ] || ng "$f: 先頭に '# 確認する状態' のコメントが必要"
        [[ $(title "$f") != *'|'* ]] || ng "$f: 1 行目に '|' は使わない"
        grep -q 'rollout status' "$f" && echo "[WARN] $f: rollout status ではなく、oc wait で待ってから oc get pods / oc logs で状態を見せる"
        grep -n 'oc wait' "$f" | grep -v -- '--timeout' | sed "s|^|[WARN] $f: oc wait に --timeout を付ける: |"
        grep -n 'oc get.*|[[:space:]]*grep -q' "$f" | sed "s|^|[WARN] $f: oc get の出力を変数に入れてから判定する: |";;
      manifests/*.yaml|scripts/*.sh)
        b="$(sid "$f")"
        basename "$f" | has -E '^[0-9]{2}-[a-z0-9-]+\.(yaml|sh)$' || ng "$f: 名前は NN-name.yaml / NN-name.sh"
        [ -f "manifests/$b.yaml" ] && [ -f "scripts/$b.sh" ] && ng "$b: manifests/$b.yaml と scripts/$b.sh はどちらか一方にする"
        [ -f "$(chk "$b")" ] || ng "$f: $(chk "$b") がありません"
        [ -n "$(title "$f")" ] || ng "$f: 先頭に '# 作業名' のコメントが必要"
        [[ $(title "$f") != *'|'* ]] || ng "$f: 1 行目に '|' は使わない"
        [[ $(title "$f") == *する ]] || echo "[WARN] $f: 作業名は「〜する」の形にする (手順書で「〜します。」になる)"
        if [[ $f == *.yaml && $has_oc = 1 ]]; then
          oc label --local -f "$f" x=y -o name >/dev/null 2>&1 || ng "$f: YAML エラー"
          # namespace が無いと、実行した人のカレントプロジェクトに作られてしまう。
          # クラスタにまだ無い種類 (Operator が後から作る CRD など) は判定できないので WARN にする
          if [ "$nsd" != " " ]; then
            while IFS='|' read -r av k n ns; do
              [ -n "$k" ] && [ -z "$ns" ] || continue
              key="$([ "${av%/*}" = "$av" ] || echo "${av%/*}")/$k"
              if [[ $nsd == *" $key "* ]]; then ng "$f: $k/$n に metadata.namespace が必要"
              elif [[ $cls != *" $key "* ]]; then echo "[WARN] $f: $k/$n はクラスタにまだ無い種類です。namespace が必要な種類なら metadata.namespace を書く"
              fi
            done < <(oc label --local -f "$f" x=y -o go-template='{{.apiVersion}}|{{.kind}}|{{.metadata.name}}|{{with .metadata.namespace}}{{.}}{{end}}{{"\n"}}' 2>/dev/null)
          fi
          grep -qE '^kind:[[:space:]]*Secret' "$f" && ! grep -q CHANGE_ME "$f" && echo "[WARN] $f: Secret の値は CHANGE_ME にする"
          # 行末の説明は、手順書で「ここでは、以下のようになります。」のリストになる。「〜します。」の文で書く
          body "$f" | sed -n "s@$KEYDOC@\\3@p" | grep -v '。$' | sed "s|^|[WARN] $f: 行末の説明は「〜します。」の文で書く: |"
          # 説明として読み取れない行末のコメント (引用符を含むなど) は、手順書の YAML にそのまま残る
          body "$f" | grep -E '[^[:space:]][[:space:]]+# ' | grep -v "$(printf '%s' "$KEYDOC" | sed 's/\\(/(/g; s/\\)/)/g; s/\\{/{/g; s/\\}/}/g')" -E | sed "s|^|[WARN] $f: 行末のコメントを説明として扱えません (引用符を使わない): |"
          for img in $(sed -n 's/^[[:space:]-]*image:[[:space:]]*//p' "$f" | sed 's/[[:space:]]#.*//' | tr -d "\"'"); do
            [[ ${img##*/} == *@sha256:* || ( ${img##*/} == *:* && $img != *:latest ) ]] || echo "[WARN] $f: $img のタグを固定する"
          done
        fi;;
      *) ng "$f: 想定外のファイル";;
    esac
  done
  [ $fail -eq 0 ] && echo "[OK] lint" && [ "$CMD" = lint ] && echo "次: runbook.sh plan $SLUG"
  return $fail
}

# plan: run で適用するものを示す (クラスタは変更しない)
cmd_plan() {
  local s ng=0 dup=0 exist
  cmd_cluster >/dev/null || { echo "[NG] クラスタに接続できません"; echo "次: runbook.sh cluster"; return 1; }
  echo "接続先: $(oc whoami) @ $(oc whoami --show-server) (OpenShift $(version))"
  echo
  echo "成功条件 (DoD):"
  criteria | while IFS='|' read -r b d; do echo "- [ ] ${d}（確認: ${b}）"; done
  echo
  # パラメータ: 環境ごとに変える値 (spec.md の "## パラメータ")
  if [ -n "$(spec_section パラメータ)" ]; then
    echo "パラメータ:"
    spec_section パラメータ
    echo
    echo "注記: 別の環境で実行する場合は、これらの値の見直しが必要なことがあります。"
    echo
  fi
  echo "適用するもの:"
  for s in $(steps); do
    echo "$(sid "$s"): $(title "$s")"
    if [[ $s == *.yaml ]]; then
      oc label --local -f "$s" x=y -o go-template='{{.kind}} {{.metadata.name}}{{if .metadata.namespace}} (namespace: {{.metadata.namespace}}){{else}} (クラスタスコープ){{end}}{{"\n"}}' 2>/dev/null | sed 's/^/  - 作成: /'
      if ! exist="$(existing "$s")"; then echo "  [NG] 既にあるかどうかを確認できません (権限・通信を確認する)"; ng=1
      elif [ -n "$exist" ]; then printf '%s\n' "$exist" | sed 's/^/  [NG] 既に存在する (run は開始しない): /'; ng=1; dup=1; fi
    else
      echo "  - スクリプトを実行 (rollback.sh で元に戻す)"
    fi
  done
  [ $dup = 0 ] || { echo; echo "案内: 既にあるリソースは、検証のクリーンアップで削除されてしまうため適用しない。パラメータで名前を変える (spec.md の パラメータ と該当するファイルを直す) か、検証を中止する"; }
  if leftover; then
    ng=1
    echo
    if ! same_target; then target_ng; return $ng; fi
    echo "[NG] 前回の検証のリソースが残っている可能性があります。cleanup で次のものを元に戻します:"
    # rollback.sh に実行する処理が無ければ、表示しない
    if rollback_needed && [ -n "$(rollback_summary)" ]; then
      echo "  - scripts/rollback.sh を実行:"
      rollback_summary | sed 's/^/      /'
    fi
    local unknown=0 out
    exist=""
    for s in $(cat run/applied.txt 2>/dev/null); do
      if out="$(existing "$s" 2>/dev/null)"; then exist+="$out"$'\n'; else unknown=1; fi
    done
    exist="$(printf '%s' "$exist" | grep -v '^$' || true)"
    [ -z "$exist" ] || printf '%s\n' "$exist" | sed 's/^/  - 削除: /'
    [ $unknown = 0 ] || echo "  - (適用した YAML のリソースの一部は、残っているか確認できません。権限・通信を確認する)"
    [ -n "$exist" ] || [ $unknown = 1 ] || [ ! -s run/applied.txt ] || echo "  - (適用した YAML のリソースは、クラスタに見つかりません)"
    echo "次: runbook.sh cleanup $SLUG"
  fi
  [ $ng = 0 ] && { echo; echo "次: runbook.sh run $SLUG --cleanup (作成したリソースを残すときは --keep)"; }
  return $ng
}

# --- run / cleanup ---

# run_step <ファイル>: YAML は apply、.sh は実行。その後 check.sh
run_step() {
  local s=$1 exist
  if [[ $s == *.yaml ]]; then
    exist="$(existing "$s")" || { echo "[NG] 既にあるかどうかを確認できないため適用しない"; return 1; }
    [ -z "$exist" ] || { echo "[NG] 既に存在するため適用しない (cleanup で消えてしまうため): $exist"; return 1; }
    # 適用したときの内容を保存し、cleanup はその内容で削除する (後でファイルを直しても、別のリソースを消さない)
    mkdir -p run/applied; cp "$s" "run/applied/${s##*/}"
    echo "run/applied/${s##*/}" >> run/applied.txt
    oc apply -f "$s" || return 1
  else
    touch run/touched
    bash <(instrument "$s" run) || return 1
  fi
  bash <(instrument "$(chk "$(sid "$s")")" check)
}

# diagnose: 適用した YAML の Namespace について、リソース・イベント・Pod ログを出力する (rollback で消える前に記録する)
diagnose() {
  local f ns p out
  for ns in $(for f in $(cat run/applied.txt 2>/dev/null); do
      oc label --local -f "$f" x=y -o go-template='{{if eq .kind "Namespace"}}{{.metadata.name}}{{else}}{{with .metadata.namespace}}{{.}}{{end}}{{end}}{{"\n"}}'
    done | grep -v '^$' | sort -u); do
    echo "=== 診断: namespace $ns"
    oc -n "$ns" get all -o wide 2>/dev/null
    echo "--- events"; oc -n "$ns" get events --sort-by=.lastTimestamp | tail -20
    # Operator のリソースがあるときだけ、見出しを付けて出す
    out="$(oc -n "$ns" get subscription,csv,installplan 2>/dev/null)"
    [ -z "$out" ] || { echo "--- subscription / csv / installplan"; printf '%s\n' "$out"; echo "--- subscription の状態"
      oc -n "$ns" get subscription -o jsonpath='{range .items[*]}{.metadata.name}: {range .status.conditions[*]}{.type}={.status} {.message}; {end}{"\n"}{end}' 2>/dev/null; }
    for p in $(oc -n "$ns" get pods -o name); do echo "--- logs $p"; oc -n "$ns" logs "$p" --all-containers --tail=20; done
  done
}

cmd_run() {
  local keep=0
  case "${1:-}" in
    --cleanup) ;;
    --keep) keep=1;;
    *) die "検証後にクリーンアップするか (--cleanup)、リソースを残すか (--keep) を指定する: runbook.sh run <name> --cleanup|--keep";;
  esac
  # 開始できないときは、何も変更せずに 3 で終える
  cmd_cluster || return 3
  pin_kubeconfig || return 3
  local tgt; tgt="$(target)"
  [ -n "$tgt" ] || { echo "[NG] 接続先 (API サーバーとプロジェクト) を取得できません"; return 3; }
  cmd_lint || return 3
  leftover && { echo "[NG] 前回の検証のリソースが残っている可能性があります"; echo "次: runbook.sh plan $SLUG で確認し、runbook.sh cleanup $SLUG"; return 3; }
  local s exist pre=0
  for s in $(steps); do
    [[ $s == *.yaml ]] || continue
    if ! exist="$(existing "$s")"; then echo "[NG] $s: 既にあるかどうかを確認できません"; pre=1
    elif [ -n "$exist" ]; then printf '%s\n' "$exist" | sed "s|^|[NG] $s: 既に存在する: |"; pre=1; fi
  done
  [ $pre = 0 ] || { echo "次: runbook.sh plan $SLUG"; return 3; }
  local fp; fp="$(fingerprint)"   # 実行中にファイルを直しても、実行した内容の指紋を記録する
  rm -rf run; mkdir -p run/logs; touch run/pending; echo "$tgt" > run/server
  cmd_doc >/dev/null   # 実行中・中断時に、前回の「検証済み」の手順書が残らないようにする
  # 中断されたとき (Bash の timeout など) は、その旨を記録して終える。pending が残るので cleanup で元に戻せる
  #   (ステップの出力はログに向けているので、画面への出力は fd 3 に書く)
  exec 3>&1
  trap 'echo "<!-- result=INTERRUPTED date=$(date "+%Y-%m-%dT%H:%M") -->" > run/result.md; echo "[NG] 中断されました" >&3; echo "次: runbook.sh plan $SLUG で確認し、runbook.sh cleanup $SLUG" >&3; exit 130' INT TERM
  local b t st rows="" failed="" rb=OK cl=OK result=PASS n
  for s in $(steps); do
    b="$(sid "$s")"
    if [ -n "$failed" ]; then rows+="| $b | $(title "$s") | SKIP | - |"$'\n'; continue; fi
    t=$(date +%s)
    if run_step "$s" > "run/logs/$b.log" 2>&1; then st=OK; else st=NG; failed=$b; diagnose >> "run/logs/$b.log" 2>&1; fi
    rows+="| $b | $(title "$s") | $st | $(( $(date +%s) - t )) |"$'\n'
    echo "[$st] $b  $(title "$s")"
  done
  if [ $keep = 1 ]; then
    # 作成したリソースを残す (pending も残る)。後で cleanup を実行すると元に戻す
    rb=未実施; cl=未実施; echo "[SKIP] rollback / cleanup (--keep。rollback.sh は検証していません)"
  elif ! rollback_needed; then
    # 何も変更していない (最初のステップの適用前に止まった) ので、切り戻さない
    rb=不要; cl=不要; echo "[SKIP] rollback / cleanup (何も変更していません)"; rm -f run/pending
  else
    bash <(instrument scripts/rollback.sh rollback) > run/logs/rollback.log 2>&1 || rb=NG; echo "[$rb] rollback"
    # rollback.sh が止まったとき (この手順で作成していないリソースがあるなど) は、YAML も削除しない。ユーザーが判断する
    if [ $rb = OK ]; then delete_applied > run/logs/cleanup.log 2>&1 || cl=NG; else cl=未実施; fi; echo "[$cl] cleanup"
    [ $rb = OK ] && [ $cl = OK ] && rm -f run/pending run/touched
  fi
  trap - INT TERM
  [ -z "$failed" ] && [ $rb != NG ] && [ $cl != NG ] || result=FAIL
  {
    echo "<!-- result=$result date=$(date '+%Y-%m-%dT%H:%M') version=$(version) fp=$fp keep=$keep -->"
    echo "# 検証結果: $(title spec.md)"
    echo
    echo "- 結果: **${result}**（切り戻し ${rb} / クリーンアップ ${cl}）"
    echo "- 日時: $(date '+%Y-%m-%d %H:%M')"
    echo "- 接続先: \`$(cut -d' ' -f1 run/server)\`（プロジェクト $(cut -d' ' -f2 run/server)、OpenShift $(version)、$(oc whoami)）"
    echo
    echo "| ステップ | 作業 | 結果 | 秒 |"
    echo "| --- | --- | --- | --- |"
    printf '%s' "$rows"
    echo
    echo "## 成功条件 (DoD)"
    echo
    criteria | while IFS='|' read -r b d; do
      echo "$b|$d|$(printf '%s' "$rows" | awk -F' *[|] *' -v b="$b" '$2 == b {print $4}')"
    done | checklist step
    for n in $failed $([ $rb = NG ] && echo rollback) $([ $cl = NG ] && echo cleanup); do
      printf '\n## NG: %s（末尾 60 行）\n\n```text\n' "$n"; tail -60 "run/logs/$n.log"; echo '```'
    done
    echo; echo "全ログ: run/logs/"
  } > run/result.md
  echo "結果: $result → $DIR/$SLUG/run/result.md"
  cmd_doc
  if [ $result = FAIL ]; then
    if [ -n "$failed" ]; then echo "次: $DIR/$SLUG/run/logs/$failed.log で原因を調べる"
    elif [ $rb = NG ]; then echo "次: $DIR/$SLUG/run/logs/rollback.log で原因を調べる"
    else echo "次: $DIR/$SLUG/run/logs/cleanup.log で原因を調べる"; fi
    if leftover && [ $keep = 0 ]; then echo "次: リソースが残っている。ファイルを直す前に runbook.sh plan $SLUG で確認し、runbook.sh cleanup $SLUG (rollback.sh の不具合なら、rollback.sh だけを先に直す)"
    elif [ -n "$failed" ]; then echo "次: ファイルを直して run をやり直す"; fi
  fi
  [ $keep = 1 ] && leftover && echo "案内: リソースは残っています。元に戻すときは、runbook.md の「切り戻し」の手順を実行する"
  [ -n "$failed" ] && return 1
  [ $result = PASS ] || return 2
  return 0
}

# rollback.sh で .sh ステップの変更を戻してから、適用した YAML を削除する
cmd_cleanup() {
  leftover || { echo "[OK] 削除するものはありません"; return 0; }
  cmd_cluster >/dev/null || { echo "[NG] クラスタに接続できません"; echo "次: runbook.sh cluster"; return 3; }
  same_target || { target_ng; return 3; }
  pin_kubeconfig || return 3
  if rollback_needed; then
    bash <(instrument scripts/rollback.sh rollback) || { echo "[NG] rollback.sh が失敗しました"; echo "案内: 上の出力と読み取りだけの調査で原因を調べる。この手順で作成していないリソースがあって止まった場合は、どうするかをユーザーに聞く"; return 1; }
  fi
  delete_applied || { echo "案内: 残ったリソースを読み取りだけの調査で調べる (finalizer など)。強制削除は、ユーザーの了承を得てから行う"; return 1; }
  rm -f run/pending run/touched
  echo "[OK] クリーンアップ完了"
}

# 適用した YAML を逆順に削除し、残っていないことを確かめる
delete_applied() {
  local f out left="" unknown=""
  [ -s run/applied.txt ] || { echo "[OK] 適用した YAML はありません"; return 0; }
  for f in $(tac run/applied.txt 2>/dev/null || tail -r run/applied.txt); do
    out="$(oc delete -f "$f" --ignore-not-found --wait --timeout=$TIMEOUT 2>&1)"
    # CRD が消えていれば、その kind のリソースも存在しない
    printf '%s\n' "$out" | grep -vE 'no matches for kind|resource mapping not found|ensure CRDs are installed first|^[[:space:]]*$' || true
  done
  # 残っていないことを確かめる。確認できないとき (権限・通信) は、残っているものとして扱う
  for f in $(cat run/applied.txt); do
    if ! out="$(existing "$f")"; then unknown+="$f"$'\n'
    elif [ -n "$out" ]; then left+="$out"$'\n'; fi
  done
  [ -z "$unknown" ] || { echo "[NG] 削除できたか確認できません (権限・通信を確認する):"; printf '%s' "$unknown"; return 1; }
  [ -z "$left" ] || { echo "[NG] 削除できなかったリソース:"; printf '%s' "$left"; return 1; }
  rm -f run/applied.txt; rm -rf run/applied
  echo "[OK] 適用した YAML を削除しました"
}

# --- doc (Red Hat 公式ドキュメントの手順モジュールの書き方に準じる) ---
# body <ファイル>: 手順書に載せる本文 (先頭のコメント・shebang・set -euo pipefail・先頭の空行を除く)
body()  { grep -vE '^#|^set -euo pipefail$' "$1" | sed '/./,$!d'; }
# yaml_body <ファイル>: YAML 本文から行末の説明コメント (" # 説明") を除く
yaml_body() { body "$1" | sed "s@$KEYDOC@\\1@"; }
# yaml_where <ファイル> <インデント>: 行末の説明コメントを「ここでは、以下のようになります。」のリストにする
#   同じ名前のキーが何か所にもあっても区別できるように、キーと値の組 ("name: web-terminal-check") を示す
yaml_where() {
  local list
  list="$(body "$1" | sed -n "s@$KEYDOC@\\1|\\3@p" | sed 's/^[[:space:]-]*\([^|]*\)|/- `\1`: /; s/:`: /`: /')"
  [ -n "$list" ] || return 0
  echo; echo "$2ここでは、以下のようになります。"; echo; printf '%s\n' "$list" | sed "s/^/$2/"
}
# prompt: コマンドの開始行に "$ " を付ける (継続行・インデント行・ブロック終端・ヒアドキュメントには付けない)
prompt() {
  awk -v q="'" '
    hd != "" { print; t = $0; sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
    { print ((cont || $0 == "" || $0 ~ /^[[:space:]]/ || $0 ~ /^(done|fi|esac|else|elif|then|do|[})])/) ? "" : "$ ") $0 }
    { cont = ($0 ~ /(\\|\||&&|\(|\{|[[:space:]]do|[[:space:]]then|[[:space:]]in)[[:space:]]*$/) }
    match($0, /(^|[^<])<<-?[[:space:]]*["'"'"']?[A-Za-z_]+/) { h = substr($0, RSTART, RLENGTH); sub(/^.*<</, "", h); gsub(/["[:space:]-]/, "", h); gsub(q, "", h); hd = h }
  '
}
# block <言語> <インデント>: 標準入力をコードブロックとして出力する
block() { echo "$2\`\`\`$1"; sed "s/^/$2/"; echo "$2\`\`\`"; }
# output <ログ> <タグ> <番号>: 検証ログから、そのブロックの出力を取り出す (最大 30 行)
#   タグが apply のときは、最初の区切りより前 (oc apply の出力)
output() {
  [ -f "$1" ] || return 0
  if [ "$2" = apply ]; then awk '/^--- [a-z]+:[0-9]+$|^=== 診断/ {exit} {print}' "$1"
  else awk -v m="--- $2:$3" '$0 == m {on = 1; next} /^--- [a-z]+:[0-9]+$|^=== 診断/ {on = 0} on' "$1"; fi | head -30
}
# example <ログ> <タグ> <番号> <インデント>: 出力があれば「出力例」を出す
example() {
  local out; out="$(output "$1" "$2" "$3")"
  [ -n "$out" ] || return 0
  echo; echo "$4**出力例**"; echo; printf '%s\n' "$out" | block "terminal" "$4"
}
polite() { sed "s/する$/します/"; }   # 作業名を「〜します」に整える
# admonition <種類> <本文> <インデント>: Red Hat ドキュメントの注記 (注記 / 重要 / 警告)
admonition() { printf '\n%s> **%s**\n%s>\n%s> %s\n' "$3" "$1" "$3" "$3" "$2"; }
# notes <ファイル> <インデント>: "# 注意:" "# 注記:" → 注記、"# 重要:" → 重要、"# 警告:" → 警告
notes() {
  sed -nE 's/^# (注意|注記|重要|警告): *(.*)$/\1|\2/p' "$1" | while IFS='|' read -r k n; do
    [ "$k" = 注意 ] && k=注記
    admonition "$k" "$n" "$2"
  done
}
# spec_section <見出し>: spec.md の "## 見出し" の中身 (次の ## まで)
spec_section() {
  awk -v h="## $1" '$0 == h {f = 1; next} /^## / {f = 0} f' spec.md |
    awk 'NF {for (; b > 0; b--) print ""; print; next} {b++}' | sed '/./,$!d'   # 前後の空行を除く
}
# spec_other: 前提条件・関連情報 以外の spec.md の節 (パラメータなど) をそのまま出す
spec_other() { awk '/^## / {f = ($0 != "## 前提条件" && $0 != "## 成功条件 (DoD)" && $0 != "## 関連情報")} f' spec.md; }
# script_step <ファイル> <タグ> <インデント> <ログ> <項目 (ブロックが 1 つ)> <項目 (ブロックが複数)> [<注記のファイル>]
#   ブロックが 1 つなら、項目の下にコマンドと出力例を出す。
#   複数なら、ブロックごとに「次のコマンドを実行して、<説明>。」のサブステップにして、コマンドと出力例を出す
#   (<項目 (ブロックが複数)> が空なら、親の項目を作らず、ブロックを <インデント> の番号付き手順にする)
#   <注記のファイル> があれば、その注記を項目の本文として出す (項目の前に出すと、番号付きリストが途中で切れる)
script_step() {
  local f=$1 tag=$2 c="$3   " log=$4 k n=0 m=0 d   # 項目の本文はリスト記号の分だけ下げる
  for ((k = 1; k <= $(blocks "$f"); k++)); do [ -n "$(block_part "$f" $k code)" ] && n=$((n + 1)); done
  if [ $n -le 1 ]; then
    # 項目が「次のコマンドを実行します。」だけのときは、ブロックの説明を使う
    d=""; for ((k = 1; k <= $(blocks "$f"); k++)); do [ -n "$(block_part "$f" $k code)" ] && d="$(block_part "$f" $k desc | head -1 | sed 's/。$//' | polite)"; done
    if [ -n "$d" ] && [[ $5 == *"次のコマンドを実行します。" ]]; then echo; echo "$3${5%次のコマンドを実行します。}次のコマンドを実行して、${d}。"
    else echo; echo "$3$5"; fi
    [ -z "${7:-}" ] || notes "$7" "$c"
    for ((k = 1; k <= $(blocks "$f"); k++)); do
      [ -n "$(block_part "$f" $k code)" ] || continue
      echo; block_part "$f" $k code | prompt | block terminal "$c"
      example "$log" "$tag" $k "$c"
    done
    return
  fi
  if [ -n "$6" ]; then echo; echo "$3$6"; [ -z "${7:-}" ] || notes "$7" "$c"; else c="$3"; fi
  for ((k = 1; k <= $(blocks "$f"); k++)); do
    [ -n "$(block_part "$f" $k code)" ] || continue
    m=$((m + 1)); d="$(block_part "$f" $k desc | head -1 | sed 's/。$//' | polite)"
    echo; echo "$c$m. 次のコマンドを実行${d:+して、$d}$([ -z "$d" ] && echo "します")。"
    echo; block_part "$f" $k code | prompt | block terminal "$c   "
    example "$log" "$tag" $k "$c   "
  done
}

cmd_doc() {
  [ -f spec.md ] || die "spec.md がありません"
  local result s b i=0 st log last="" I="   " II="      " j
  result="$(meta result)"
  [ -n "$(meta fp)" ] && [ "$(meta fp)" != "$(fingerprint)" ] && result=STALE
  for s in $(steps); do last="$(sid "$s")"; done
  # ステップ <b> の検証ログ (成功したステップの出力だけを出力例にする)
  steplog() {
    st="$(awk -F' *[|] *' -v b="$1" '$2==b {print $4}' run/result.md 2>/dev/null)"
    [ "$st" = OK ] && echo "run/logs/$1.log" || echo /dev/null
  }
  {
    head -1 spec.md
    echo
    # 概要 (タイトルの次から最初の ## まで)
    sed -n '2,/^## /p' spec.md | sed '/^## /d' | sed '/./,$!d'
    case "$result" in
      PASS)  admonition 注記 "この手順は $(meta date | tr T ' ')、OpenShift $(meta version) で検証済みです$([ "$(meta keep)" = 1 ] && echo "。切り戻しは検証していません")（詳細: run/result.md）。" "";;
      FAIL)  admonition 警告 "この手順は検証で失敗しています。使用しないでください（詳細: run/result.md）。" "";;
      INTERRUPTED) admonition 警告 "この手順の検証は中断されました。この手順は未検証です（詳細: run/result.md）。" "";;
      STALE) admonition 警告 "検証後に手順が変更されています。この手順は未検証です。" "";;
      *)     admonition 警告 "この手順は未検証です。" "";;
    esac
    echo
    echo "## 前提条件"
    echo
    spec_section 前提条件
    echo "- コマンドは、この手順書があるディレクトリ (manifests/ と scripts/ がある場所) で実行する。"
    [ -n "$(spec_other)" ] && { echo; spec_other; }
    echo
    echo "## 手順"
    for s in $(steps); do
      b="$(sid "$s")"; i=$((i+1)); log="$(steplog "$b")"; j=1
      echo
      echo "$i. $(title "$s" | polite)。"
      notes "$s" "$I"
      if [[ $s == *.yaml ]]; then
        echo; echo "${I}$j. 次の YAML を使用して \`$s\` ファイルを作成します。"; j=$((j+1))
        echo; yaml_body "$s" | block yaml "$II"
        yaml_where "$s" "$II"
        echo; echo "${I}$j. 次のコマンドを実行して、マニフェストを適用します。"; j=$((j+1))
        echo; echo "oc apply -f $s" | prompt | block terminal "$II"
        example "$log" apply 0 "$II"
      else
        script_step "$s" run "$I" "$log" "$j. 次のコマンドを実行します。" "$j. 次のコマンドを順に実行します。"; j=$((j+1))
      fi
      # 最後のステップの確認は「検証」に載せる
      [ "$b" = "$last" ] && continue
      script_step "$(chk "$b")" check "$I" "$log" \
        "$j. 次のコマンドを実行して、$(title "$(chk "$b")")ことを確認します。" "$j. $(title "$(chk "$b")")ことを確認します。" "$(chk "$b")"
    done
    echo
    echo "## 検証"
    notes "$(chk "$last")" ""
    script_step "$(chk "$last")" check "" "$(steplog "$last")" \
      "- 次のコマンドを実行して、$(title "$(chk "$last")")ことを確認します。" "- $(title "$(chk "$last")")ことを確認します。"
    # 成功条件 (DoD): 手順の確認とは分け、検証での達成状況をチェックリストで示す
    if [ -n "$(criteria)" ]; then
      echo
      echo "## 成功条件 (DoD)"
      echo
      if [ "$result" = PASS ] || [ "$result" = FAIL ]; then
        echo "$(meta date | tr T ' ') の検証で確認できた成功条件に [x] を付けています。"
      elif [ "$result" = STALE ]; then
        echo "検証後に手順が変更されているため、成功条件は未確認です。"
      else
        echo "この手順は検証されていないため、成功条件は未確認です。"
      fi
      echo
      criteria | while IFS='|' read -r b d; do
        case "$result" in PASS|FAIL) st="$(step_status "$b")";; STALE) st="検証後に変更";; *) st=未検証;; esac
        echo "$b|$d|$st"
      done | checklist index
    fi
    # 切り戻し: run (--cleanup) と cleanup と同じ順序 (rollback.sh → 適用した YAML を逆順に削除) で載せる
    echo
    echo "## 切り戻し"
    echo
    echo "この手順で作成・変更したものを削除し、手順を実行する前の状態に戻します。"
    # リソースを残して検証した (--keep) ときは、切り戻しの手順を実行していない
    if { [ "$result" = PASS ] || [ "$result" = FAIL ]; } && [ "$(meta keep)" = 1 ]; then
      admonition 重要 "この切り戻しの手順は、検証では実行していません。実行する前に、内容を確認してください。" ""
    fi
    notes scripts/rollback.sh ""
    # 複数のブロックは 1 つのスクリプトとして実行される (変数を引き継ぎ、止める条件で以降を実行しない)
    if [ "$(for ((k = 1; k <= $(blocks scripts/rollback.sh); k++)); do block_part scripts/rollback.sh $k code | head -1; done | grep -c .)" -gt 1 ]; then
      admonition 注記 "次のコマンドは、同じシェルで上から順に実行します。途中で「止めます」と表示された場合は、それ以降のコマンドを実行しないでください。" ""
    fi
    echo
    echo "### 手順"
    local rbn=0 k yamls out
    for ((k = 1; k <= $(blocks scripts/rollback.sh); k++)); do [ -n "$(block_part scripts/rollback.sh $k code)" ] && rbn=$((rbn + 1)); done
    [ $rbn = 0 ] || script_step scripts/rollback.sh rollback "" "$([ "$result" = PASS ] && [ -f run/logs/rollback.log ] && echo run/logs/rollback.log || echo /dev/null)" \
      "1. 次のコマンドを実行します。" ""
    yamls="$(steps | grep '\.yaml$' | { tac 2>/dev/null || tail -r; })"
    if [ -n "$yamls" ]; then
      echo; echo "$((rbn + 1)). 次のコマンドを実行して、作成したリソースを、適用したときと逆の順序で削除します。"
      echo; printf '%s\n' "$yamls" | sed 's/^/oc delete -f /; s/$/ --ignore-not-found/' | prompt | block terminal "   "
      out="$([ "$result" = PASS ] && grep -v '^\[OK\]' run/logs/cleanup.log 2>/dev/null | head -30)"
      [ -z "$out" ] || { echo; echo "   **出力例**"; echo; printf '%s\n' "$out" | block terminal "   "; }
    fi
    [ $rbn != 0 ] || [ -n "$yamls" ] || { echo; echo "戻すものはありません。"; }
    if [ -n "$(spec_section 関連情報)" ]; then
      echo; echo "## 関連情報"; echo; spec_section 関連情報
    fi
  } | cat -s > runbook.md
  echo "[OK] $DIR/$SLUG/runbook.md"
  [ "$result" = PASS ] || echo "[WARN] 検証結果が PASS ではありません (${result:-未検証})"
}

# --- main ---

usage() { awk 'NR == 1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"; exit 3; }
CMD="${1:-}"; SLUG="${2:-}"
case "$CMD" in
  cluster) cmd_cluster;;
  new)
    [[ $SLUG =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "usage: runbook.sh new <name> (英小文字・数字・ハイフン)"
    cmd_new;;
  lint|plan|run|cleanup|doc)
    [[ $SLUG =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "usage: runbook.sh $CMD <name>"
    cd "$DIR/$SLUG" 2>/dev/null || die "$DIR/$SLUG がありません"
    "cmd_$CMD" "${@:3}";;
  *) usage;;
esac
