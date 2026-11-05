#!/usr/bin/env bash
# Red Hat ナレッジベース (KCS) を検索する MCP サーバー (cldmnky/mcp-servers の rhkcs-mcp) を、このリポジトリで使えるようにする
#
# rhkcs-mcp-setup スキルが、次の順で使う (check → build → token (ユーザーが別のターミナルで実行) → test。新しい版に上げるときは update → PIN を書き換え → build → test)
# Claude Code は、リポジトリのルートの .mcp.json から run を実行して、MCP サーバーを起動する
#
# 使い方:
#   rhkcs.sh check   導入の状況を確認する (バイナリ、Go (ビルドしていなければ)、token、.mcp.json)。token の値は表示しない
#   rhkcs.sh build   固定したコミットのソースを取得し、バイナリをビルドする (Go が必要。ユーザーが入れる)
#   rhkcs.sh token   offline token を、画面に表示せずに入力して .rhkcs/token に保存する (端末から実行する。Claude Code の Bash からは実行できない)
#   rhkcs.sh test    MCP サーバーを起動し、search_kcs のエラーと記事 URL の有無を確かめ、1 件目の題名と URL を表示する
#   rhkcs.sh update  固定したコミットから取得元の最新までの変更 (コミット、変わったファイル、通信先・token・環境変数・ツールの名前と引数に関わる行) を表示する。.rhkcs/src に最新を取得するだけで、ほかは書き換えない
#   rhkcs.sh run     MCP サーバーを起動する (.mcp.json から Claude Code が実行する。標準出力は MCP の通信に使う。固定したコミットでビルドしたものだけを起動する)
#   rhkcs.sh permissions token の権限だけを 600 に直す (内容は読まない)
#   (終了コード: 0=OK 1=NG 3=開始できない)
#
# 置き場所 (すべてリポジトリの中の .rhkcs/。Git の管理対象外。リポジトリの外には書かない):
#   .rhkcs/src/    ソース (https://github.com/cldmnky/mcp-servers を PIN のコミットで取得)
#   .rhkcs/bin/    ビルドしたバイナリ (rhkcs-mcp) と、そのコミット (rhkcs-mcp.commit)
#   .rhkcs/go/     Go のモジュールとビルドのキャッシュ、ビルド中の HOME と一時ファイル (Go のテレメトリなどを ~ に書かないため)
#   .rhkcs/log/    MCP サーバーのログ
#   .rhkcs/token   offline token (権限 600。run が読んで MCP サーバーに渡す)
set -uo pipefail
set +x  # 呼び出し元が xtrace を有効にしていても token を記録しない
umask 077
REPO_URL="https://github.com/cldmnky/mcp-servers.git"
PIN="7e39b5c2eb5f78f6b129e4608f90a31e6c059819"   # 2026-10-05「Fix MCP server reliability and Jira query handling」
GO_MIN="1.25.0"                                  # go.mod の go の行
# リポジトリのルートは、実行した場所ではなく、スクリプトの場所 (.claude/skills/<skill>/scripts/) から決める
TOP="$(cd "$(dirname "$0")/../../../.." && pwd -P)" || exit 3
S="$TOP/.rhkcs"
BIN="$S/bin/rhkcs-mcp"
TOKEN_FILE="$S/token"
SCRIPT=".claude/skills/rhkcs-mcp-setup/scripts/rhkcs.sh"
T="bash $SCRIPT"
NEXT_TOKEN="https://access.redhat.com/management/api で offline token を作り、別のターミナルで $T token を実行する"

die() { echo "[NG] $*" >&2; exit 3; }
# own_dir <ディレクトリ…>: .rhkcs の下にディレクトリを作る
#   main で .rhkcs 以下を検査した後にだけ呼ぶ。保存先を他ユーザーと共有しない。
own_dir() {
  mkdir -p "$@" || die "${S#$TOP/} にディレクトリを作れません"
  chmod 700 "$S" || die ".rhkcs の権限を変更できません"
}
# has <grep の引数>: 標準入力に一致する行があるか。pipefail のもとで grep -q は偽になることがあるため、入力を最後まで読む
has() { grep "$@" >/dev/null; }

