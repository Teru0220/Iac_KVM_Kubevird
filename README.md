# KVM ノードプロビジョニング

Terraform と `dmacvicar/libvirt` provider を使用して、ローカルの KVM/libvirt 環境へ複数の仮想ノードと qcow2 ボリュームを作成する構成です。

## 構成

```text
composition/
  main.tf              # nodes を for_each で展開するルート構成
  variables.tf         # nodes の型定義
  terraform.tfvars     # 作成するノードの具体的な設定
  provider.tf          # libvirt provider
  tests/               # terraform test 用のテスト

infrastructure_module/
  main.tf              # 1ノード分の volume/domain module を接続
  variables.tf
  outputs.tf

resource_module/
  libvirt_volume/      # 1ボリュームを作成
  libvirt_domain/      # 1ドメインを作成
  libvirt_cloudinit_disk/   # cloud-init ISOを生成
  libvirt_cloudinit_volume/ # cloud-init ISOをvolume poolへ登録

ansible/
  inventory.yaml       # Terraform が生成する Ansible inventory
  inventory.yaml.tftpl # inventory のテンプレート
```

処理の流れは次のとおりです。

```text
composition
  -> infrastructure_module (node 単位)
    -> libvirt_volume
    -> libvirt_cloudinit_disk
    -> libvirt_cloudinit_volume
    -> libvirt_domain
```

`for_each` は `composition` だけで使用します。下位 module は常に1つの `node` を処理し、OS volume と cloud-init volume の output を domain module に渡します。

## 前提条件

- Linux
- Terraform 1.6 以上
- KVM/libvirt
- `qemu:///system` に接続できる libvirt 環境
- `dmacvicar/libvirt` provider 0.9.9
- Ubuntu 22.04 (Jammy) の cloud image
- cloud-init 対応の Ubuntu cloud image

## Ubuntu cloud image の準備

Ubuntu の公式 cloud image を次のページからダウンロードします。

<https://cloud-images.ubuntu.com/jammy/current/>

例として、作業用ディレクトリへ Jammy の qcow2 イメージをダウンロードします。

```bash
mkdir -p ~/tmp_disk
wget -O ~/tmp_disk/ubuntu-22.04-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

`composition/terraform.tfvars` の `image_path` には、ダウンロードしたイメージの絶対パスを指定します。

```hcl
image_path = "/home/your-user/tmp_disk/ubuntu-22.04-cloudimg-amd64.img"
```

Terraform はこのイメージを backing image としてノードごとの qcow2 volume を作成し、ドメインへ接続します。OS のインストールや初期設定を済ませたイメージを別途用意する必要はありません。

```text
Ubuntu Jammy cloud image
  |
  +-- node-01.qcow2 -> node-01
  +-- node-02.qcow2 -> node-02
