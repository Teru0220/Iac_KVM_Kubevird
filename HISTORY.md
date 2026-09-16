# IaC_tf_KVM 構築対応記録 (Development Log)

## 概要
このドキュメントは、KVM (Libvirt) 上に Kubernetes クラスターを構築、その後KubeVirtを導入した過程と、検証中に発生した問題・解決策をまとめた作業履歴である。

構築は次の順序で進めた。

1. KVM ノードの起動と接続を安定化
2. Terraform の構成をモジュール化
3. cloud-init と Ansible でノード構築を自動化
4. Kubernetes と KubeVirt を導入

---

## 対応履歴・詳細

### 1. 2026-09-01: KVM ノードの起動安定化とコンソール設定
Kubernetes ノードを載せる KVM を作成するため、`dmacvicar/libvirt` provider v0.9.x の domain 設定を検証した。

* **ディスク形式**
  * qcow2 イメージが `raw` として扱われる問題を確認した。
  * `disk` ブロックで `driver.type = "qcow2"`、`target.dev = "vda"`、`target.bus = "virtio"` を明示し、正しい形式で接続できるようにした。
* **Q35 の起動安定化**
  * `pciehp: Slot(0): Card not present` が繰り返されて起動が停止する問題を確認した。
  * `type_machine = "pc"` で切り分けた後、Q35 を維持する構成として graphics、video、ACPI/APIC を明示する方針を確定した。
  * Control Plane と worker の domain XML を比較し、`features` の ACPI/APIC 設定不足が initramfs の LVM 活性化タイムアウトの原因と判断した。
  * `acpi = true`、`apic = {}`、`vm_port.state = "off"` を追加し、Ubuntu 24.04 の起動を確認した。
* **画面・コンソール・ネットワーク**
  * CUI ノードの画面出力と接続手段を確保するため、SPICE graphics、virtio video、serial console、VirtIO-RNG を追加した。
  * ディスクには qcow2 と VirtIO target、ネットワークには virtio インターフェースを使用した。
* **Terraform state の復旧**
  * 壊れた domain を参照した際に `ObjectStatus(0)` の panic が発生するケースを確認した。
  * `terraform state rm` でリソースを state から切り離し、`virsh destroy` / `virsh undefine` で孤立した domain を削除して復旧する手順を整理した。
* **シリアルコンソールの運用**
  * 接続競合時は `virsh console <domain> --force` を使用する。
  * ゲスト側で `console=ttyS0,115200n8` を GRUB に追加し、`serial-getty@ttyS0.service` を有効化すると、`virsh console` からログイン画面を利用できる。
* **今後の検証**
  * `vm_port`、clock、metadata、ACPI/APIC を個別に削減検証し、Q35 ノードに必要な最小構成を確定する。

---

### 2. 2026-09-02: 初期検証と KVM ノードの要件確定
* **起動要件**
  * Q35 マシンタイプで VM を安定して起動するため、`acpi = true` と `apic = {}` を設定した。
* **ノードのリソース**
  * Control Plane: 4 GB RAM、40 GB Disk、2 vCPU
  * Worker Node: 8 GB RAM、40 GB Disk、2 vCPU（2 台）
* **動作確認**
  * 最小構成の `libvirt_domain` / `libvirt_volume` で VM を作成し、SSH 接続とネットワーク疎通を確認した。

---

### 3. 2026-09-03: Terraform Composition 構成への移行
Terraform Best Practices の Composition 設計原則に従い、単一ファイル中心の構成を次の 3 層へ分割した。

1. **`composition/`（最上位・ルート）**
  * インフラ全体を組み立てるルートモジュール。
  * `for_each` でノード定義のマップを展開し、複数ノードを動的にプロビジョニングする。
2. **`infrastructure_module/`（中間層・論理まとめ）**
  * `libvirt_domain` やストレージなどを組み合わせ、「KVM ノード」という論理単位にまとめる。
3. **`resource_module/`（最下層・アトミックリソース）**
  * `libvirt_domain`、`libvirt_volume` など、単一リソースを管理する最小モジュール。

---

### 4. 2026-09-07: cloud-init と Ubuntu cloud image の導入
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

---

### 5. 2026-09-08: Ansible inventory の自動生成と IP アドレス取得
* Terraform で作成した各 libvirt domain を起動し、DHCP リースから割り当てられた IPv4 アドレスを取得する処理を追加。
* ノード設定に `role` を追加し、`control` と `worker` の役割を指定可能にした。
* Terraform の `local_file` resource で `ansible/inventory.yaml` を自動生成。
  * `control` ノードを `control_plane`、`worker` ノードを `worker_node` に分類。
  * 接続ユーザー、SSH 秘密鍵、Python interpreter などの Ansible 接続設定を inventory に出力。
