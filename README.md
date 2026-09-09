# KVM ノードプロビジョニング + Kubernetes 構築基盤

このリポジトリは、Terraform と `dmacvicar/libvirt` provider を使って KVM/libvirt 上に仮想ノードを作成し、さらに Ansible で Kubernetes クラスタの初期化・ノード参加までを自動化する構成です。

## 1. 構成の概要

```text
.
├── composition/                     # Terraform のルート構成
│   ├── main.tf                      # libvirt domain / volume を node 単位で生成
│   ├── variables.tf                 # nodes などの定義
│   ├── terraform.tfvars            # 実際のノード構成
│   └── tests/                      # terraform test
├── infrastructure_module/           # 1 node 分の論理モジュール
├── resource_module/                 # libvirt volume / domain / cloud-init などのリソース実装
├── ansible/
│   ├── inventory.yml                # Terraform により生成される実行用 inventory
│   ├── inventory.yml.tftpl          # inventory 生成テンプレート
│   ├── site.yml                    # 全ロールを呼び出す playbook
│   ├── group_vars/
│   └── roles/
├── README.md
├── HISTORY.md
└── terraform.tfvars.example
```

Terraform は `composition` で Node 定義を展開して各 VM を作成し、cloud-init により `ubuntu` ユーザーと SSH 公開鍵を設定します。その後、`ansible/inventory.yml` が自動生成され、Ansible からノードへ接続して Kubernetes の準備を進めます。

## 2. 主要な機能

- KVM/libvirt 上の仮想ノード作成
- Ubuntu 22.04 Jammy cloud image を backing image として利用
- cloud-init による初期ユーザー作成と SSH 設定
- `role` ごとの inventory 自動生成
  - `control` -> `control_plane`
  - `worker` -> `worker_node`
- Ansible による Kubernetes 前提設定とクラスタ構築

## 3. 前提条件

- Linux ホスト
- Terraform 1.6 以上
- KVM / libvirt
- `qemu:///system` への接続
- `dmacvicar/libvirt` provider
- Ubuntu 22.04 cloud image
- SSH 公開鍵ファイル

## 4. 事前準備

### Ubuntu cloud image の用意

```bash
mkdir -p ~/tmp_disk
wget -O ~/tmp_disk/ubuntu-22.04-cloudimg.qcow2 \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

`composition/terraform.tfvars` の `image_path` にダウンロードしたファイルの絶対パスを設定します。

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
cd composition
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
cat ../ansible/inventory.yml
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

## 7. 役割と作成ルール

`composition/terraform.tfvars` に設定する `role` は次のように使われます。

- `control` : control-plane ノードとして `control_plane` グループに登録
- `worker` : worker ノードとして `worker_node` グループに登録

`domain_name` は `for_each` のキーとして使われるため、重複しないようにします。

## 8. 後片付け

```bash
cd composition
terraform destroy
```

## 9. 変更履歴

最新の対応内容は [HISTORY.md](HISTORY.md) を参照してください。

---

本構成は、KVM の VM 作成・DHCP での IP 取得・cloud-init 設定・Ansible 構成管理までを一連の流れとして扱えるように整理しています。既存のノードに対しては `terraform apply` を繰り返し、必要に応じて inventory と playbook が更新される運用を想定しています。

## テスト

native Terraform test を使用しています。テストは `plan` モードで実行されるため、libvirt リソースを実際には作成しません。

```bash
terraform -chdir=composition test
```

テストファイルは [composition/tests/nodes.tftest.hcl](composition/tests/nodes.tftest.hcl) です。複数の node から domain と volume が生成され、それぞれの名前が設定値どおりになることを検証します。

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

- [terraform.tfvars.example](terraform.tfvars.example)
- [composition/main.tf](composition/main.tf)
- [infrastructure_module/main.tf](infrastructure_module/main.tf)
- [resource_module/libvirt_volume/main.tf](resource_module/libvirt_volume/main.tf)
- [resource_module/libvirt_domain/main.tf](resource_module/libvirt_domain/main.tf)
