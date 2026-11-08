#!/usr/bin/env bash
# Google ドキュメント・スライドを gws で読み取る
#
# 使い方:
#   review.sh fetch <URL>  資料を gws-doc-reviews/.work/ に読み取り、資料の名前・最終更新と、レビュー結果の保存先 (gws-doc-reviews/<レビューした日>_<資料名>.md) を表示する
#                          ドキュメント: document.md と、埋め込まれた画像 (image<N>.<拡張子>)
#                          スライド:     slides.md (スライドごとの文字とスピーカーノート) と、画像・線・表・グラフ・動画のあるスライドの画像 (slide-<N>.png)
#   review.sh clean        gws-doc-reviews/.work/ を消す
set -uo pipefail
umask 077
GWS_TESTED="0.22.5"
# リポジトリのルートは、スクリプトの場所 (.claude/skills/<skill>/scripts/) から決める
TOP="$(cd "$(dirname "$0")/../../../.." && pwd -P)" || exit 1
cd "$TOP" || exit 1   # gws は --output にカレントディレクトリの下しか受け付けない
OUT=gws-doc-reviews
WORK="$OUT/.work"
# 文字だけでは分からない要素があるスライドか
VISUAL='def visual: [.pageElements[]? | .. | objects | select(has("image") or has("line") or has("table") or has("sheetsChart") or has("video"))] | length > 0;'