* `ansible k8s_cluster -i ./ansible/inventory.yaml -m ping` による作成ノードの SSH 接続確認に対応。

---

### 6. 2026-09-10: Ansible Playbook 実行と運用手順の確定
* Terraform で生成した `ansible/inventory.yml` を使って、Ansible によるノード設定と Kubernetes 基盤の導入を実行した。
* `ansible-playbook -i inventory.yml site.yml` を実行し、Ansible のロール群 (`common`, `container_runtime`, `k8s_packages`, `control_plane`, `worker`) が正常に動作することを確認した。
* `control` ノードが `control_plane` グループ、`worker` ノードが `worker_node` グループにマッピングされるよう inventory の自動生成処理を整理した。
* README を実際の運用手順に合わせて更新し、Terraform から Ansible への接続・デプロイ手順を明確化した。
* クラスタ接続確認 (`ansible k8s_cluster -i ./ansible/inventory.yml -m ping`) と Ansible Playbook 実行を、実運用の一連の流れとして確定した。

---

### 7. 2026-09-15: KubeVirt 前提条件確認と導入手順の検証
* `doc/KubeVirtCheckList.md` のチェック項目に沿って、KubeVirt 導入前の前提条件を確認した。
  * Kubernetes クラスターが起動し、全ノードが `Ready` であること。
  * `kubectl cluster-info` で Kubernetes API Server に接続できること。
  * 全ノードで `virt-host-validate qemu` を実行し、`/dev/kvm` が利用可能であること。
  * AppArmor/SELinux による KVM やコンテナランタイムへのアクセス拒否がないこと。
  * CNI プラグインの Pod が正常に稼働していること。
  * Kubernetes バージョンが KubeVirt の対応範囲に含まれること。
  * KubeVirt と VM の稼働に必要な CPU・メモリが確保されていること。
* KubeVirt 公式サイトのインストール手順を参照し、`doc/kubevirtInstallation.md` の手順を実行した。
  * KubeVirt Operator のリリース YAML を apply。
  * KubeVirt カスタムリソースを apply。
  * `kubevirt` リソースが `Available` になるまで待機。
  * `kubevirt` namespace の Operator、`virt-api`、`virt-controller`、`virt-handler` などの Pod を確認。
* 導入後の試行錯誤により、KubeVirt 本体だけでは VM 用のディスクを準備できず、`doc/pvcstart.md` の処理が必要であることを確認した。
  * `ExpandDisks` feature gate の有効化。
  * CDI Operator/CR の導入。
  * NFS サーバーと NFS クライアントの設定。
  * Helm による NFS external provisioner と `nfs-client` StorageClass の導入。
  * DataVolume を作成し、外部の Ubuntu cloud image を CDI 経由で取り込む処理。
* 上記の確認結果をもとに、KubeVirt インストール、CDI、NFS、DataVolume の処理を Ansible へ組み込む方針を確定した。

---

### 8. 2026-09-16: KubeVirt とストレージ処理の Ansible 統合
* `doc/kubevirtRequirements.md` の内容を `ansible/roles/kubevirt` に統合した。
  * `virt-host-validate qemu` による仮想化支援機能の検証。
  * `/dev/kvm` の権限設定と `kvm` グループへの追加。
  * AppArmor プロファイルの解除、サービス停止、無効化。
* `doc/kubevirtInstallation.md` の内容を Ansible 化した。
  * KubeVirt Operator と KubeVirt CR の導入。
  * KubeVirt の `Available` 状態待機。
* `doc/pvcstart.md` の内容を Ansible 化した。
  * `ExpandDisks` の有効化。
  * CDI Operator/CR の導入。
  * NFS サーバー、worker の NFS クライアント、NFS external provisioner の構築。
  * `nfs-client` StorageClass のデフォルト設定。
  * `K8s_yml/ubuntu/tmp_dv.yml` の apply と DataVolume `Succeeded` 待機。
* control plane の `ansible_user` 用 ED25519 SSH 鍵ペア生成処理を追加した。
* ロール名を内容に合わせて `storage` から `kubevirt` へ変更した。
* README と作業履歴の構成を現行の Terraform/Ansible/KubeVirt フローに合わせて更新した。

---

#### 検証
* `ansible-playbook --syntax-check -i inventory.yml site.yml`
* `ansible-playbook --list-tasks -i inventory.yml site.yml`
* `git diff --check`