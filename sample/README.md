# 成果物のサンプル

実際に検証・調査した結果をもとにした、スキルの成果物の例です。ノード名やクラスタのドメインなどは `<ノード名>` のような形に、ノードのネットワークの IP アドレスは 192.0.2.0/24 に置き換えています。

| サンプル | スキル | 内容 |
| --- | --- | --- |
| [openshift-runbook/hello-route/](openshift-runbook/hello-route/runbook.md) | openshift-runbook | nginx を Service と Route（edge TLS）で公開する |
| [openshift-runbook/metallb-l2/](openshift-runbook/metallb-l2/runbook.md) | openshift-runbook | MetalLB Operator を導入し、L2 モードで LoadBalancer の Service に外部 IP アドレスを割り当てる |
| [openshift-must-gather-analysis/20261104-005705/](openshift-must-gather-analysis/20261104-005705/report.md) | openshift-must-gather-analysis | SNO のアップデート中に、kube-apiserver の installer Pod が Error になった原因を調べる |

## openshift-runbook

```text
hello-route/
├── spec.md          # 目的、成功条件、前提条件、パラメータ（最初に合意する内容）、アクセス情報
├── runbook.md       # 検証済みの手順書（できあがるもの）
├── manifests/       # 適用する YAML
├── scripts/         # 各手順の確認スクリプトと、切り戻し（rollback.sh）
└── run/
    ├── result.md    # 検証の結果（各手順の OK/NG、成功条件、切り戻しとクリーンアップの結果）
    ├── server       # 検証した接続先
    └── logs/        # 各手順の出力
```

## openshift-must-gather-analysis

must-gather 自体は含めていません。

```text
20261104-005705/
├── checklist.md     # 確認事項と調査項目（調べた結果の事実の番号付き）
└── report.md        # 報告書（できあがるもの）
```