# go_version: インストールされている Go のバージョン (例: 1.25.3)。無ければ何も出さない
#   go version もテレメトリを書くため、goenv で実行する
go_version() { command -v go >/dev/null 2>&1 && goenv go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^go//'; }
# ver_ge <a> <b>: バージョン a が b 以上か (1.25 は 1.25.0 として比べる)
ver_ge() { awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, "."); for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 } exit 0 }'; }
# token_ok: token のファイルがあり、空でなく、シンボリックリンクでないか
token_ok() { [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ] && [ ! -L "$TOKEN_FILE" ]; }
# token_perm_ok: token のファイルが、所有者だけが読み書きできる (600) か
token_perm_ok() { find "$TOKEN_FILE" -prune -perm 600 2>/dev/null | has .; }
# built: 固定したコミットでビルドしたバイナリがあるか
built() { [ -x "$BIN" ] && [ "$(cat "$S/bin/rhkcs-mcp.commit" 2>/dev/null)" = "$PIN" ]; }
# goenv <コマンド…>: Go を、キャッシュと HOME を .rhkcs/go/ にして実行する
#   ~/go や ~/Library/Caches のほか、ユーザーの設定のディレクトリ (Go のテレメトリ、go env -w の設定) にも書かない
#   ビルド中の一時ファイルも、もとの TMPDIR (リポジトリの外) ではなく .rhkcs/go/tmp に置く
#   (GOTMPDIR は go の作業用、TMPDIR はほかの一時ファイル用。無いと失敗するため作っておく)
#   C コンパイラー (macOS では xcrun 経由の clang) は、TMPDIR とは別にリポジトリの外へキャッシュを書くことがあるため、cgo を使わない (CGO_ENABLED=0)
goenv() {
  own_dir "$S/go/home/.config" "$S/go/tmp"
  HOME="$S/go/home" XDG_CONFIG_HOME="$S/go/home/.config" GOPATH="$S/go" GOMODCACHE="$S/go/pkg/mod" GOCACHE="$S/go/cache" GOTMPDIR="$S/go/tmp" TMPDIR="$S/go/tmp" \
  GOWORK=off GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS="-mod=readonly -modcacherw" "$@"
}

# --- check ---

