

```markdown
# NFSバックエンド Kubernetesストレージ基盤 構築手順

このドキュメントは、NFSサーバーの構築からHelmを用いた `nfs-subdir-external-provisioner` のデプロイまでの手順をまとめたものです。
```


## 1. kubevirt.io/v1.KubeVirtを修正
ubeVirtが自動的にVMの仮想ディスクのサイズを拡張し、ゲストOSに認識させる設定を行います。

```bash
# kubevirt.io/v1.KubeVirtを修正
kubectl patch kubevirt kubevirt -n kubevirt --type='merge' -p='{
  "spec": {
    "configuration": {
      "developerConfiguration": {
        "featureGates": ["ExpandDisks"]
      }
    }
  }
}'

```

# 2. CDI のインストール
```bash
export VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml
```

## 3. NFSサーバーのセットアップ
NFSサーバーとなるノードで実行します。

```bash
# NFSパッケージのインストールとディレクトリ作成
sudo apt update && sudo apt install -y nfs-kernel-server
sudo mkdir -p /srv/nfs/kubedata
sudo chown -R nobody:nogroup /srv/nfs/kubedata
sudo chmod 777 /srv/nfs/kubedata

# exports 設定の追加（全クラスターノードからのアクセスを許可）
echo "/srv/nfs/kubedata *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports

# 設定の適用とサービス再起動
sudo exportfs -a
sudo systemctl restart nfs-kernel-server

```

## 4. NFSクライアントのインストール

すべてのワーカーノードで実行します。

```bash
# 全ワーカーノードに NFS クライアントをインストール
sudo apt update && sudo apt install -y nfs-common

```

## 5. Helm のインストール

管理端末または対象ノードで実行します。

```bash
# Helm のインストール
curl [https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3](https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3) | bash

```

## 6. プロビジョナーのデプロイ（Helm）

Helmリポジトリを追加し、NFSプロビジョナーとデフォルトストレージクラスをデプロイします。

```bash
# Helm リポジトリの追加
helm repo add nfs-subdir-external-provisioner [https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/](https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/)
helm repo update

# プロビジョナーのインストール（IPアドレスとパスを指定）
# 例: IP アドレスが 192.168.1.10 の場合
helm install nfs-client nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=<control-plane-01のIPアドレス> \
  --set nfs.path=/srv/nfs/kubedata \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=true

```