ng() { echo "[NG] $1"; [ -z "${2:-}" ] || echo "案内: $2"; exit 1; }
# api <service> <resource> <method> <引数…>: 読み取りのメソッドだけを呼ぶ
api() {
  case "$1 $2 $3 ${4:-}" in
    "drive files get "*|"drive files export "*|"slides presentations get "*|"slides presentations pages getThumbnail") gws "$@";;
    *) ng "読み取り以外のメソッドは呼びません: $1 $2 $3";;
  esac
}
# export_to <MIME> <出力>: 資料を書き出す。失敗したら、出力を消して偽
export_to() {
  api drive files export --params "$(jq -cn --arg id "$ID" --arg m "$1" '{fileId: $id, mimeType: $m}')" --output "$2" >/dev/null 2>&1 && [ -s "$2" ] && return 0
  rm -f "$2"; return 1
}
clean() {
  [ -d "$WORK" ] || return 0
  rm -f "$WORK"/* && rmdir "$WORK"
}

[ ! -L "$OUT" ] && [ ! -L "$WORK" ] || ng "$OUT か $WORK がシンボリックリンクです"
case "${1:-} $#" in
  "clean 1") clean || ng "$WORK を消せません"; exit 0;;
  "fetch 2") ;;
  *) ng "使い方: bash .claude/skills/openshift-gws-doc-review/scripts/review.sh fetch <URL> | clean";;
esac

command -v gws >/dev/null 2>&1 || ng "gws がありません" "https://github.com/googleworkspace/cli の手順で入れ、gws auth login で認証する"
command -v jq >/dev/null 2>&1 || ng "jq がありません" "パッケージマネージャーで jq を入れる"
v="$(gws --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ "$v" = "$GWS_TESTED" ] || echo "[WARN] gws ${v:-(バージョン不明)}。動作を確かめたのは $GWS_TESTED です"

# 公開用の URL (/d/e/…/pub) は ID が短いので受け付けない
re='^https://docs\.google\.com/(document|presentation)/(u/[0-9]+/)?d/([A-Za-z0-9_-]{20,})'
[[ $2 =~ $re ]] || ng "Google ドキュメントかスライドの編集用の URL ではありません: $2"
ID="${BASH_REMATCH[3]}"

rc=0
meta="$(api drive files get --params "$(jq -cn --arg id "$ID" '{fileId: $id, fields: "name,mimeType,modifiedTime,webViewLink", supportsAllDrives: true}')" 2>/dev/null)" || rc=$?
[ $rc != 2 ] || ng "gws が認証されていません (期限切れを含む)" "ユーザーが ! gws auth login を実行する"
[ $rc = 0 ] || ng "資料を読めません: $(jq -r '.error.message // empty' <<<"$meta" 2>/dev/null)" "URL と、認証したアカウントに閲覧の権限があるかを確かめる"
mime="$(jq -r .mimeType <<<"$meta")"
case "$mime" in
  application/vnd.google-apps.document) kind=document;;
  application/vnd.google-apps.presentation) kind=slides;;
  *) ng "Google ドキュメントかスライドではありません (種類: $mime)";;
esac

clean || ng "$WORK を消せません"
mkdir -p "$WORK" || ng "$WORK を作れません"
if [ $kind = document ]; then
  export_to text/markdown "$WORK/export.md" || ng "本文を書き出せません"
  # 埋め込まれた画像 ([imageN]: <data:image/png;base64,…>) をファイルに戻し、本文からはファイル名で参照する
  awk -v dir="$WORK" '
    match($0, /^\[image[0-9]+\]: <data:image\/[a-z0-9.+-]+;base64,/) {
      name = substr($0, 2, index($0, "]") - 2)
      ext = substr($0, RSTART, RLENGTH); sub(/^.*data:image\//, "", ext); sub(/[+;].*$/, "", ext)
      if (ext == "jpeg") ext = "jpg"
      data = substr($0, RLENGTH + 1); sub(/>$/, "", data)
      cmd = "base64 --decode > \"" dir "/" name "." ext "\""
      print data | cmd; close(cmd)
      print "[" name "]: " name "." ext
      next
    }
    { print }' "$WORK/export.md" >"$WORK/document.md" || ng "本文を処理できません"
  rm -f "$WORK/export.md"
else
  api slides presentations get --params "$(jq -cn --arg id "$ID" '{presentationId: $id, fields: "slides(objectId,pageElements,slideProperties(isSkipped,notesPage(notesProperties,pageElements)))"}')" >"$WORK/presentation.json" 2>/dev/null || ng "スライドを読み取れません"
  # スライドごとに、図形と表の文字、スピーカーノートを並べる。画像にするスライドには、ファイル名を添える
  jq -r "$VISUAL"'
    def texts: [.. | objects | .textRun?.content? | strings] | join("") | sub("\\s+$"; "");
    .slides | to_entries[] |
    "## スライド \(.key + 1)\(if .value.slideProperties.isSkipped then "（非表示）" else "" end)\n",
    (if (.value | visual) then "画像: slide-\(.key + 1).png\n" else empty end),
    ([.value.pageElements[]? | texts | select(test("\\S"))] | join("\n")),
    (.value.slideProperties.notesPage as $n
      | [$n.pageElements[]? | select(.objectId == $n.notesProperties.speakerNotesObjectId) | texts] | join("")
      | if test("\\S") then "\n### ノート\n\n" + . else empty end),
    ""' "$WORK/presentation.json" >"$WORK/slides.md" || ng "スライドの文字を読み取れません"
  jq -r "$VISUAL"' .slides | to_entries[] | select(.value | visual) | "\(.key + 1) \(.value.objectId)"' "$WORK/presentation.json" |
  while read -r n page; do
    url="$(api slides presentations pages getThumbnail --params "$(jq -cn --arg id "$ID" --arg p "$page" '{presentationId: $id, pageObjectId: $p, "thumbnailProperties.mimeType": "PNG", "thumbnailProperties.thumbnailSize": "LARGE"}')" </dev/null 2>/dev/null | jq -r '.contentUrl // empty')"
    # contentUrl は Google が発行する一時的な URL で、認証なしで取得できる
    if [ -z "$url" ] || ! curl -fsS --proto '=https' --max-time 60 -o "$WORK/slide-$n.png" "$url" </dev/null; then
      rm -f "$WORK/slide-$n.png"; echo "[WARN] スライド $n の画像を取得できません。文字からだけ判断する"
    fi
    sleep 1   # Slides API の上限 (1 分に 60 回) に合わせる
  done
  rm -f "$WORK/presentation.json"
fi

jq -r '"[OK] \(.name)\nURL: \(.webViewLink)\n最終更新: \(.modifiedTime)"' <<<"$meta"
ls -1 "$WORK"/*
# ファイル名に使えない文字は _ に替え、同じ名前があれば _2、_3 … を付ける (jq は文字単位で切る)
name="$(jq -r '.name | gsub("[[:cntrl:]/\\\\:*?\"<>|]"; "_") | .[0:80]' <<<"$meta")"
name="$(date +%Y%m%d)_${name:-$ID}"
dest="$OUT/$name.md"; i=2
while [ -e "$dest" ]; do dest="$OUT/${name}_$i.md"; i=$((i + 1)); done
echo "レビュー結果の保存先: $dest"