cmd_check() {
  local v ng=0 next=""
  # run は .rhkcs がシンボリックリンクだと起動しないため、先に確かめる (Go の確認も .rhkcs に書く)
  [ ! -L "$S" ] || { echo "[NG] ${S#$TOP/} がシンボリックリンクです"; echo "次: ${S#$TOP/} を消してから、もう一度 $T check を実行する"; return 1; }
  if built; then echo "[OK] rhkcs-mcp: ${BIN#$TOP/} (コミット ${PIN:0:7})"
  else
    if [ -x "$BIN" ]; then echo "[NG] rhkcs-mcp が、固定したコミット (${PIN:0:7}) でビルドされていません"; else echo "[NG] rhkcs-mcp がビルドされていません"; fi
    ng=1
    # Go と git は、ビルドするときだけ要る
    v="$(go_version)"
    if [ -z "$v" ]; then echo "[NG] Go がありません (ビルドに Go $GO_MIN 以上が必要)"; next="Go を入れる (macOS: brew install go。Linux: 配布元のパッケージか https://go.dev/dl/)"
    elif ! ver_ge "$v" "$GO_MIN"; then echo "[NG] Go $v は古い (Go $GO_MIN 以上が必要)"; next="Go を $GO_MIN 以上に上げる"
    else echo "[OK] Go $v"; fi
    command -v git >/dev/null 2>&1 && echo "[OK] git" || { echo "[NG] git がありません"; next="${next:-git を入れる}"; }
    next="${next:-$T build}"
  fi
  if token_ok && token_perm_ok; then echo "[OK] token: ${TOKEN_FILE#$TOP/}"
  elif token_ok; then echo "[NG] token: ${TOKEN_FILE#$TOP/} の権限が 600 ではありません"; ng=1; next="${next:-$T permissions}"
  elif [ -L "$TOKEN_FILE" ]; then echo "[NG] token: ${TOKEN_FILE#$TOP/} がシンボリックリンクです"; ng=1; next="${next:-${TOKEN_FILE#$TOP/} を消してから、$NEXT_TOKEN}"
  else
    echo "[NG] token がありません (${TOKEN_FILE#$TOP/})"; ng=1
    next="${next:-$NEXT_TOKEN}"
  fi
  if [ -f "$TOP/.mcp.json" ] && has -F "$SCRIPT" < "$TOP/.mcp.json"; then echo "[OK] .mcp.json: rhkcs"
  else echo "[NG] .mcp.json に rhkcs がありません"; ng=1; next="${next:-リポジトリのルートの .mcp.json に rhkcs を登録する (スキルの README の「仕組み」を参照)}"; fi
  if [ $ng = 0 ]; then
    echo "次: $T test で検索できるかを確かめる。Claude Code では /mcp で rhkcs が connected かを確かめる"
    return 0
  fi
  echo "次: $next"
  return 1
}

# need_origin: .rhkcs/src の取得元が、決めたリポジトリか (違えば止める)
#   remote get-url は ~/.gitconfig の insteadOf で書き換えた URL を返すため、設定の値そのものを比べる
need_origin() {
  [ "$(git -C "$S/src" config --get remote.origin.url 2>/dev/null)" = "$REPO_URL" ] || die "${S#$TOP/}/src の取得元が $REPO_URL ではありません (${S#$TOP/}/src を消してから、もう一度実行する)"
}

# --- build ---

cmd_build() {
  local v head st
  # .rhkcs がシンボリックリンクだと、go_version の中の goenv が止まり「Go がありません」と誤って出るため、先に確かめる
  own_dir "$S/bin" "$S/log"
  v="$(go_version)"
  [ -n "$v" ] || die "Go がありません。Go $GO_MIN 以上を入れてから、もう一度実行する (macOS: brew install go。Linux: 配布元のパッケージか https://go.dev/dl/)"
  ver_ge "$v" "$GO_MIN" || die "Go $v は古い。Go $GO_MIN 以上に上げてから、もう一度実行する"
  command -v git >/dev/null 2>&1 || die "git がありません"
  # 取得が途中で止まると、.git の無いディレクトリが残ることがある
  [ -d "$S/src/.git" ] || [ ! -e "$S/src" ] || die "${S#$TOP/}/src が Git のリポジトリではありません (${S#$TOP/}/src を消してから、もう一度実行する)"
  if [ ! -d "$S/src/.git" ]; then
    echo "取得します: $REPO_URL → ${S#$TOP/}/src"
    git clone --quiet "$REPO_URL" "$S/src" || die "取得できません: $REPO_URL"
  fi
  need_origin
  # 固定したコミットに合わせる。無ければ取り直す
  git -C "$S/src" cat-file -e "$PIN^{commit}" 2>/dev/null || git -C "$S/src" fetch --quiet origin || die "取得できません: $REPO_URL"
  git -C "$S/src" -c advice.detachedHead=false checkout --quiet --detach "$PIN" || die "コミット ${PIN:0:7} に切り替えられません"
  head="$(git -C "$S/src" rev-parse HEAD)"
  [ "$head" = "$PIN" ] || die "ソースのコミットが違います: $head"
  # checkout は手元の変更や追加したファイルを残すため、固定したコミットのとおりかを確かめる
  st="$(git -C "$S/src" status --porcelain)" || die "${S#$TOP/}/src の状態を確かめられません"
  [ -z "$st" ] || die "${S#$TOP/}/src に、固定したコミットとの違いがあります (${S#$TOP/}/src を消してから、もう一度実行する)"
  echo "ビルドします: コミット ${PIN:0:7} (Go $v)"
  ( cd "$S/src" && goenv go build -trimpath -o "$BIN" ./pkg/mcp/rhkcs-mcp ) || die "ビルドできません (上のエラーを見る)"
  echo "$PIN" > "$S/bin/rhkcs-mcp.commit" || die "ビルド記録を保存できません"
  echo "[OK] ビルドしました: ${BIN#$TOP/}"
  if token_ok; then echo "次: $T test"
  else echo "次: $NEXT_TOKEN"; fi
}

