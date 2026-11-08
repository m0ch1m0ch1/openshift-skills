# openshift-gws-doc-review

Google ドキュメント・スライドを [gws](https://github.com/googleworkspace/cli) で読み取り、技術的な誤りと懸念点をまとめるスキルです。

- 技術的な正しさ（仕様、既定値、コマンド、設定ファイル、構成図など）と、サポートの範囲（サポートされない構成、Technology Preview、サポートの終わったバージョンなど）を見ます。資料の章立てや文章の表現は見ません。
- 問題のある箇所だけを、場所・内容・根拠の表にします。

## 前提条件

- gws と [jq](https://jqlang.org/) がインストールされ、`gws auth login` で認証している。
- （任意）rhdocs と rhkcs の MCP。つなぎ方は[ルートの README](../../../README.md#red-hat-の情報源をつなぐ任意) を参照してください。

## 使い方

```text
# 資料の URL を聞いてから始める
/openshift-gws-doc-review

# 資料の URL を指定して始める
/openshift-gws-doc-review <資料の URL>
```

例: `/openshift-gws-doc-review https://docs.google.com/presentation/d/<ID>/edit`

## 成果物

レビュー結果を `gws-doc-reviews/<レビューした日>_<資料名>.md` に保存します。
