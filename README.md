# KVM ノードプロビジョニング + Kubernetes 構築基盤

このリポジトリは、Terraform と `dmacvicar/libvirt` provider を使って KVM/libvirt 上に仮想ノードを作成し、さらに Ansible で Kubernetes クラスタの初期化・ノード参加までを自動化する構成です。

## 1. 構成の概要

```text
.
├── Terraform/                       # Terraform の本体
│   ├── composition/                # Terraform のルート構成
│   │   ├── main.tf                  # libvirt domain / volume を node 単位で生成
│   │   ├── variables.tf             # nodes などの定義
│   │   ├── terraform.tfvars        # 実際のノード構成
│   │   └── tests/                  # terraform test
│   ├── infrastructure_module/      # 1 node 分の論理モジュール
│   ├── resource_module/            # libvirt volume / domain / cloud-init などのリソース実装
│   └── terraform.tfvars.example    # サンプル設定
├── ansible/
│   ├── inventory.yml               # Terraform により生成される実行用 inventory
│   ├── inventory.yml.tftpl         # inventory 生成テンプレート
│   ├── site.yml                    # 全ロールを呼び出す playbook
│   ├── group_vars/all.yml          # Kubernetes/KubeVirt/NFS の共通変数
│   └── roles/
│       ├── common/                 # OS 前提設定
│       ├── container_runtime/      # containerd 設定
│       ├── k8s_packages/           # kubeadm/kubelet/kubectl 導入
│       ├── control_plane/          # kubeadm init、CNI、SSH 鍵生成
│       ├── worker/                 # worker のクラスタ参加
│       └── kubevirt/               # KubeVirt、CDI、NFS、DataVolume
├── K8s_yml/                        # Kubernetes/KubeVirt マニフェスト
├── doc/                            # 手動手順と自動化対象の仕様
├── historys/                       # 作業履歴
├── README.md
└── .gitignore
```

Terraform は `Terraform/composition` で Node 定義を展開して各 VM を作成し、cloud-init により `ubuntu` ユーザーと SSH 公開鍵を設定します。その後、`ansible/inventory.yml` が自動生成され、Ansible からノードへ接続して Kubernetes の準備を進めます。

## 2. 主要な機能

- KVM/libvirt 上の仮想ノード作成
- Ubuntu 22.04 Jammy cloud image を backing image として利用
- cloud-init による初期ユーザー作成と SSH 設定
- `role` ごとの inventory 自動生成
  - `control` -> `control_plane`
  - `worker` -> `worker_node`
- Ansible による Kubernetes 前提設定とクラスタ構築
- control plane 上での ED25519 SSH 鍵ペア生成
- KubeVirt Operator/CR と CDI の導入
- NFS サーバー、NFS provisioner、デフォルト StorageClass の構築
- Ubuntu cloud image 用 DataVolume の apply と `Succeeded` 待機

## 3. 前提条件

- Linux ホスト
- Terraform 1.6 以上
- KVM / libvirt
- `qemu:///system` への接続
- `dmacvicar/libvirt` provider
- Ubuntu 22.04 cloud image
- SSH 公開鍵ファイル
- Ansible と `ansible.posix` collection
- `kubectl`、`kubeadm`、`kubelet`、`helm`（Ansible が対象ノードへ導入）
- KVM が利用可能なホスト（`/dev/kvm`）

## 4. 事前準備

### Ubuntu cloud image の用意

```bash
mkdir -p ~/tmp_disk
wget -O ~/tmp_disk/ubuntu-22.04-cloudimg.qcow2 \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

`Terraform/composition/terraform.tfvars` の `image_path` にダウンロードしたファイルの絶対パスを設定します。

```hcl
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
cloudinit_user = "ubuntu"
user_password = "ubuntu"

