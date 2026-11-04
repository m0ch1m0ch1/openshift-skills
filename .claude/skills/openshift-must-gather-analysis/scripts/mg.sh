#!/usr/bin/env bash
# must-gather を omc で調べ、確認事項のファイル (checklist.md) と調査報告 (report.md) を作る。クラスタには接続しない
#
# openshift-must-gather-analysis スキルが、次の順で使う (check → new → prepare → plan / items → overview → report → ns / cond / pod / logs / errors / count / events / grep / show → lint)
#
# 使い方 (<file> と <subpath> は、must-gather のルートからの相対パス):
#   mg.sh check                              omc の導入状況と、must-gather の置き場所を確認する
#   mg.sh list                               ケース (must-gather-analyses/<case>/) の一覧と、報告書の状態 (人が使う。スキルは使わない)
#   mg.sh new      [<case>]                  ケースのディレクトリを作り、must-gather を置く場所を表示する (ケース名の既定: 仮の new-<作成日時>)
#                                            置き場所の直下に置かれた must-gather があれば、このケースに移す
#   mg.sh prepare  <case>                    must-gather-analyses/<case>/must-gather/ に置いた must-gather を omc use で選ぶ
#                                            must-gather/ の外 (ケースのディレクトリの直下) に置かれていれば、must-gather/ に移す
#                                            アーカイブ (tar.gz / tgz / tar / tar.xz / zip) を置いた場合は、その場で展開し、元のアーカイブを消す
#                                            ケース名が仮の new-<作成日時> なら、must-gather の取得日時 (日本時間の YYYYMMDD-HHMMSS) に付け直す
#                                            (展開先の外を指すファイルを含むアーカイブは展開しない。外を指すシンボリックリンクを含む must-gather は omc で読まない)
#   mg.sh plan     <case>                    確認事項のファイル (checklist.md: 事象、確認事項、調査項目) のひな形を作る
#   mg.sh items    <case>                    checklist.md の確認事項と調査項目を、進み具合 (調べ済みの数) と一緒に表示する
#   mg.sh overview <case>                    異常の概要 (ClusterVersion と最近のアップデート、ClusterOperator、ノード、Pod、MCP、アラート、Warning イベント)。調査の起点を探すために使う
#   mg.sh ns       <case> [<ns>]             Namespace について、must-gather に含まれるリソースと、Pod のログの有無・期間を表示する
#                                            (引数が無ければ、OpenShift 以外の Namespace の一覧と、Pod・ログの数)
#   mg.sh cond     <case> <file>             リソースの status.conditions を、条件ごとに 1 行で行番号付きで表示する (ClusterOperator、ノード、MCP など)
#   mg.sh pod      <case> <ns> <pod>         Pod の phase と、コンテナごとの状態・前回の終了・再起動の回数・ログの期間を表示する
#   mg.sh logs     <case> <ns> <pod> [<container>] [<regex>] [--previous]
#                                            コンテナのログを「ファイル:行: 内容」で表示する (regex があれば検索、無ければ末尾)
#                                            先頭にログのファイルと期間を表示する。ログが取得されていなければ、Pod の YAML にあるコンテナの終了メッセージを表示する
#   mg.sh errors   <case> <file>             klog 形式のエラー (E / F) を、ソースの場所と内容ごとに数える (Pod のログ、host_service_logs/ のサービスログ)
#   mg.sh count    <case> <regex> <file> [hour|minute]
#                                            regex に一致する行を、1 時間ごと (既定) か 1 分ごとに数える
#   mg.sh events   <case> [<ns>] [<regex>]   イベントを時刻順に表示する (regex で絞り込む。-A は全 Namespace)
#   mg.sh grep     <case> <regex> [<subpath>]  must-gather の中を検索し、「ファイル:行: 内容」で表示する (根拠の行番号を得る)
#                                            多すぎるとき (MG_MAX 件を超える) は、ファイルごとの件数を表示する
#   mg.sh show     <case> <file> <line> [<n>]  ファイルの指定した行の前後 n 行 (既定: 5) を、行番号付きで表示する
#   mg.sh report   <case>                    報告書 (report.md) のひな形を作る。事象と確認事項は checklist.md から写す
#                                            報告書が既にあれば、事象と確認事項だけを checklist.md から写し直す
#   mg.sh lint     <case>                    checklist.md と report.md を確認する (必須の節、TODO、事象と確認事項の一致、確認事項ごとの調査項目と回答、
#                                            調査項目の結果、根拠のファイルと行が実在し引用と一致するか、事実の番号、
#                                            未確認事項のコマンドと情報元の URL (無ければ WARN))
#   (終了コード: 0=OK 1=lint などの NG 3=開始できない 10=omc が無い)
#
# 環境変数:
#   ANALYSIS_DIR  調査 (ケース) を置くディレクトリ (既定: リポジトリのルートの must-gather-analyses/。ルートはスクリプトの場所から決める)
#   MG_MAX        各サブコマンドが表示する最大行数 (既定: 50)
#   OMCCONFIG     omc の設定ファイル (どの must-gather を使うか)。既定: must-gather-analyses/.omc/omc.json (~/.omc の代わり)
#
# ケースのディレクトリ: must-gather-analyses/<case>/ の must-gather/ (調べる対象)、checklist.md (事象・確認事項・調査項目)、report.md (調査報告)
#
# 根拠の書き方: must-gather のルート (cluster-scoped-resources があるディレクトリ) からの相対パスと行番号を、
#   `namespaces/<ns>/pods/<pod>/<container>/<container>/logs/current.log:120` (範囲は :120-125) の形で書く
set -uo pipefail
# リポジトリのルートは、実行した場所ではなく、スクリプトの場所 (.claude/skills/<skill>/scripts/) から決める
TOP="$(cd "$(dirname "$0")/../../../.." && pwd)"
DIR="${ANALYSIS_DIR:-$TOP/must-gather-analyses}"
OMCCONFIG="${OMCCONFIG:-$DIR/.omc/omc.json}"
case "$OMCCONFIG" in /*) ;; *) OMCCONFIG="$TOP/$OMCCONFIG";; esac
export OMCCONFIG
MAX="${MG_MAX:-50}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SECTIONS="概要 事象 確認事項 時系列 確認した事実 原因 対処案 未確認事項 情報元"   # report.md の節
CL_SECTIONS="事象 確認事項 調査項目"                                                  # checklist.md の節

die() { echo "[NG] $*"; exit 3; }
# has <grep の引数>: 標準入力に一致する行があるか。pipefail のもとで grep -q は偽になることがあるため、入力を最後まで読む
has() { grep "$@" >/dev/null; }
# rel <パス>: must-gather のルートからの相対パスで、ルートの外を指さない (絶対パスや .. を含まない) ことを確かめる
rel() { case "/$1/" in //*|*/../*) die "パスは must-gather のルートからの相対パスで、.. を含めずに指定する: $1";; esac; }
# name <名前>: Namespace や Pod の名前に、パスの区切り (/ や ..) が含まれないことを確かめる
name() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $1 != *..* ]] || die "名前が正しくありません: $1"; }

# root <case>: must-gather のルート。複数あるとき (ODF などの追加の must-gather) は ClusterVersion を含むものを優先する
root() {
  local d best=""
  while IFS= read -r d; do
    d="${d%/cluster-scoped-resources}"
    [ -n "$best" ] || best="$d"
    if [ -d "$d/cluster-scoped-resources/config.openshift.io/clusterversions" ]; then best="$d"; break; fi
  done < <(find "$DIR/$1/must-gather" -maxdepth 6 -type d -name cluster-scoped-resources 2>/dev/null | LC_ALL=C sort)
  [ -n "$best" ] && echo "$best"
}
need_root() {
  R="$(root "$SLUG")" || { echo "[NG] $DIR/$SLUG/must-gather/ に must-gather が見つかりません (cluster-scoped-resources を含むディレクトリ)"; echo "案内: must-gather のアーカイブか、展開したディレクトリを $DIR/$SLUG/must-gather/ に置いてから、mg.sh prepare $SLUG を実行する"; exit 3; }
  RR="$(cd -P "$R" && pwd -P)"   # シンボリックリンクを辿った、ルートの実際の場所
}
# inside <パス>: 実際の場所 (途中のシンボリックリンクを辿った先) が、must-gather のルートの下にあるか
inside() {
  local d
  if [ -d "$1" ]; then d="$(cd -P "$1" 2>/dev/null && pwd -P)"; else d="$(cd -P "$(dirname "$1")" 2>/dev/null && pwd -P)"; fi || return 1
  case "$d/" in "$RR"/*) return 0;; esac; return 1
}
# ok_file <パス>: must-gather のルートからの相対パスで、ルートの下にある普通のファイル (シンボリックリンクでない) か
ok_file() { case "/$1/" in //*|*/../*) return 1;; esac; [ -f "$R/$1" ] && [ ! -L "$R/$1" ] && inside "$R/$1"; }
need_file() { ok_file "$1" || die "$1 がありません (must-gather のルートからの相対パスで指定する。.. やシンボリックリンク、ルートの外を指すものは読まない)"; }
need_omc() { command -v omc >/dev/null 2>&1 || { echo "[NG] omc がありません"; echo "次: mg.sh check"; exit 10; }; }
# no_outside_links: omc はシンボリックリンクを辿って読むため、must-gather/ の中に、絶対パスか .. を指すシンボリックリンクがあれば使わない
#   (どのリンクも、そのディレクトリの下だけを指していれば、リンクを辿っても must-gather/ の外には出ない)
no_outside_links() {
  local l t
  while IFS= read -r l; do
    t="$(readlink "$l")"
    case "/$t/" in //*|*/../*) echo "[NG] must-gather の外を指す可能性のあるシンボリックリンクがあるため、omc では読みません: ${l#"$DIR"/} -> $t"
      echo "案内: must-gather を取り直すか、そのシンボリックリンクを消すかをユーザーに聞く"; exit 3;; esac
  done < <(find "$DIR/$SLUG/must-gather" -type l 2>/dev/null)
}
# use_mg: omc の対象を、このケースの must-gather にする (omc use は全体の設定なので、毎回選び直す)
use_mg() { need_root; need_omc; no_outside_links; mkdir -p "$(dirname "$OMCCONFIG")"; omc use "$R" >/dev/null 2>&1 || die "omc use に失敗しました: $R"; }
# lim: 標準入力を最大 MAX 行に絞る。見出しの行だけのときは「該当なし」
lim() {
  awk -v max="$MAX" '
    NF == 0 { next }
    { n++ }
    n == 1 { first = $0; next }
    n == 2 { print substr(first, 1, 300) }
    n <= max { print substr($0, 1, 300) }
    END {
      if (n == 0 || (n == 1 && first ~ /^(NAME|NAMESPACE|LAST SEEN|GROUP)[ \t]/)) print "(該当なし)"
      else if (n == 1) print substr(first, 1, 300)
      else if (n > max) print "... (全 " n " 行のうち先頭 " max " 行。絞り込んで調べる)"
    }'
}
# og <omc の引数>: omc を実行する。取得できないとき (エラー) は、「該当なし」と区別できるように [WARN] を出す
og() {
  local out
  if ! out="$(omc "$@" 2>&1)" || printf '%s\n' "$out" | head -1 | has '^Error'; then
    echo "[WARN] 取得できません (omc $*): $(printf '%s\n' "$out" | head -1 | cut -c1-200)"; return 0
  fi
  printf '%s\n' "$out"
}
# version_of <root>: must-gather のクラスタのバージョン (ClusterVersion の status.desired.version)
version_of() {
  local f="$1/cluster-scoped-resources/config.openshift.io/clusterversions/version.yaml"
  [ -f "$f" ] || { echo 不明; return 0; }
  { sed -n '/^  desired:/,/^  [a-z]/p' "$f" | sed -n 's/^    version: *//p'
    sed -n 's/^  desired: *{.*version: *\([^,} ]*\).*/\1/p' "$f"; echo 不明; } | head -1
}
# history_of <root>: ClusterVersion の status.history (アップデートの履歴) の新しい 3 件
history_of() {
  local p="cluster-scoped-resources/config.openshift.io/clusterversions/version.yaml"
  [ -f "$1/$p" ] || { echo "[WARN] $p がありません"; return 0; }
  printf '%-12s %-10s %-22s %s\n' VERSION STATE STARTED COMPLETED
  awk '
    function out() { if (ver != "") printf "%-12s %-10s %-22s %s\n", ver, st, s, (c == "" || c == "null" ? "-" : c); ver = st = s = c = "" }
    /^  history:/ { h = 1; next }
    h && /^  [^ -]/ { exit }
    h && /^  - / { out(); if (++n > 3) exit }
    h {
      l = $0; sub(/^  - /, "", l); sub(/^ +/, "", l)
      k = l; sub(/:.*/, "", k); v = l; sub(/^[^:]*: */, "", v); gsub(/"/, "", v)
      if (k == "version") ver = v; else if (k == "state") st = v; else if (k == "startedTime") s = v; else if (k == "completionTime") c = v
    }
    END { out() }' "$1/$p"
  echo "根拠: $p (行番号は mg.sh grep で得る)"
}
taken_at() { if [ -f "$1/timestamp" ]; then head -1 "$1/timestamp" | sed 's/ m=.*//' | cut -c1-60; else echo 不明; fi; }   # must-gather の取得日時
# jst <root> <date の書式>: must-gather の取得日時 (UTC) を、日本時間の指定の書式で出す。分からなければ何も出さない
jst() {
  local t s
  [ -f "$1/timestamp" ] || return 0
  t="$(head -1 "$1/timestamp" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')" || return 0
  # date は GNU (Linux) と BSD (macOS) で書き方が違うため、両方を試す
  s="$(date -u -d "$t" '+%s' 2>/dev/null || date -j -u -f '%Y-%m-%d %H:%M:%S' "$t" '+%s' 2>/dev/null)" || return 0
  TZ=Asia/Tokyo date -d "@$s" "$2" 2>/dev/null || TZ=Asia/Tokyo date -r "$s" "$2"
}
# name_of <root>: must-gather から付けるケース名。取得日時 (日本時間) の YYYYMMDD-HHMMSS
name_of() { jst "$1" '+%Y%m%d-%H%M%S'; }

# loose: 置き場所の直下に置かれた must-gather (ディレクトリかアーカイブ。ケースのディレクトリ以外)
loose() {
  local f
  for f in "$DIR"/*; do
    [ -e "$f" ] || continue
    [ -d "$f/must-gather" ] && continue
    if [ -d "$f" ] && find "$f" -maxdepth 6 -type d -name cluster-scoped-resources 2>/dev/null | has .; then echo "$f"
    elif [ -f "$f" ]; then case "$f" in *.tar.gz|*.tgz|*.tar.xz|*.tar|*.zip) echo "$f";; esac; fi
  done
}

# --- check / list / new / prepare ---

cmd_check() {
  if command -v omc >/dev/null 2>&1; then
    # omc version は、選んでいる must-gather が無いとき、先頭にそのエラーを出すため、バージョンの行だけを使う
    local v; v="$(omc version 2>&1 | grep -oE 'v[0-9][0-9.]*' | head -1)"
    echo "[OK] omc: ${v:-バージョン不明} ($(command -v omc))"
  else
    echo "[NG] omc がありません"
    echo "案内: 入れ方は https://github.com/gmeghnag/omc#installation を参照する (入れたら、PATH の通ったディレクトリに置く)"
    return 10
  fi
  echo "[OK] must-gather の置き場所: $DIR"
  [ -d "$DIR" ] || echo "[WARN] $DIR がありません (new で作る)"
}

cmd_list() {
  local c r st f m
  while IFS= read -r f; do echo "[WARN] ケースに入っていない must-gather: ${f#$DIR/} (mg.sh new で、新しいケースに移す)"; done < <(loose)
  ls -d "$DIR"/*/must-gather >/dev/null 2>&1 || { echo "$DIR/ にケースはありません"; return 0; }
  echo "| ケース | must-gather | 取得日時 | バージョン | 報告書 |"
  echo "|---|---|---|---|---|"
  for c in "$DIR"/*/must-gather; do
    c="$(basename "$(dirname "$c")")"
    r="$(root "$c")"
    if [ ! -f "$DIR/$c/report.md" ]; then st=なし
    elif ! ( SLUG="$c"; cmd_lint ) 2>&1 | has -E '^\[(NG|WARN)\]'; then st=完成
    else st=作成中; fi
    m="${r#$DIR/$c/must-gather/}"; [ "${m%%/*}" = "$m" ] || m="${m%%/*}/…"   # 長いディレクトリ名 (quay-io-…sha256-…) は省く
    if [ -n "$r" ]; then echo "| $c | $m | $(taken_at "$r") | $(version_of "$r") | $st |"
    else echo "| $c | 見つからない | - | - | $st |"; fi
  done
}

# new [<case>]: ケースのディレクトリを作り、must-gather を置く場所を表示する
cmd_new() {
  local c="${SLUG:-new-$(date '+%Y%m%d-%H%M%S')}"
  [[ $c =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "ケース名は英小文字・数字・._- にする: $c"
  [ ! -e "$DIR/$c" ] || { echo "[NG] $DIR/$c は既にあります"; echo "案内: 別のケース名にする"; exit 3; }
  local f moved=0
  mkdir -p "$DIR/$c/must-gather"
  echo "[OK] ケース: $c"
  while IFS= read -r f; do
    mv "$f" "$DIR/$c/must-gather/" && { echo "移しました: ${f#$DIR/} → $c/must-gather/"; moved=1; }
  done < <(loose)
  if [ $moved = 1 ]; then echo "次: mg.sh prepare $c"; return 0; fi
  echo "must-gather を置く場所: $DIR/$c/must-gather/"
  echo "案内: must-gather のアーカイブ (tar.gz など) か、展開したディレクトリを、上の場所に置く (コピーか移動)"
  echo "次: 置いたら mg.sh prepare $c"
}

# prepare <case>: ケースの must-gather/ に置いたものを使う。アーカイブはその場で展開する
cmd_prepare() {
  local c="$DIR/$SLUG/must-gather" a d
  [ -d "$c" ] || die "$c がありません (先に mg.sh new)"
  # 展開済みの must-gather が無ければ、置かれたアーカイブを展開する
  if ! root "$SLUG" >/dev/null; then
    # must-gather/ の外 (ケースのディレクトリの直下) に置かれた must-gather は、must-gather/ に移す
    for a in "$DIR/$SLUG"/*; do
      case "${a##*/}" in must-gather|checklist.md|report.md) continue;; esac
      [ -e "$a" ] && [ ! -L "$a" ] || continue
      if [ -d "$a" ]; then find "$a" -maxdepth 6 -type d -name cluster-scoped-resources 2>/dev/null | has . || continue
      else case "$a" in *.tar.gz|*.tgz|*.tar.xz|*.tar|*.zip) ;; *) continue;; esac; fi
      mv "$a" "$c/" || die "移せません: $a"
      echo "移しました: ${a#$DIR/} → $SLUG/must-gather/"
    done
    while IFS= read -r a; do
      echo "展開します: ${a#$c/}"
      # 中のファイルが、絶対パスや .. で展開先 (ケースのディレクトリ) の外を指していれば、展開しない
      case "$a" in
        *.zip) unzip -Z1 "$a" ;;
        *)     tar tf "$a" ;;
      esac 2>/dev/null | has -E '^/|(^|/)\.\.(/|$)' && die "展開先の外を指すファイルが含まれるため、展開しません: $a"
      # 途中で止まった展開をやり直すときに、残ったファイルを上書きする (tar と同じ。unzip は聞いてきて、入力が無いと失敗する)
      case "$a" in
        *.tar.gz|*.tgz) tar xzf "$a" -C "$c" || die "展開できません: $a";;
        *.tar.xz)       tar xJf "$a" -C "$c" || die "展開できません: $a";;
        *.tar)          tar xf  "$a" -C "$c" || die "展開できません: $a";;
        *.zip)          unzip -oq "$a" -d "$c" || die "展開できません: $a";;
      esac
      rm -f "$a" && echo "元のアーカイブを消しました: ${a#$c/}"
    done < <(find "$c" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' -o -name '*.tar.xz' -o -name '*.tar' -o -name '*.zip' \) | LC_ALL=C sort)
  fi
  need_root
  local base to n=1
  if [[ $SLUG =~ ^new-[0-9]{8}-[0-9]{6}$ ]] && base="$(name_of "$R")" && [ -n "$base" ]; then
    to="$base"
    while [ -e "$DIR/$to" ]; do n=$((n + 1)); to="$base-$n"; done   # 同じ名前のケースがあれば -2, -3, …
    mv "$DIR/$SLUG" "$DIR/$to" || die "ケース名を変えられません: $SLUG → $to"
    echo "[OK] ケース名を変えました: $SLUG → $to"
    SLUG="$to"; need_root
  fi
  use_mg
  echo "[OK] ケース: $SLUG"
  echo "[OK] must-gather: $R"
  local j; j="$(jst "$R" '+%Y-%m-%d %H:%M:%S')"
  echo "取得日時: $(taken_at "$R") (日本時間: ${j:-不明})"
  echo "クラスタのバージョン: $(version_of "$R")"
  # 追加の must-gather (ODF など) があれば知らせる
  while IFS= read -r d; do
    d="${d%/cluster-scoped-resources}"
    case "$d/" in "$R"/*) continue;; esac   # 本体の中のサブフォルダ (istio など) は除く
    echo "ほかの must-gather: $d"
  done < <(find "$c" -maxdepth 6 -type d -name cluster-scoped-resources 2>/dev/null | LC_ALL=C sort)
  echo "次: 取得日時とバージョンを示して事象を確認し、mg.sh plan $SLUG で確認事項のファイルを作る"
}

# --- overview / grep / show ---

cmd_overview() {
  use_mg
  echo "must-gather: $R (取得日時: $(taken_at "$R")、バージョン: $(version_of "$R"))"
  echo; echo "## ClusterVersion"
  og get clusterversion | lim
  echo; echo "## 最近のアップデート (新しい順に 3 件。時刻は UTC。事象の時刻と重なっていないかを見る)"
  history_of "$R"
  echo; echo "## ClusterOperator (Available でない、Progressing、Degraded のもの)"
  og get clusteroperators | awk 'NR == 1 || $3 != "True" || $4 == "True" || $5 == "True"' | lim
  echo; echo "## ノード (Ready でないもの)"
  og get nodes | awk 'NR == 1 || $2 != "Ready"' | lim
  echo; echo "## Pod (Running / Completed でない、コンテナが揃っていない、再起動が 5 回以上のもの)"
  og get pods -A | awk 'NR == 1 { print; next }
    { split($3, a, "/") }
    ($4 != "Running" && $4 != "Completed" && $4 != "Succeeded") || ($4 == "Running" && a[1] != a[2]) || ($5 + 0 >= 5)' | lim
  echo; echo "## MachineConfigPool (更新が終わっていない、Degraded のもの)"
  og get machineconfigpools | awk 'NR == 1 || $3 != "True" || $4 == "True" || $5 == "True"' | lim
  echo; echo "## 発生中のアラート (常に発生している Watchdog を除く)"
  og prom rules -s firing -o wide | awk 'NR == 1 || $2 != "Watchdog"' | lim
  echo; echo "## Warning イベント (Namespace・理由・メッセージの先頭ごとの件数。多い順)"
  # 同じイベントが大量に出ると一覧が埋まるため、種類ごとにまとめる
  og get events -A | awk 'NR > 1 && $3 == "Warning" {
      m = ""; for (i = 6; i <= NF; i++) m = m " " $i
      # IP や ID の違いでは分けない
      gsub(/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, "<IP>", m); gsub(/[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+/, "<ID>", m)
      k = sprintf("%-40s %-28s %s", $1, $4, substr(m, 2, 90)); c[k]++
    }
    END { for (k in c) printf "%6d  %s\n", c[k], k }' | sort -rn | lim
  echo
  echo "次: 事象が現れている場所を起点として示す。事象と関係のない異常は追わない"
}

cmd_grep() {
  local re="${1:-}" sub="${2:-.}" out n cnt
  [ -n "$re" ] || die "usage: mg.sh grep <case> <regex> [<subpath>]"
  rel "$sub"; need_root
  [ -e "$R/$sub" ] && [ ! -L "$R/$sub" ] && inside "$R/$sub" || die "$sub がありません (must-gather のルートからの相対パスで指定する。シンボリックリンクや、ルートの外を指すものは検索しない)"
  # 一致が大量にあり得るため、先頭の MAX+1 件だけを受け取る
  out="$(cd "$R" && grep -rnHIE --exclude='*.gz' -e "$re" "$sub" 2>/dev/null | head -n "$((MAX + 1))" | sed 's|^\./||')"
  n="$(printf '%s\n' "$out" | grep -c .)"
  [ "$n" -gt 0 ] || { echo "(該当なし)"; return 0; }
  if [ "$n" -gt "$MAX" ]; then
    # 多すぎるときは中身を出さず、ファイルごとの件数を出す (ファイル 1 つにつき 1 行なので小さい)
    cnt="$(cd "$R" && grep -rcHIE --exclude='*.gz' -e "$re" "$sub" 2>/dev/null | grep -v ':0$' | sed 's|^\./||')"
    echo "全 $(printf '%s\n' "$cnt" | awk -F: '{ t += $NF } END { print t }') 件。ファイルごとの件数 (多い順に 20 件):"
    printf '%s\n' "$cnt" | awk -F: '{ c = $NF; sub(/:[0-9]+$/, ""); printf "%7d %s\n", c, $0 }' | sort -rn | head -n 20
    echo "次: 正規表現かパス (<subpath>) で $MAX 件以下に絞り込む"
    return 0
  fi
  # 内容だけを 300 文字で切る (パスが長くても、内容が切れないように)
  printf '%s\n' "$out" | awk '{ if (match($0, /^[^:]*:[0-9]+:/)) print substr($0, 1, RLENGTH) substr($0, RLENGTH + 1, 300); else print substr($0, 1, 300) }'
  echo "次: 根拠にする行は mg.sh show $SLUG <file> <line> で前後を確かめる"
}

cmd_show() {
  local f="${1:-}" l="${2:-}" n="${3:-5}" total s e
  [[ $l =~ ^[0-9]+$ && $n =~ ^[0-9]+$ ]] || die "usage: mg.sh show <case> <file> <line> [<n>]"
  need_root; need_file "$f"
  total="$(awk 'END { print NR }' "$R/$f")"   # wc -l は、末尾に改行の無い最後の行を数えない
  [ "$l" -ge 1 ] && [ "$l" -le "$total" ] || die "$f に $l 行目はありません (全 $total 行)"
  s=$((l - n)); [ "$s" -ge 1 ] || s=1; e=$((l + n))
  awk -v s="$s" -v e="$e" -v l="$l" 'NR >= s && NR <= e { printf "%s%7d  %s\n", (NR == l ? ">" : " "), NR, substr($0, 1, 300) } NR > e { exit }' "$R/$f"
  echo "根拠の書き方: \`$f:$l\`"
}

# logs <ns> <pod> [<container>] [<regex>] [--previous]: ログのファイルを特定し、根拠に使える形で表示する
#   Pod 名の次の引数がコンテナ名と一致すればコンテナ、それ以外は検索の正規表現として扱う
cmd_logs() {
  local ns="${1:-}" pod="${2:-}" c="" re="" prev=0 a d f n out cs
  [ -n "$ns" ] && [ -n "$pod" ] || die "usage: mg.sh logs <case> <ns> <pod> [<container>] [<regex>] [--previous]"
  shift 2
  name "$ns"; name "$pod"; need_root
  d="namespaces/$ns/pods/$pod"
  [ -d "$R/$d" ] && inside "$R/$d" || { echo "[NG] $d がありません"; echo "案内: Pod 名は omc get pods -n $ns で確かめる"; exit 3; }
  cs="$(find "$R/$d" -mindepth 1 -maxdepth 1 -type d -exec basename {} ';' | LC_ALL=C sort)"
  for a in "$@"; do
    if [ "$a" = --previous ]; then prev=1
    elif [ -z "$c" ] && [ -z "$re" ] && printf '%s\n' "$cs" | has -xF -- "$a"; then c="$a"
    else re="$a"; fi
  done
  if [ -z "$c" ]; then
    [ "$(printf '%s\n' "$cs" | grep -c .)" = 1 ] || { echo "[NG] コンテナを指定する: $(printf '%s ' $cs)"; exit 3; }
    c="$cs"
  fi
  f="$d/$c/$c/logs/$([ $prev = 1 ] && echo previous || echo current).log"
  ok_file "$f" || { echo "[NG] $f がありません"; [ $prev = 0 ] || echo "案内: 再起動前のログは取得されていない"; exit 3; }
  # ログを取得できていなければ、Pod の YAML にある終了メッセージ (terminated.message。小さい) を使う
  if head -1 "$R/$f" | has '^unable to retrieve container logs'; then
    echo "[WARN] ログは取得されていません ($f: $(head -1 "$R/$f" | cut -c1-80))"
    f="$d/$pod.yaml"
    out="$(term_msg "$R/$f" "$c" "$([ $prev = 1 ] && echo lastState || echo state)")"
    [ -n "$out" ] || { echo "案内: 終了メッセージもありません。omc describe pod $pod -n $ns で状態を確かめる"; return 0; }
    echo "代わりに、コンテナの終了メッセージ (terminated.message) を表示します: $f"
    # 終了メッセージは YAML の連続した行なので、先頭の行番号から数える
    if [ -n "$re" ]; then printf '%s\n' "$out" | cut -f2- | match_lines "$f" "$re" "${out%%	*}"; else printf '%s\n' "$out" | tail -n "$MAX" | fmt_lines "$f"; fi
    return 0
  fi
  # ログのファイルは大きいことがあるため、変数に読み込まず、先頭から 1 回だけ流して読む
  echo "ログ: $f (期間: $(log_range "$R/$f"))"
  if [ -n "$re" ]; then
    match_lines "$f" "$re" 1 < "$R/$f"
  else
    n="$(awk 'END { print NR }' "$R/$f")"
    tail -n "$MAX" "$R/$f" | awk -v o="$(( n > MAX ? n - MAX : 0 ))" '{ print o + NR "\t" $0 }' | fmt_lines "$f"
    [ "$n" -le "$MAX" ] || echo "(全 $n 行のうち末尾 $MAX 行。regex で検索する)"
  fi
}

# 「ファイル:行: 内容」の内容は 300 文字で切る。パスが長くても、内容 (エラーメッセージ) が切れないよう、パスは切らない
# fmt_lines <file>: 標準入力の「行番号<TAB>内容」を、「ファイル:行: 内容」で出す
fmt_lines() { awk -v f="$1" '{ l = $0; sub(/^[^\t]*\t/, "", l); split($0, a, "\t"); print f ":" a[1] ":" substr(l, 1, 300) }'; }
# match_lines <file> <regex> <先頭の行番号>: 標準入力の行のうち regex に一致する行の先頭 MAX 件を、「ファイル:行: 内容」で出す
match_lines() {
  grep -nE -e "$2" | awk -v f="$1" -v base="$3" -v max="$MAX" '
    { i = index($0, ":"); n++; if (n <= max) print f ":" (base + substr($0, 1, i - 1) - 1) ":" substr($0, i + 1, 300) }
    END { if (!n) print "(該当なし: " f ")"; else if (n > max) print "... (全 " n " 件のうち先頭 " max " 件。正規表現で絞り込む)" }'
}

# log_range <ログのファイル>: 先頭と末尾の行の時刻 (ログの期間)
log_range() {
  [ -s "$1" ] || { echo "ログは空 (取得されていない)"; return 0; }
  echo "$(head -1 "$1" | line_time) 〜 $(tail -1 "$1" | line_time)"
}
# line_time: 標準入力の行の先頭の時刻 (Pod のログは YYYY-MM-DDTHH:MM:SS、ノードのサービスログは Mon DD HH:MM:SS)
line_time() {
  local l; IFS= read -r l
  case "$l" in
    [A-Z][a-z][a-z]\ *) printf '%s\n' "${l:0:15}";;
    *) printf '%s\n' "${l%% *}" | cut -c1-19;;
  esac
}

# count <regex> <file> [hour|minute]: regex に一致する行を、1 時間ごと (既定) か 1 分ごとに数える
#   ログの時刻は、Pod のログ (YYYY-MM-DDTHH:MM:SS…) と、ノードのサービスログ (Mon DD HH:MM:SS…) の形に対応する
cmd_count() {
  local re="${1:-}" f="${2:-}" unit="${3:-hour}" out n
  [ -n "$re" ] && [ -n "$f" ] || die "usage: mg.sh count <case> <regex> <file> [hour|minute]"
  case "$unit" in hour|minute) ;; *) die "単位は hour か minute にする: $unit";; esac
  need_root; need_file "$f"
  out="$(grep -E -e "$re" "$R/$f" | awk -v u="$unit" '
    {
      if (match($0, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]/)) { t = substr($0, 1, 16); sub(/T/, " ", t) }
      else if (match($0, /^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9][0-9]:[0-9][0-9]/)) t = substr($0, 1, 12)
      else t = ""
      if (t != "" && u == "hour") t = substr(t, 1, length(t) - 3) ":xx"
      if (t == "") t = "(時刻なし)"
      if (!(t in c)) o[++k] = t
      c[t]++
    }
    END { for (i = 1; i <= k; i++) printf "%7d  %s\n", c[o[i]], o[i] }')"
  n="$(printf '%s\n' "$out" | grep -c .)"
  [ "$n" -gt 0 ] || { echo "(該当なし: ${f}。ログの期間: $(log_range "$R/$f"))"; return 0; }
  echo "  件数  時刻 (${f}。ログの期間: $(log_range "$R/$f"))"
  printf '%s\n' "$out" | head -n "$MAX"
  [ "$n" -le "$MAX" ] || echo "... (全 $n 行のうち先頭 $MAX 行。regex に時刻を入れて絞り込む)"
  echo "次: 増えた時刻の前後を mg.sh grep $SLUG '<時刻>' $f で見る"
}

# cond <file>: リソースの status.conditions を、条件ごとに 1 行で表示する (ClusterOperator、ノード、MCP、Operator のリソースなど)
cmd_cond() {
  local f="${1:-}"
  [ -n "$f" ] || die "usage: mg.sh cond <case> <file>"
  need_root; need_file "$f"
  awk '
    function out() { sub(/["\x27]$/, "", m); if (t != "") printf "%s=%s  reason=%s  (%s 〜)  [type: %d 行目, message: %s 行目]\n    %s\n", t, s, (r == "" ? "-" : r), lt, tl, (ml == "" ? "-" : ml), substr(m, 1, 250); t = s = r = m = lt = ml = ""; tl = 0 }
    /^  conditions:/ { c = 1; next }
    c && /^  [^ -]/ { out(); c = 0 }
    !c { next }
    /^  - / { out() }
    { l = $0; sub(/^  - /, "    ", l) }
    mc && l ~ /^      / { v = l; sub(/^ */, "", v); m = m " " v; next }   # 複数行にわたる message の続き
    { mc = 0 }
    l ~ /^    type: /               { t = l; sub(/^ *type: */, "", t); tl = NR }
    l ~ /^    status: /             { s = l; sub(/^ *status: */, "", s); gsub(/"/, "", s) }
    l ~ /^    reason: /             { r = l; sub(/^ *reason: */, "", r) }
    l ~ /^    lastTransitionTime: / { lt = l; sub(/^ *lastTransitionTime: */, "", lt); gsub(/"/, "", lt) }
    l ~ /^    message: /            { m = l; sub(/^ *message: */, "", m); sub(/^[|>]-?$/, "", m); gsub(/^["\x27]|["\x27]$/, "", m); ml = NR; mc = 1 }
    END { out() }' "$R/$f" | lim
  echo "根拠の書き方: \`$f:<行>\` (message の行を引用する)"
}

# pod <ns> <pod>: Pod の状態と、コンテナごとの状態・前回の終了・再起動の回数・ログの有無を表示する
cmd_pod() {
  local ns="${1:-}" pod="${2:-}" f d c lf
  [ -n "$ns" ] && [ -n "$pod" ] || die "usage: mg.sh pod <case> <ns> <pod>"
  name "$ns"; name "$pod"; need_root
  d="namespaces/$ns/pods/$pod"; f="$d/$pod.yaml"
  ok_file "$f" || { echo "[NG] $f がありません"; echo "案内: Pod 名は omc get pods -n $ns で確かめる"; exit 3; }
  echo "Pod: $f"
  awk '
    function st(p) { return (k[p] == "" ? "-" : k[p] (rs[p] == "" ? "" : "(" rs[p] ")") (ec[p] == "" ? "" : " exit=" ec[p]) (sa[p] == "" ? "" : " " sa[p]) (fa[p] == "" ? "" : " 〜 " fa[p]) (ln[p] == "" ? "" : " [" ln[p] " 行目]")) }
    function out() { if (n != "") buf = buf sprintf("  %s%s: ready=%s restarts=%s\n    いま: %s\n    前回: %s\n", n, (init ? " (init)" : ""), rd, rc, st("state"), st("lastState")); n = rd = rc = ""; split("", k); split("", rs); split("", ec); split("", sa); split("", fa); split("", ln) }
    /^  phase: /     { ph = $2 }
    /^  nodeName: /  { nd = $2 }
    /^  startTime: / { stt = $2; gsub(/"/, "", stt) }
    /^  (init)?[cC]ontainerStatuses:/ { out(); cs = 1; init = ($0 ~ /init/); next }
    cs && /^  [^ -]/ { out(); cs = 0 }
    !cs { next }
    /^  - / { out() }
    { l = $0; sub(/^  - /, "    ", l) }
    l ~ /^    name: /         { n = l; sub(/^ *name: */, "", n) }
    l ~ /^    ready: /        { rd = l; sub(/^ *ready: */, "", rd) }
    l ~ /^    restartCount: / { rc = l; sub(/^ *restartCount: */, "", rc) }
    l ~ /^    (state|lastState):/ { p = l; sub(/^ */, "", p); sub(/:.*/, "", p) }
    l ~ /^      (running|waiting|terminated):/ { kk = l; sub(/^ */, "", kk); sub(/:.*/, "", kk); k[p] = kk }
    l ~ /^        reason: /     { v = l; sub(/^ *reason: */, "", v); rs[p] = v; ln[p] = NR }
    l ~ /^        exitCode: /   { v = l; sub(/^ *exitCode: */, "", v); ec[p] = v }
    l ~ /^        startedAt: /  { v = l; sub(/^ *startedAt: */, "", v); gsub(/"/, "", v); sa[p] = v }
    l ~ /^        finishedAt: / { v = l; sub(/^ *finishedAt: */, "", v); gsub(/"/, "", v); fa[p] = v }
    END { out(); printf "phase: %s  node: %s  startTime: %s\nコンテナ:\n%s", ph, nd, stt, buf }' "$R/$f"
  echo "ログ:"
  for c in "$R/$d"/*/; do
    c="$(basename "$c")"
    for lf in current previous; do
      ok_file "$d/$c/$c/logs/$lf.log" || continue
      [ "$lf" = current ] || [ -s "$R/$d/$c/$c/logs/$lf.log" ] || continue   # 再起動前のログは、中身があるときだけ出す
      if head -1 "$R/$d/$c/$c/logs/$lf.log" | has '^unable to retrieve'; then echo "  $c ($lf): 取得されていない (終了メッセージは mg.sh logs で見る)"
      else echo "  $c ($lf): $(log_range "$R/$d/$c/$c/logs/$lf.log")"; fi
    done
  done
  echo "次: ログは mg.sh logs $SLUG $ns $pod <container> で見る"
}

# errors <file>: klog 形式のエラー (E) と致命的エラー (F) を、ソースの場所と内容ごとに数える (Pod のログ、kubelet などのサービスログ)
cmd_errors() {
  local f="${1:-}" out
  [ -n "$f" ] || die "usage: mg.sh errors <case> <file>"
  need_root; need_file "$f"
  echo "ファイル: $f (期間: $(log_range "$R/$f"))"
  out="$(awk '
    /(^| )[EF][0-9][0-9][0-9][0-9] / {
      n++; if (match($0, /[A-Za-z0-9_]+\.go:[0-9]+\] /)) key = substr($0, RSTART, RLENGTH + 80); else key = substr($0, 1, 100)
      gsub(/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/, "<IP>", key); gsub(/[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+/, "<UUID>", key)
      if (!(key in c)) first[key] = NR
      c[key]++; last[key] = NR
    }
    END { printf "全 %d 件\n", n; for (k in c) printf "%7d  [%d〜%d 行目]  %s\n", c[k], first[k], last[k], k }' "$R/$f")"
  printf '%s\n' "$out" | head -1
  printf '%s\n' "$out" | tail -n +2 | sort -rn | head -n 15
  echo "次: 種類ごとの時刻の変化は mg.sh count $SLUG '<内容の一部>' $f minute、根拠の行は mg.sh show $SLUG $f <行>"
}

# term_msg <Pod の YAML> <container> <state|lastState>: コンテナの終了メッセージを「行番号<TAB>内容」で出す
term_msg() {
  awk -v c="$2" -v want="$3" '
    function flush() { if (name == c) printf "%s", buf; buf = ""; name = "" }
    /^  (init|ephemeral)?[cC]ontainerStatuses:/ { flush(); inst = 1; next }
    /^ ? ?[^ -]/ { flush(); inst = 0 }
    !inst { next }
    /^  - / { flush(); sec = ""; term = 0; cap = 0 }
    cap && /^          / { buf = buf NR "\t" substr($0, 11) "\n"; next }
    { cap = 0 }
    /^    name: / { name = $2 }
    /^    [a-zA-Z]+:/ { sec = $1; sub(/:$/, "", sec) }
    /^      [a-zA-Z]+:/ { term = ($1 == "terminated:") }
    sec == want && term && /^        message: *\|/ { cap = 1; next }
    sec == want && term && /^        message: / { m = $0; sub(/^ *message: */, "", m); buf = buf NR "\t" m "\n" }
    END { flush() }
  ' "$1"
}

# ns [<ns>]: Namespace について、must-gather に何が含まれているか (Pod やログが取得されているか) を表示する
#   引数が無ければ、OpenShift 以外の Namespace の一覧
cmd_ns() {
  local ns="${1:-}" d n p l pod c f
  need_root
  if [ -z "$ns" ]; then
    echo "| Namespace | Pod | ログのあるコンテナ |"
    echo "|---|---|---|"
    for d in "$R"/namespaces/*/; do
      n="$(basename "$d")"
      case "$n" in openshift|openshift-*|kube-*|default) continue;; esac
      [ ! -L "${d%/}" ] || continue   # シンボリックリンクの先 (must-gather の外かもしれない) は数えない
      p="$(find "$d/pods" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -c .)"
      l="$(find "$d/pods" -name current.log -size +0 2>/dev/null | grep -c .)"
      echo "| $n | $p | $l |"
    done
    echo "案内: OpenShift 以外 (openshift-*、kube-*、default を除く) の Namespace。Pod が 0 なら、その Namespace の Pod とログは must-gather に無い"
    echo "案内: 事象に関係する Namespace の情報が無ければ、製品の must-gather (oc adm must-gather --image=<製品の must-gather イメージ>)、無ければ oc adm inspect ns/<ns> の結果を依頼するか、「未確認事項」に回す"
    return 0
  fi
  name "$ns"; d="$R/namespaces/$ns"
  [ -d "$d" ] && [ ! -L "$d" ] && inside "$d" || { echo "[NG] namespaces/$ns がありません (must-gather に含まれていない)"; echo "案内: 製品の must-gather (oc adm must-gather --image=<製品の must-gather イメージ>)、無ければ oc adm inspect ns/$ns の結果を依頼するか、「未確認事項」に回す"; exit 3; }
  echo "## namespaces/$ns に含まれるリソース"
  # clusterserviceversions は、全 Namespace にコピーされる Operator の情報のため除く
  find "$d" -mindepth 2 -maxdepth 3 -name '*.yaml' -not -path "$d/pods/*" -not -path "$d/operators.coreos.com/clusterserviceversions/*" | sed "s|^$d/||" | LC_ALL=C sort | lim
  echo; echo "## Pod とログ (コンテナ: ログの期間)"
  [ -d "$d/pods" ] || { echo "(Pod は含まれていない)"; return 0; }
  for pod in "$d"/pods/*/; do
    pod="$(basename "$pod")"; echo "$pod"
    for c in "$d/pods/$pod"/*/; do
      c="$(basename "$c")"; f="$d/pods/$pod/$c/$c/logs/current.log"
      ok_file "namespaces/$ns/pods/$pod/$c/$c/logs/current.log" || continue
      if head -1 "$f" | has '^unable to retrieve'; then echo "  $c: ログは取得されていない"; else echo "  $c: $(log_range "$f")"; fi
    done
  done | lim
}

# events [<ns>] [<regex>]: イベントを時刻順に表示する
cmd_events() {
  local ns="${1:--A}" re="${2:-}"
  use_mg
  # regex は grep -E で解釈する (見出しの行は残す)
  if [ "$ns" = "-A" ]; then og events -A; else og events -n "$ns"; fi | { IFS= read -r h && printf '%s\n' "$h"; if [ -n "$re" ]; then grep -E -e "$re"; else cat; fi; } | lim
  echo "根拠の書き方: イベントは namespaces/<ns>/core/events.yaml にある。mg.sh grep $SLUG '<メッセージの一部>' namespaces/<ns>/core/events.yaml で行番号を得る"
  echo "案内: イベントは一定時間で消える。事象の時刻のイベントが無ければ、ノードのサービスログを見る (mg.sh count $SLUG '<regex>' host_service_logs/masters/kubelet_service.log minute)"
}

# --- report / lint ---

# fill <template>: ひな形の @…@ を、ケースの情報で置き換えて出す (値に | や & があっても壊れないよう、文字列として置き換える)
fill() {
  F_DATE="$(date '+%Y-%m-%d')" F_MG="$(basename "$DIR")/${R#$DIR/}" F_TAKEN="$(taken_at "$R")" \
  F_JST="$(jst "$R" '+%Y-%m-%d %H:%M:%S')" F_VERSION="$(version_of "$R")" awk '
    function rep(s, k, v,   i) { while ((i = index(s, k)) > 0) s = substr(s, 1, i - 1) v substr(s, i + length(k)); return s }
    BEGIN { split("DATE MG TAKEN JST VERSION", ks, " "); for (i in ks) { v = ENVIRON["F_" ks[i]]; m["@" ks[i] "@"] = (v == "" ? "不明" : v) } }
    { for (k in m) $0 = rep($0, k, m[k]); print }' "$SKILL_DIR/templates/$1"
}
# copy_sections <checklist>: 標準入力の報告書の「事象」と「確認事項」の中身を、checklist.md のものに置き換えて出す
copy_sections() {
  awk -v c="$1" '
    BEGIN { while ((getline l < c) > 0) { if (l ~ /^## /) s = l; else if (s == "## 事象" || s == "## 確認事項") body[s] = body[s] l "\n" } }
    /^## / { skip = ($0 == "## 事象" || $0 == "## 確認事項"); print; if (skip) printf "%s", body[$0]; next }
    !skip { print }'
}

# plan: 確認事項のファイル (checklist.md: 事象、確認事項、調査項目) のひな形を作る
cmd_plan() {
  local f="$DIR/$SLUG/checklist.md"
  need_root
  [ ! -e "$f" ] || { echo "[OK] 確認事項のファイルは既にあります: $f"; return 0; }
  fill checklist.md > "$f"
  echo "[OK] $f を作りました"
  echo "次: 「事象」「確認事項」「調査項目」を書き、mg.sh items $SLUG で表示してユーザーに示す"
}

# report: 報告書 (report.md) のひな形を作る。既にあれば、事象と確認事項だけを checklist.md から写し直す
cmd_report() {
  local f="$DIR/$SLUG/report.md" c="$DIR/$SLUG/checklist.md"
  need_root
  [ -f "$c" ] || { echo "[NG] 確認事項のファイルがありません: $c"; echo "次: mg.sh plan $SLUG"; exit 3; }
  if [ -e "$f" ]; then
    copy_sections "$c" < "$f" > "$f.tmp" && mv "$f.tmp" "$f" || die "報告書を書き換えられません: $f"
    echo "[OK] 報告書の「事象」と「確認事項」を checklist.md から写し直しました: $f"
    return 0
  fi
  fill report.md | copy_sections "$c" > "$f"
  echo "[OK] $f を作りました (事象と確認事項は checklist.md から写した)"
  echo "次: 調査項目を調べてチェックし、確認した事実と未確認事項を報告書に書き足す。最後に mg.sh lint $SLUG"
}

# items: checklist.md の確認事項と調査項目を、進み具合 (調べ済みの数) と一緒に表示する
cmd_items() {
  local f="$DIR/$SLUG/checklist.md" all checked
  [ -f "$f" ] || { echo "[NG] 確認事項のファイルがありません: $f"; echo "次: mg.sh plan $SLUG"; exit 3; }
  all="$(section "$f" 調査項目 | grep -cE '^- \[[ x]\] ')"; checked="$(section "$f" 調査項目 | grep -cE '^- \[x\] ')"
  echo "## 確認事項"
  section "$f" 確認事項 | grep -E '^[0-9]+\. ' | lim
  echo; echo "## 調査項目 (調べ済み: $checked / $all)"
  section "$f" 調査項目 | grep -E '^- \[[ x]\] ' | lim
}

# section <file> <見出し>: "## 見出し" の中身
section() { awk -v h="## $2" '$0 == h {f = 1; next} /^## / {f = 0} f' "$1"; }
# quotes: 標準入力から、引用付きの根拠 (`パス:行` 「引用」) を "パス<US>行<US>行<US>引用" で出す
US=$'\x1f'
#   「」は、正規表現の文字の集合 ([^」]) だとロケールによって一致しないため、index で探す
quotes() {
  awk -v us="$US" '{
    s = $0
    while (match(s, /`[^` ]+\/[^` ]+:[0-9]+(-[0-9]+)?`/)) {
      ref = substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH)
      t = s; sub(/^ */, "", t)
      if (index(t, "「") != 1) continue
      t = substr(t, length("「") + 1); e = index(t, "」"); if (!e) continue
      p = ref; sub(/:[0-9]+(-[0-9]+)?$/, "", p)
      r = substr(ref, length(p) + 2); a = r; b = ""
      if (index(r, "-")) { a = substr(r, 1, index(r, "-") - 1); b = substr(r, index(r, "-") + 1) }
      print p us a us b us substr(t, 1, e - 1)
    }
  }'
}
# evidence <report>: 根拠を書く節 (確認した事実、原因)。ほかの節のコマンドを根拠と取り違えないよう、この 2 つだけを見る
evidence() { section "$1" 確認した事実; section "$1" 原因; }
# refs: 標準入力から、根拠の参照 (`パス:行` または `パス:行-行`) を "パス 行 行" で出す
refs() { grep -oE '`[^` ]+/[^` ]+:[0-9]+(-[0-9]+)?`' | tr -d '`' | sed -E 's/:([0-9]+)(-([0-9]+))?$/ \1 \3/'; }

cmd_lint() {
  local f="$DIR/$SLUG/report.md" cl="$DIR/$SLUG/checklist.md" fail=0 s p a b total n
  ng() { echo "[NG] $*"; fail=1; }
  need_root
  [ -f "$cl" ] || { echo "[NG] 確認事項のファイルがありません: $cl"; echo "次: mg.sh plan $SLUG"; return 1; }
  [ -f "$f" ] || { echo "[NG] 報告書がありません: $f"; echo "次: mg.sh report $SLUG"; return 1; }
  head -1 "$f" | has '^# ' || ng "report.md の 1 行目に '# 調査報告: …' が必要"
  for s in $SECTIONS; do
    grep -qx "## $s" "$f" || ng "report.md に '## $s' の節が必要"
  done
  for s in $CL_SECTIONS; do
    grep -qx "## $s" "$cl" || ng "checklist.md に '## $s' の節が必要"
  done
  # 事象と確認事項は checklist.md の写しなので、TODO は checklist.md の側だけで指摘する
  awk '/^## / { skip = ($0 == "## 事象" || $0 == "## 確認事項") } !skip && /TODO/ { print NR ":" $0 }' "$f" | sed 's/^/[NG] report.md に TODO が残っています: /' | grep . && fail=1
  grep -n 'TODO' "$cl" | sed 's/^/[NG] checklist.md に TODO が残っています: /' | grep . && fail=1
  for s in 事象 確認事項; do
    [ "$(section "$f" "$s")" = "$(section "$cl" "$s")" ] || ng "report.md と checklist.md の「${s}」が一致しません (mg.sh report $SLUG で写し直す)"
  done
  # 根拠: ファイルと行が must-gather に実在するか
  while read -r p a b; do
    [ -n "$p" ] || continue
    ok_file "$p" || { ng "根拠のファイルがありません (must-gather の外、シンボリックリンクは不可): $p"; continue; }
    total="$(awk 'END { print NR }' "$R/$p")"
    for n in $a $b; do [ "$n" -ge 1 ] && [ "$n" -le "$total" ] || ng "根拠の行がありません: $p:$n (全 $total 行)"; done
  done < <(evidence "$f" | refs)
  [ -n "$(section "$f" 確認した事実 | refs)" ] || ng "'## 確認した事実' に根拠 (\`パス:行\`) がありません"
  # 原因は、根拠を直接書くか、確認した事実の番号 (事実 N) で示す
  [ -n "$(section "$f" 原因 | refs)" ] || section "$f" 原因 | has -E '事実 ?[0-9]' ||
    ng "'## 原因' に根拠 (\`パス:行\` か、確認した事実の番号「事実 N」) がありません"
  # 引用: その行 (範囲) に、引用した記述が本当にあるか。「…」で省略した部分は、区切った各部分を確かめる
  local q text part ok
  while IFS="$US" read -r p a b q; do
    ok_file "$p" || continue
    text="$(sed -n "${a},${b:-$a}p" "$R/$p")"; ok=1
    while IFS= read -r part; do
      part="$(printf '%s' "$part" | sed 's/^ *//; s/ *$//')"
      [ -z "$part" ] || printf '%s' "$text" | has -F -- "$part" || ok=0
    done < <(printf '%s\n' "$q" | awk '{ gsub(/…/, "\n"); print }')
    [ $ok = 1 ] || ng "引用が、その行の記述と一致しません: $p:$a${b:+-$b} 「$(printf '%s' "$q" | cut -c1-80)」"
  done < <(evidence "$f" | quotes)
  # 確認事項と調査項目: 確認事項ごとに調査項目 (N-M.) があり、すべてチェック済みで結果があり、原因か対処案で答えているか
  local items k
  items="$(section "$cl" 調査項目 | grep -E '^- \[[ x]\] [0-9]+-[0-9]+\. ')"
  [ -n "$(section "$cl" 確認事項 | grep -E '^[0-9]+\. ')" ] || ng "checklist.md の '## 確認事項' に番号付きの項目 (1. …) がありません"
  [ -n "$items" ] || ng "checklist.md の '## 調査項目' に項目 (- [ ] 1-1. …) がありません"
  for k in $(section "$cl" 確認事項 | grep -oE '^[0-9]+' | sort -un); do
    printf '%s\n' "$items" | has -E "^- \[[ x]\] $k-[0-9]+\. " || ng "確認事項 $k の調査項目 ($k-1. …) がありません"
    { section "$f" 原因; section "$f" 対処案; } | has -E "確認事項 ?$k([^0-9-]|$)" || ng "確認事項 $k に、'## 原因' か '## 対処案' で答えていません (「確認事項 ${k}」と書いて答える)"
  done
  printf '%s\n' "$items" | grep -E '^- \[ \] ' | sed 's|^|[NG] 調べていない調査項目があります: |' | grep . && fail=1
  printf '%s\n' "$items" | grep -E '^- \[x\] ' | grep -vE '→ *(事実 ?[0-9]+|未確認事項)' | sed 's|^|[NG] 調査項目に結果 (→ 事実 N か 未確認事項) がありません: |' | grep . && fail=1
  # 事実の番号 (事実 N) が、確認した事実の番号付きの項目にあるか
  local facts
  facts="$(section "$f" 確認した事実 | grep -cE '^[0-9]+\. ')"
  for n in $(cat "$f" "$cl" | grep -oE '事実 ?[0-9]+' | grep -oE '[0-9]+' | sort -un); do
    [ "$n" -le "$facts" ] || ng "事実 $n がありません ('## 確認した事実' の番号付きの項目は $facts 件)"
  done
  [ "$(section "$f" 確認した事実 | refs | wc -l)" -le "$(section "$f" 確認した事実 | quotes | wc -l)" ] ||
    echo "[WARN] '## 確認した事実' に、引用 (\`パス:行\` 「…」) の無い根拠があります"
  section "$f" 未確認事項 | has '`' || echo "[WARN] '## 未確認事項' に、確かめるコマンド (\`…\`) がありません (コマンドで確かめられない場合は、確かめる方法を書く)"
  section "$f" 情報元 | has -E 'https?://' || echo "[WARN] '## 情報元' に URL がありません (見つからなかった場合は、その旨を書く)"
  [ $fail = 0 ] && echo "[OK] lint"
  return $fail
}

# --- main ---

usage() { awk 'NR == 1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"; exit 3; }
CMD="${1:-}"; SLUG="${2:-}"
case "$CMD" in
  check) cmd_check;;
  list)  cmd_list;;
  new) cmd_new;;
  prepare|plan|items|overview|ns|cond|pod|logs|errors|count|events|grep|show|report|lint)
    [[ $SLUG =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "usage: mg.sh $CMD <case> (ケース名は英小文字・数字・._-)"
    [ -d "$DIR/$SLUG" ] || die "$DIR/$SLUG がありません (先に mg.sh new)"
    "cmd_$CMD" "${@:3}";;
  *) usage;;
esac
