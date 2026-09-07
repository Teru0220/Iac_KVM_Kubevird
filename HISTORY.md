# IAAC_tf_KVM 構築対応記録 (Development Log)

## 概要
本プロジェクトは、KVM (Libvirt) 上に Kubernetes プラットフォームを構築するための Infrastructure as Code (IaC) 環境の整備記録である。単一の記述ファイル（モノリシック構成）から出発し、「Terraform Best Practices」に準拠した Composition パターン（3 階層構造）への移行を行った。

---

## 対応履歴・詳細

### 4. 2026-09-08: Ansible inventory の自動生成と IP アドレス取得
* Terraform で作成した各 libvirt domain を起動し、DHCP リースから割り当てられた IPv4 アドレスを取得する処理を追加。
* ノード設定に `role` を追加し、`control` と `worker` の役割を指定可能にした。
* Terraform の `local_file` resource で `ansible/inventory.yaml` を自動生成。
  * `control` ノードを `control_plane`、`worker` ノードを `worker_node` に分類。
  * 接続ユーザー、SSH 秘密鍵、Python interpreter などの Ansible 接続設定を inventory に出力。
* `ansible k8s_cluster -i ./ansible/inventory.yaml -m ping` による作成ノードの SSH 接続確認に対応。

### 1. 初期検証と動作要件の確定
* **`q35` マシンタイプの動作安定化**
  * `q35` マシンタイプで VM を正常起動させるため、`acpi = true` および `apic = {}` のフラグ設定が必須であることを特定・適用。
* **リソーススペックの策定**
  * **Control Plane**: 4GB RAM, 40GB Disk, 2 vCPU
  * **Worker Nodes**: 8GB RAM, 40GB Disk, 2 vCPU (×2 台)
* **実環境の動作検証**
  * 最小構成の `libvirt_domain` / `libvirt_volume` を使用し、SSH 接続およびネットワーク疎通を確認。

---

### 2. Composition パターンに基づく 3 階層構造の策定
公式ドキュメント (`terraform-best-practices.com`) の Composition 設計原則に従い、ディレクトリ構造を以下の 3 段階に再設計。

1. **`composition/`（最上位・ルート）**
   * インフラ全体のオーケストレーション。`for_each` を用いて変数のマップから動的にノードをプロビジョニング。
2. **`infrastructure_module/`（中間層・論理まとめ）**
   * 個々のリソースを組み合わせ、「KVM ノード」という論理単位としてまとめるモジュール。
3. **`resource_module/`（最下層・アトミックリソース）**
   * `libvirt_domain` や `libvirt_volume` など、単一リソースのみを管理する最小モジュール。

---

### 3. 2026-09-07: cloud-init と Ubuntu cloud image の導入
* Ubuntu 22.04 (Jammy) の公式 cloud image を OS の backing image として利用する構成へ変更。
  * `https://cloud-images.ubuntu.com/jammy/current/` から取得した qcow2 イメージを `image_path` に指定。
  * ノードごとの qcow2 volume を作成し、libvirt domain へ接続。
* cloud-init による初回起動時の初期設定を追加。
  * `libvirt_cloudinit_disk` で user-data と meta-data を含む ISO を生成。
  * `templatefile()` を使用して SSH 公開鍵を user-data へ展開。
  * `ssh_public_key_path` で公開鍵ファイルを指定可能にした。
* 公式 provider ドキュメントに合わせ、cloud-init ISO を storage pool の volume として登録。
  * `libvirt_cloudinit_volume` モジュールを追加。
  * domain から `source.volume` で cloud-init volume を接続。

