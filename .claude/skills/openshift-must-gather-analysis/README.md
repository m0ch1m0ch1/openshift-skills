# openshift-must-gather-analysis

OpenShift の must-gather を omc で調べ、指定した事象の原因と対処案を報告書にまとめるスキルです。実クラスタには接続しません。

クラスタ全体を網羅的に点検するもの（TSR のような確認）ではありません。事象が現れている場所から「なぜそうなったか」をさかのぼり、その道筋の上だけを調べます。

- 事象を聞いたら、この調査で答えること（確認事項）と、確認事項ごとに調べること（調査項目）を `checklist.md` に書いて示し、調べながらチェックしていきます。
- 報告書（`report.md`）では、確認事項ごとに答えます。事実には根拠（must-gather のどのファイルの何行目に、何が書かれているか）を付け、スクリプトが、そのファイルと行が実在し、引用がその行に書かれているかを確かめます。
- 対処案には、できるだけ情報元（公式ドキュメント、ナレッジベース、バグ報告）を付けます。
- must-gather で確かめられなかったことは、確かめるコマンドと一緒に「未確認事項」に書きます。

## 前提条件

- [omc](https://github.com/gmeghnag/omc) がインストールされている（入っていなければ、スキルが案内します）。
- 調べる must-gather（アーカイブか、展開したディレクトリ）がある。事象に OpenShift 本体以外の製品が関わる場合は、その製品の must-gather か `oc adm inspect` の結果もあるとよい（スキルが必要に応じて依頼します）。
- （任意）Red Hat ドキュメントの MCP（rhdocs）。`/mcp` で `rhdocs` を認証すると、公式ドキュメントを要約されずに読み、情報元として確かめられます。
- （任意）Red Hat ナレッジベースの MCP（rhkcs）。[rhkcs-mcp-setup](../rhkcs-mcp-setup/README.md) で導入すると、ログインが必要な記事も情報元として確かめられます。

## 使い方

```text
# 調べたい事象を聞いてから始める
/openshift-must-gather-analysis

# 調べたい事象を指定して始める
/openshift-must-gather-analysis <調べたい事象>
```

例: `/openshift-must-gather-analysis 昨日の 17 時ごろから、openshift-monitoring の Pod が CrashLoopBackOff になっている`

次の順に進みます。

1. omc の導入状況と、Red Hat ドキュメントの MCP（rhdocs）とナレッジベースの MCP（rhkcs）が使えるかを確認する。使えないものがあれば、導入せずに進めてよいかを確認する。
2. must-gather を置く場所を案内し、置いたら展開する（ケース名を指定しなければ、must-gather の取得日時になる）。
3. 取得日時とバージョンを示して事象を整理し、`checklist.md` に事象・確認事項・調査項目を書いて示す。
4. 異常の概要から調査の起点を決め、調査項目を見直す。
5. `report.md` を作り、調査項目を調べてチェックしながら、起点から「なぜそうなったか」をさかのぼる。見つけた事実と未確認事項は、その都度報告書に書き足す。
6. 原因までの道筋を時系列で示し、事象と合っているかを確認する。
7. 確認事項ごとの回答と対処案を、情報元と一緒に整理する（rhdocs が使えれば公式ドキュメントをそれで読み、rhkcs が使えればログインが必要なナレッジベースの記事も読んで確かめる）。情報元から、まだ調べていない原因や影響が分かったら、5 に戻って must-gather で確かめる。
8. 報告書の残りの節を書き、`mg.sh lint` の確認を通す。lint で確かめられないこと（推論、引用の妥当性、情報元の内容、対処案のコマンドの書き方）も見直す。

## 成果物

```text
input/openshift-must-gather-analysis/<ケース名>/    調べた must-gather（展開したもの）
output/openshift-must-gather-analysis/<ケース名>/
├── checklist.md    事象、確認事項、調査項目（チェックリストと結果）
└── report.md       調査報告（概要、事象、確認事項、時系列、確認した事実、原因、対処案、未確認事項、情報元）
```

## 構成

```text
openshift-must-gather-analysis/
├── SKILL.md                      # 進め方
├── references/analysis-guide.md  # 調べ方、コマンド、情報元の探し方、checklist.md と報告書の書き方
├── templates/checklist.md        # checklist.md のひな形
├── templates/report.md           # report.md のひな形
└── scripts/mg.sh                 # 処理の本体（使い方は bash .claude/skills/openshift-must-gather-analysis/scripts/mg.sh で表示）
```

## データの置き場所

- must-gather は `input/openshift-must-gather-analysis/<ケース名>/` に、確認事項と報告書は `output/openshift-must-gather-analysis/<ケース名>/` に置きます（Git の管理対象外。環境変数 `MUST_GATHER_DIR` と `ANALYSIS_DIR` で変えられます）。`input/openshift-must-gather-analysis/` の直下に置いた must-gather は、どれを使うかを確かめてから、ケースに移します。展開した元のアーカイブは消します。
- omc の設定（どの must-gather を使うか）は、`~/.omc/omc.json` ではなく `output/openshift-must-gather-analysis/.omc/omc.json` に保存します（環境変数 `OMCCONFIG`。`.claude/settings.json` の `env` で設定しており、Claude Code を起動し直すと有効になります）。
- `mg.sh` はリポジトリの外に書き込みません。must-gather の外を指すパスやシンボリックリンクは読まず、展開先の外を指すファイルを含むアーカイブは展開しません。外を指すシンボリックリンクがあれば、続きのアーカイブも展開しません。