nodes = [
  {
    domain_name        = "control-plane-01"
    instance_id        = "control-plane-01"
    hostname           = "control-plane-01"
    cloudinit_name     = "control-plane-01-seed.iso"
    volume_name        = "control-plane-01.qcow2"
    image_path         = "/home/your-user/tmp_disk/ubuntu-22.04-cloudimg.qcow2"
    volume_pool        = "default"
    volume_capacity    = 42949672960
    volume_format      = "qcow2"
    volume_target      = { format = { type = "qcow2" } }
    domain_memory      = 4096
    domain_memory_unit = "MiB"
    domain_vcpu        = 2
    domain_type        = "kvm"
    disk_driver        = { type = "qcow2", discard = "unmap" }
    disk_target        = { dev = "vda", bus = "virtio" }
    os = {
      type         = "hvm"
      type_arch    = "x86_64"
      type_machine = "q35"
      boot_devices = [{ dev = "hd" }]
    }
    cpu      = { mode = "host-passthrough" }
    features = { acpi = true, apic = {} }
    devices = {
      interfaces = [{ model = { type = "virtio" }, source = { network = { network = "default" } } }]
      consoles   = [{ target = { type = "serial", port = "0" } }]
      graphics   = [{ spice = { auto_port = true, listeners = [{ address = {} }] } }]
    }
    role = "control"
  }
]
```

## 5. Terraform による VM 作成

```bash
cd Terraform/composition
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

`terraform apply` の途中で、各 VM の DHCP アドレスが取得され、`ansible/inventory.yml` が自動生成されます。生成された inventory はそのまま `ansible` 側の playbook 実行で利用できます。

```bash
terraform output domain_names
terraform output volume_names
terraform output cloudinit_names
cat ../../ansible/inventory.yml
```

## 6. Ansible による接続確認と構築

以下のコマンドで接続確認を行います。

```bash
ansible k8s_cluster -i ./ansible/inventory.yml -m ping
```

構築を進める場合は、playbook を実行します。

```bash
cd ansible
ansible-playbook -i inventory.yml site.yml
```

`site.yml` には以下のロールが定義されています。

- `common`
- `container_runtime`
- `k8s_packages`
- `control_plane`
- `worker`
- `kubevirt`

`kubevirt` ロールは次の処理を control plane を中心に実行します。

1. 全ノードの KVM 前提条件確認と AppArmor 停止
2. KubeVirt Operator/CR の導入と `Available` 待機
3. NFS サーバーと worker の NFS クライアント設定
4. KubeVirt の `ExpandDisks` 有効化
5. CDI、Helm、NFS external provisioner の導入
6. `K8s_yml/ubuntu/tmp_dv.yml` の DataVolume apply と `Succeeded` 待機

共通設定は [ansible/group_vars/all.yml](ansible/group_vars/all.yml) で管理します。

- `nfs_export_path`: NFS export のパス
- `nfs_export_options`: NFS export の公開オプション
- `nfs_storage_class_name`: StorageClass 名（既定値は `nfs-client`）
- `kubevirt_wait_timeout`: KubeVirt の起動待機時間
- `datavolume_wait_timeout`: DataVolume の完了待機時間

control plane の `ansible_user` には `/home/<ユーザー>/.ssh/id_ed25519` と対応する公開鍵を作成します。既存の秘密鍵は上書きしません。

### KubeVirt VM の起動サンプル

DataVolume `ubuntu-image` が `Succeeded` になった後、[K8s_yml/ubuntu/test_cmd_vm.txt](K8s_yml/ubuntu/test_cmd_vm.txt) のコマンドで Ubuntu VM を作成できます。コマンドは `ubuntu-vm.yaml` を生成して apply します。