```

イメージが存在しない場合、パスや形式が実際のファイルと異なる場合は、ノードの作成に失敗します。Terraform を実行するユーザーから読み取り可能な場所にイメージを配置してください。

## cloud-init による初期設定

`libvirt_cloudinit_disk` が user-data と meta-data を含む cloud-init ISO を生成し、`libvirt_cloudinit_volume` が libvirt の storage pool へ登録します。その ISO を各ドメインへ接続することで、Ubuntu の初回起動時に cloud-init が次の設定を行います。

- `ubuntu` ユーザーの作成
- SSH 公開鍵の登録
- パスワード認証の無効化
- root ログインの無効化
- `hostname` と `instance_id` の設定

SSH 公開鍵は `ssh_public_key_path` で指定します。既定値は `~/.ssh/id_ed25519.pub` です。公開鍵ファイルが別の場所にある場合は、`composition/terraform.tfvars` で変更してください。

provider は [composition/provider.tf](composition/provider.tf) で次の URI を使用します。

```hcl
provider "libvirt" {
  uri = "qemu:///system"
}
```

Terraform 実行ユーザーが libvirt を操作できることを確認してください。

## ノード設定

具体的な設定は [composition/terraform.tfvars](composition/terraform.tfvars) の `nodes` 配列に記述します。ノードごとに全パラメータを個別指定できます。

```hcl
nodes = [
  {
    domain_name        = "node-01"
    instance_id        = "node-01"
    hostname           = "node-01"
    cloudinit_name     = "node-01-seed.iso"
    role               = "worker"
    volume_name        = "node-01.qcow2"
    image_path         = "/home/your-user/tmp_disk/jammy-server-cloudimg-amd64.img"
    volume_pool        = "default"
    volume_capacity    = 42949672960
    volume_format      = "qcow2"
    volume_target      = { format = { type = "qcow2" } }
    domain_memory      = 8192
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
      interfaces = [{
        model  = { type = "virtio" }
        source = { network = { network = "default" } }
      }]
      consoles = [{ target = { type = "serial", port = "0" } }]
      graphics = [{ spice = { auto_port = true, listeners = [{ address = {} }] } }]
    }
  }
]
```

`ssh_public_key_path` には cloud-init で登録するSSH公開鍵のパスを指定します。既定値は `~/.ssh/id_ed25519.pub` です。

### 主なパラメータ

| パラメータ | 説明 |
| --- | --- |
| `domain_name` | libvirt ドメイン名。`nodes` の `for_each` キーにも使用 |
| `instance_id` | cloud-init のインスタンス ID |
| `hostname` | cloud-init で設定するホスト名 |
| `cloudinit_name` | 作成する cloud-init ディスク名 |
| `role` | Ansible inventory のグループ（`control` または `worker`） |
| `volume_name` | 作成する libvirt volume 名 |
| `image_path` | Ubuntu cloud image の絶対パス |
| `volume_pool` | libvirt storage pool |
| `volume_capacity` | volume 容量（byte） |
| `volume_format` | volume と backing image の形式 |
| `volume_target` | volume の target 設定 |
| `domain_memory` | メモリ容量 |
| `domain_memory_unit` | メモリ単位 |
| `domain_vcpu` | vCPU 数 |
| `domain_type` | libvirt の仮想化タイプ |
| `disk_driver` | ドメインディスクの driver 設定 |
| `disk_target` | ドメインディスクの target 設定 |
| `os` | OS、アーキテクチャ、machine、boot 設定 |
| `cpu` | CPU モード |
| `features` | ACPI/APIC などの機能 |
| `devices` | ネットワーク、コンソール、グラフィックなどのデバイス |

`domain_name` は重複できません。重複すると `composition` の `for_each` キーが衝突します。

## 実行方法

Ubuntu cloud image と SSH 公開鍵を準備した後、作業ディレクトリを `composition` にして実行します。

```bash
cd composition
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

`terraform apply` は各ドメインを起動し、DHCP リースから取得した IPv4 アドレスを使って `ansible/inventory.yaml` を自動生成します。inventory には `role = "control"` のノードが `control_plane`、`role = "worker"` のノードが `worker_node` として登録されます。

適用後は作成された名前と生成された inventory を確認できます。

```bash
terraform output domain_names
terraform output volume_names
terraform output cloudinit_names
cat ../ansible/inventory.yaml
```

## Ansible からの接続確認

cloud-init による初回設定と SSH サービスの起動が完了した後、リポジトリのルートディレクトリから Ansible の ping module を実行します。inventory の `ansible_user` と秘密鍵のパスは `ansible/inventory.yaml` に定義されています。

```bash
ansible k8s_cluster -i ./ansible/inventory.yaml -m ping
```

接続先の IP アドレスは、libvirt の `default` ネットワークから DHCP で割り当てられます。IP アドレスを取得できない場合は、ドメインの起動状態、DHCP リース、cloud-init の完了状態を確認してから `terraform apply` を再実行してください。

削除する場合は、同じ `composition` ディレクトリで実行します。

```bash
terraform destroy
```

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