# --- update ---

# update: 固定したコミットから、取得元の最新 (既定のブランチ) までの変更を表示する
#   ファイルは書き換えない (.rhkcs/src に最新を取得するだけ)。上げるかどうかは、表示を見て人が決める
# 調べるパス: Jira 用のサーバー (pkg/mcp/rh-issues-mcp) を除くすべて
#   rhkcs-mcp が新しく読み込むパッケージ (pkg/ や internal/ の下に増えたもの) も見落とさないよう、除くほうを決める
UPDATE_PATHS=". :(exclude)pkg/mcp/rh-issues-mcp"
cmd_update() {
  local br latest n out gomin
  command -v git >/dev/null 2>&1 || die "git がありません"
  own_dir "$S"
  [ -d "$S/src/.git" ] || die "${S#$TOP/}/src がありません (先に $T build)"
  need_origin
  git -C "$S/src" fetch --quiet origin || die "取得できません: $REPO_URL"
  # 固定したコミットが無いと、下の比較が失敗して「(なし)」と誤って出るため、先に確かめる
  git -C "$S/src" cat-file -e "$PIN^{commit}" 2>/dev/null || die "固定したコミット (${PIN:0:7}) が ${S#$TOP/}/src にありません (取得元の履歴が書き換えられた可能性がある。上げる前に理由を確かめる)"
  # 既定のブランチ。取得元で既定のブランチが変わっても追えるよう、毎回取得元に問い合わせて origin/HEAD を記録し直す
  # (問い合わせに失敗したときは、clone したときに記録したものを使う)
  git -C "$S/src" remote set-head origin --auto >/dev/null 2>&1
  br="$(git -C "$S/src" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || die "取得元の既定のブランチが分かりません"
  latest="$(git -C "$S/src" rev-parse "$br")" || die "$br のコミットが分かりません"
  echo "固定したコミット: ${PIN:0:12}  最新 ($br): ${latest:0:12}"
  if [ "$latest" = "$PIN" ]; then echo "[OK] 固定したコミットが最新です"; return 0; fi
  git -C "$S/src" merge-base --is-ancestor "$PIN" "$latest" ||
    echo "[WARN] 最新は、固定したコミットの続きではありません (取得元の履歴が書き換えられた可能性がある。上げる前に理由を確かめる)"
  n="$(git -C "$S/src" rev-list --count "$PIN..$latest")"
  echo; echo "## 増えたコミット ($n 件。新しい順に最大 30 件)"
  git -C "$S/src" log --format='%h %ad %s' --date=short "$PIN..$latest" | head -30
  echo; echo "## 変わったファイル (Jira 用のサーバー pkg/mcp/rh-issues-mcp を除く。最大 40 件)"
  # $UPDATE_PATHS は、パスごとに分けて渡すため、引用符で囲まない
  out="$(git -C "$S/src" diff --stat=120,100,40 "$PIN" "$latest" -- $UPDATE_PATHS)"
  printf '%s\n' "${out:-(なし)}"
  echo; echo "## 特に気をつける変更 (通信先の URL、token・認証、環境変数、ツールの名前と引数を含む行。テストと文書 (*.md) を除く)"
  # ファイル名は、各ファイルの見出し (diff --git から @@ まで) の --- a/ か +++ b/ の行から取る (消したファイルは +++ /dev/null になるため)
  out="$(git -C "$S/src" diff -U0 "$PIN" "$latest" -- $UPDATE_PATHS ':(exclude)*_test.go' ':(exclude)*.md' | awk '
    /^diff --git / { h = 1; next }
    h && /^(--- a|\+\+\+ b)\// { f = substr($0, 7); next }
    /^@@/ { h = 0; next }
    h { next }
    /^[+-]/ && /(https?:\/\/|[Tt]oken|TOKEN|[Aa]uthorization|Bearer|Getenv|AddTool|Name: *"|json:")/ { print f ": " substr($0, 1, 200) }')"
  n="$(printf '%s\n' "$out" | grep -c .)"
  printf '%s\n' "${out:-(なし)}" | head -40
  [ "$n" -le 40 ] || echo "... (全 $n 行のうち先頭 40 行。残りは git -C $S/src diff $PIN $latest で見る)"
  gomin="$(git -C "$S/src" show "$latest:go.mod" 2>/dev/null | sed -n 's/^go //p' | head -1)"
  echo; echo "Go の版 (go.mod の go の行): 今 $GO_MIN → 最新 ${gomin:-不明}"
  echo "次: 内容を確かめ、上げてよいかを聞く。上げるなら $SCRIPT の PIN を $latest に (行末のコメントの日付と題名も)、GO_MIN を ${gomin:-<go.mod の値>} に書き換え、$T build と $T test を実行する"
}

