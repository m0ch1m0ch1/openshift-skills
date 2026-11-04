<!-- result=PASS date=2026-11-04T10:16 version=4.22.20 fp=71689fe3b0d1 keep=0 -->
# 検証結果: Route を使用した nginx の公開

- 結果: **PASS**（切り戻し OK / クリーンアップ OK）
- 日時: 2026-11-04 10:16
- 接続先: https://api.<クラスタのドメイン>:6443（プロジェクト default、OpenShift 4.22.20、system:admin）

| ステップ | 作業 | 結果 | 秒 |
|---|---|---|---|
| 01-namespace | Namespace を作成する | OK | 1 |
| 02-deployment | nginx の Deployment を作成する | OK | 3 |
| 03-service | Service を作成する | OK | 1 |
| 04-route | Route（edge TLS）で公開する | OK | 2 |

## 成功条件 (DoD)

- [x] nginx の Pod が Ready になり、起動ログが出力されている。（02-deployment）
- [x] Route の URL に HTTPS でアクセスすると HTTP 200 が返る。（04-route）

成功条件をすべて満たしています（2/2）。

全ログ: run/logs/
