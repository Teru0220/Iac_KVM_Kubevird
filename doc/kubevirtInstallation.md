# KubeVirt インストール手順

KubeVirtのデプロイは、公式で提供されているリリースYAMLを使用して行います。

## 1. バージョンの取得とオペレーターのデプロイ

まず、最新（または安定した）KubeVirtのリリースバージョンを取得し、KubeVirtオペレーターをクラスタにデプロイします。

```bash
# 1. 最新のリリースバージョンのタグを取得して変数に格納
export VERSION=$(curl -s https://github.com/kubevirt/kubevirt/releases/latest | grep -o "v[0-9]*\.[0-9]*\.[0-9]*" | head -n 1)

# 2. KubeVirt Operatorのデプロイ
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml

```

*成功の確認:*
以下のコマンドで、オペレーターのポッドが起動していることを確認します。

```bash
kubectl get pods -n kubevirt -l app.kubernetes.io/component=operator

```

ステータスが `Running` になっていること。

---

## 2. KubeVirtカスタムリソース（CR）の作成

オペレーターが稼働したら、KubeVirt本体のカスタムリソース（CR）をデプロイします。これにより、実際のKubeVirtコンポーネントが展開されます。

```bash
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml

```

*成功の確認:*
以下のコマンドで、KubeVirtのリソースが有効になり、コンポーネントがデプロイされるのを待ちます。

```bash
kubectl wait -n kubevirt kv kubevirt --for condition=Available --timeout=300s

```

成功すると `kubevirt.kubevirt.io/kubevirt condition met` と表示されます。

---

## 3. インストールの検証

すべての主要なコンポーネントが正常に稼働しているか確認します。

```bash
kubectl get kubevirt -n kubevirt
kubectl get pods -n kubevirt

```

*成功の確認:*

* `kubevirt` リソースの `PHASE` が `Deployed` になっていること。
* `virt-api`, `virt-controller`, `virt-handler` などのポッドがすべて `Running` 状態であること。


## 参考文献
* [KubeVirt 公式ドキュメント](https://kubevirt.io/user-guide/cluster_admin/installation/#installing-kubevirt-on-kubernetes)