# --- token ---

cmd_token() {
  local t
  [ -t 0 ] || die "端末から実行する (token を画面に出さずに入力するため。Claude Code の Bash や ! からは実行できない)"
  printf 'offline token を貼り付けて Enter (画面には表示されません): ' >&2
  IFS= read -rs t; echo >&2
  t="$(printf '%s' "$t" | tr -d '[:space:]')"
  [ -n "$t" ] || die "token が空です"
  own_dir "$S"
  # token のファイルがシンボリックリンクのときも、リンク先に書かない
  [ ! -L "$TOKEN_FILE" ] || die "${TOKEN_FILE#$TOP/} がシンボリックリンクです (消してから、もう一度実行する)"
  # 既にあるファイルは umask では権限が変わらないため、書く前に 600 にする (ほかの人が読める間に token を書かない)
  [ ! -e "$TOKEN_FILE" ] || chmod 600 "$TOKEN_FILE" || die "${TOKEN_FILE#$TOP/} の権限を 600 にできません"
  ( umask 077; printf '%s\n' "$t" > "$TOKEN_FILE" ) || die "保存できません: $TOKEN_FILE"
  chmod 600 "$TOKEN_FILE" || die "${TOKEN_FILE#$TOP/} の権限を 600 にできません"
  echo "[OK] 保存しました: ${TOKEN_FILE#$TOP/} (権限 600)"
  echo "次: Claude Code に戻り、保存したことを伝える ($T test で確かめる)"
}

# --- run / test ---

# run: MCP サーバーを起動する。標準出力は MCP の通信に使うため、メッセージは標準エラー出力に出す
cmd_run() {
  # 固定したコミットでビルドしたものだけを起動する (PIN を変えた後に、古いバイナリが動かないように)
  built || { echo "rhkcs-mcp が、固定したコミット (${PIN:0:7}) でビルドされていません ($T build)" >&2; exit 1; }
  token_ok && token_perm_ok || { echo "token が無いか、権限が 600 ではありません ($T check)" >&2; exit 1; }
  [ ! -L "$S" ] || { echo "${S#$TOP/} がシンボリックリンクです" >&2; exit 1; }
  RH_API_OFFLINE_TOKEN="$(head -1 "$TOKEN_FILE")"
  export RH_API_OFFLINE_TOKEN
  own_dir "$S/log"
  exec "$BIN" -log-dir "$S/log"
}