```bash
cd K8s_yml/ubuntu
cat << EOF > ubuntu-vm.yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ubuntu-vm
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata:
        name: ubuntu-dv
      spec:
        storage:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 10Gi
          storageClassName: nfs-client
        source:
          pvc:
            name: ubuntu-image
  template:
    metadata:
      labels:
        kubevirt.io/domain: ubuntu-vm
    spec:
      domain:
        devices:
          disks:
          - disk:
              bus: virtio
            name: datavolumedisk
          - disk:
              bus: virtio
            name: cloudinitdisk
        resources:
          requests:
            memory: 2Gi
      volumes:
      - dataVolume:
          name: ubuntu-dv
        name: datavolumedisk
      - cloudInitNoCloud:
          userData: |
            #cloud-config
            users:
              - name: ubuntu
                sudo: ['ALL=(ALL) NOPASSWD:ALL]
                shell: /bin/bash
                ssh_authorized_keys:
                  - $(cat ~/.ssh/id_rsa.pub 2>/dev/null || cat ~/.ssh/id_ed25519.pub)
            chpasswd:
              list: |
                ubuntu:ubuntu
              expire: False
            ssh_pwauth: True
        name: cloudinitdisk
EOF
kubectl apply -f ubuntu-vm.yaml
```

作成後は次のコマンドで VM と VMI の状態を確認します。

```bash
kubectl get vm ubuntu-vm
kubectl get vmi ubuntu-vm
```

## 7. 役割と作成ルール

`Terraform/composition/terraform.tfvars` に設定する `role` は次のように使われます。

- `control` : control-plane ノードとして `control_plane` グループに登録
- `worker` : worker ノードとして `worker_node` グループに登録

`domain_name` は `for_each` のキーとして使われるため、重複しないようにします。

## 8. 後片付け

```bash
cd Terraform/composition
terraform destroy
```

## 9. 変更履歴

最新の対応内容は [historys/HISTORY.md](historys/HISTORY.md) を参照してください。KubeVirt 関連の詳細は [historys/KubevirtHISTORY.md](historys/KubevirtHISTORY.md) を参照してください。

---

本構成は、KVM の VM 作成・DHCP での IP 取得・cloud-init 設定・Ansible 構成管理までを一連の流れとして扱えるように整理しています。既存のノードに対しては `terraform apply` を繰り返し、必要に応じて inventory と playbook が更新される運用を想定しています。

## テスト

native Terraform test を使用しています。テストは `plan` モードで実行されるため、libvirt リソースを実際には作成しません。

```bash
terraform -chdir=Terraform/composition test
```

テストファイルは [Terraform/composition/tests/nodes.tftest.hcl](Terraform/composition/tests/nodes.tftest.hcl) です。複数の node から domain と volume が生成され、それぞれの名前が設定値どおりになることを検証します。

## コンソール接続

ゲスト OS 側でシリアルログインを有効にした後、次のコマンドで接続できます。

```bash
virsh console node-01 --force
```

GRUB と serial getty の設定例:

```bash
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8 /' /etc/default/grub
sudo update-grub
sudo systemctl enable --now serial-getty@ttyS0.service
```

## 注意事項

- `image_path` は実行環境から参照できるパスを指定してください。
- `domain_name` や `volume_name` を変更すると、Terraform は既存リソースを別リソースとして扱う場合があります。
- 既存 state がある状態で resource/module 名を変更した場合は、`terraform plan` を確認してから apply してください。
- KVM/libvirt 上の手動変更は Terraform state と不一致になるため、可能な限り Terraform 経由で管理してください。

## 参考ファイル

- [Terraform/terraform.tfvars.example](Terraform/terraform.tfvars.example)
- [Terraform/composition/main.tf](Terraform/composition/main.tf)
- [Terraform/infrastructure_module/main.tf](Terraform/infrastructure_module/main.tf)
- [Terraform/resource_module/libvirt_volume/main.tf](Terraform/resource_module/libvirt_volume/main.tf)
- [Terraform/resource_module/libvirt_domain/main.tf](Terraform/resource_module/libvirt_domain/main.tf)

## 参考サイト

- [KubeVirt 公式: Kubernetes へのインストール](https://kubevirt.io/user-guide/cluster_admin/installation/#installing-kubevirt-on-kubernetes)
- [Server World: Ubuntu 22.04 の AppArmor 設定](https://www.server-world.info/query?os=Ubuntu_22.04&p=apparmor&f=1)
- [おのえ.dev: KubeVirt の構築・運用例](https://www.onoe.dev/blog/kubevirt/)
