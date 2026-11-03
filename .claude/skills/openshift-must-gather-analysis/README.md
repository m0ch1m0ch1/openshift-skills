# openshift-must-gather-analysis

OpenShift の must-gather を omc で調べ、ユーザーが示した特定の事象の原因を深掘りし、原因と対処案を報告書にまとめるスキルです。実クラスタには接続しません。

クラスタ全体を網羅的に点検するもの（TSR のような確認）ではありません。事象が現れている場所から「なぜそうなったか」をさかのぼり、その道筋の上だけを調べます。

- 事象を聞いたら、この調査で答えること（確認事項）と、確認事項ごとに調べること（調査項目）を `checklist.md` に書いて示し、調べながらチェックしていきます。
- 報告書（`report.md`）では、確認事項ごとに答えます。事実には根拠（must-gather のどのファイルの何行目に、何が書かれているか）を付け、スクリプトが、そのファイルと行が実在し、引用がその行に書かれているかを確かめます。
- 対処案には、できるだけ情報元（公式ドキュメント、ナレッジベース、バグ報告）を付けます。
- must-gather で確かめられなかったことは、確かめるコマンドと一緒に「未確認事項」に書きます。

## 前提条件

- [omc](https://github.com/gmeghnag/omc) がインストールされている（入っていなければ、スキルが案内します）。
- 調べる must-gather（アーカイブか、展開したディレクトリ）がある。事象に OpenShift 本体以外の製品が関わる場合は、その製品の must-gather か `oc adm inspect` の結果もあるとよい（スキルが必要に応じて依頼します）。

## 使い方

調べたい事象を引数に書いて実行します（省略した場合は、スキルが聞きます）。

```
/openshift-must-gather-analysis 昨日の 17 時ごろから、openshift-monitoring の Pod が CrashLoopBackOff になっている
```

次の順に進みます。

1. omc の導入状況を確認する。
2. must-gather を置く場所を案内し、置いたら展開する（ケース名は must-gather の取得日時になる。置き場所の 1 つ上、ケースのディレクトリの直下に置いた場合も、置き場所に移す）。
3. 取得日時とバージョンを示して事象を整理し、`checklist.md` に事象・確認事項・調査項目を書いて示す。
4. 異常の概要から調査の起点を決め、調査項目を見直す。
5. `report.md` を作り、調査項目を調べてチェックしながら、起点から「なぜそうなったか」をさかのぼる。見つけた事実と未確認事項は、その都度報告書に書き足す。
6. 原因までの道筋を時系列で示し、事象と合っているかを確認する。
7. 確認事項ごとの回答と対処案を、情報元と一緒に整理する。
8. 報告書の残りの節を書き、`mg.sh lint` の確認を通す。lint で確かめられないこと（推論、引用の妥当性、情報元の内容、対処案のコマンドの書き方）も見直す。

## 成果物

```
must-gather-analyses/<ケース名>/
├── must-gather/    調べた must-gather（展開したもの）
├── checklist.md    事象、確認事項、調査項目（チェックリストと結果）
└── report.md       調査報告（概要、事象、確認事項、時系列、確認した事実、原因、対処案、未確認事項、情報元）
```

## 構成

```
openshift-must-gather-analysis/
├── SKILL.md                      # 進め方
├── references/analysis-guide.md  # 調べ方、コマンド、情報元の探し方、checklist.md と報告書の書き方
├── templates/checklist.md        # checklist.md のひな形
├── templates/report.md           # report.md のひな形
└── scripts/mg.sh                 # 処理の本体（使い方は bash .claude/skills/openshift-must-gather-analysis/scripts/mg.sh で表示）
```

## データの置き場所

- ケースは `must-gather-analyses/<case>/` に置きます（Git の管理対象外。環境変数 `ANALYSIS_DIR` で変えられます）。展開した元のアーカイブは消します。
- omc の設定（どの must-gather を使うか）は、`~/.omc/omc.json` ではなく `must-gather-analyses/.omc/omc.json` に保存します（環境変数 `OMCCONFIG`。`.claude/settings.json` の `env` で設定しており、Claude Code を起動し直すと有効になります）。
- `mg.sh` はリポジトリの外に書き込まず、must-gather の外を指すパスやアーカイブの中身は読みません。
