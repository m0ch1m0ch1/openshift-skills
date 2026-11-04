<!-- result=PASS date=2026-11-04T00:03 version=4.22.20 fp=bc397752354c keep=0 -->
# 検証結果: MetalLB Operator のインストールと L2 モードの設定

- 結果: **PASS**（切り戻し OK / クリーンアップ OK）
- 日時: 2026-11-04 00:03
- 接続先: `https://api.<クラスタのドメイン>:6443`（プロジェクト default、OpenShift 4.22.20、system:admin）

| ステップ | 作業 | 結果 | 秒 |
| --- | --- | --- | --- |
| 01-operator | MetalLB Operator をインストールする | OK | 93 |
| 02-metallb | MetalLB のインスタンスを作成する | OK | 14 |
| 03-l2 | IP アドレスプールと L2 アドバタイズメントを作成する | OK | 2 |
| 04-test-app | 動作確認用のアプリケーションを LoadBalancer タイプの Service で公開する | OK | 4 |

## 成功条件 (DoD)

- [x] MetalLB Operator の CSV の PHASE が Succeeded になっている。（01-operator）
- [x] controller と speaker の Pod が Running になっている。（02-metallb）
- [x] LoadBalancer タイプの Service に IP アドレスプールの外部 IP アドレスが割り当てられ、ノードが layer2 でアナウンスし、作業端末からアクセスすると HTTP 200 が返る。（04-test-app）

成功条件をすべて満たしています（3/3）。

全ログ: run/logs/