# test: MCP の手順 (initialize → initialized → tools/call) で search_kcs を 1 回呼び、結果を確かめる
cmd_test() {
  local out res mark
  built || die "rhkcs-mcp が、固定したコミット (${PIN:0:7}) でビルドされていません (次: $T build)"
  token_ok && token_perm_ok || die "token が無いか、権限が 600 ではありません (次: $T check)"
  echo "MCP サーバーを起動し、search_kcs で検索します (最大 20 秒)"
  own_dir "$S"
  mark="$S/.test-done"; rm -f "$mark"
  # 入力を閉じるとサーバーが終わるため、応答が来るまで (最大 20 秒) は入力を開けておく。応答が来たら awk が印のファイルを作る
  out="$( {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"rhkcs-test","version":"1"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_kcs","arguments":{"query":"etcd","rows":1}}}'
    for _ in $(seq 1 40); do [ -e "$mark" ] && break; sleep 0.5; done
  } | bash "$TOP/$SCRIPT" run 2>&1 | awk -v d="$mark" '{ print } /"id"[[:space:]]*:[[:space:]]*2[[:space:]]*[,}]/ { printf "" > d; close(d); exit }' )"
  rm -f "$mark"
  res="$(printf '%s\n' "$out" | grep -E '"id"[[:space:]]*:[[:space:]]*2[[:space:]]*[,}]' | head -1)"
  if [ -z "$res" ]; then
    echo "[NG] search_kcs の応答がありません"
    printf '%s\n' "$out" | grep -v '^{' | head -5 | cut -c1-200
    echo "案内: ログは ${S#$TOP/}/log/ にある"
    return 1
  fi
  if printf '%s\n' "$res" | has -E '"isError"[[:space:]]*:[[:space:]]*true|"error"[[:space:]]*:[[:space:]]*\{'; then
    echo "[NG] search_kcs がエラーを返しました: $(printf '%s\n' "$res" | grep -oE '"(text|message)":"[^"]{0,200}' | head -1)"
    echo "案内: token が正しいか、失効していないか (offline token は 30 日使わないと失効する) を確かめる。作り直したら、別のターミナルで $T token を実行する"
    return 1
  fi
  if ! printf '%s\n' "$res" | has -E 'https://access\.redhat\.com/[a-z]+/[0-9]+'; then
    echo "[NG] 検索結果がありません"
    return 1
  fi
  # 結果のテキストから、1 件目の題名と URL を出す
  echo "[OK] search_kcs が結果を返しました: $(printf '%s\n' "$res" | grep -oE '\*\*[^*]+\*\*' | head -1 | tr -d '*') ($(printf '%s\n' "$res" | grep -oE 'https://access\.redhat\.com/[a-z]+/[0-9]+' | head -1))"
  echo "次: Claude Code を起動し直し (この会話を続けるなら claude --continue)、rhkcs の使用を承認する。/mcp で rhkcs が connected かを確かめる"
}

# --- main ---

usage() { awk 'NR == 1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"; exit 3; }
case "${1:-}" in
  check|build|token|run|test|update|permissions) [ "$#" = 1 ] || usage;;
  *) usage;;
esac
# 保存先の直下だけを検査し、シンボリックリンクなら書き込み前に止める。
for path in "$S" "$S/go" "$S/bin" "$S/log" "$S/src" "$S/token"; do
  [ ! -L "$path" ] || die "${path#$TOP/} がシンボリックリンクです (消してから、もう一度実行する)"
done
case "${1:-}" in
  check) cmd_check;;
  build) cmd_build;;
  token) cmd_token;;
  run)   cmd_run;;
  test)  cmd_test;;
  update) cmd_update;;
  permissions) token_ok || die "token がありません"; chmod 600 "$TOKEN_FILE";;
  *) usage;;
esac
