
---

## 1. 前提条件のチェックリスト（全7項目）

| # | チェック項目 | 要件の概要 | 対象ノード（役割別） | 判定 |
| --- | --- | --- | --- | --- |
| **1** | **K8s クラスターの起動** | 正常に動作する Kubernetes または OpenShift | クラスター全体 | [ ] |
| **2** | **kubectl の準備** | API サーバーにアクセス可能な CLI | クラスター操作ノード | [ ] |
| **3** | **KVM デバイス (`/dev/kvm`)** | ハードウェア仮想化サポートとアクセス権限 | **すべてのノード**（特にワークロード実行ノード） | [ ] |
| **4** | **AppArmor / SELinux** | セキュリティモジュールによるアクセス制限の構成 | **すべてのノード** | [ ] |
| **5** | **CNI プラグイン** | ポッド間通信を提供するネットワーク機能 | **すべてのノード** | [ ] |
| **6** | **K8s バージョン互換性** | KubeVirt がサポートする K8s バージョン範囲 | クラスター全体 | [ ] |
| **7** | **リソース（CPU/メモリ）** | 管理機能および VM 動作用の十分な空きリソース | **すべてのノード** | [ ] |

---

## 2. 各要件の確認手順（全7項目）

1. **1. Kubernetes クラスターの動作確認:** 対象: クラスター操作を実行するノード.
クラスター内のすべてのノードが認識され、操作可能な状態か確認します。

```bash
kubectl get nodes

```

**判定基準:** すべてのノードの STATUS が **`Ready`** であること。


2. **2. kubectl コマンドの動作確認:** 対象: クラスター操作を実行するノード.
`kubectl` から API サーバーへ正常に通信できるか確認します。

```bash
kubectl cluster-info

```

**判定基準:** `Kubernetes control plane is running at...` と表示されること。


3. **3. ハードウェア仮想化 (KVM) の確認:** 対象: すべてのノード（ノードごとに直接確認）.
各ノードにログインし、QEMU/KVM アクセラレーションが利用可能か確認します。

```bash
virt-host-validate qemu

```

**判定基準:** `/dev/kvm is accessible` が **PASS** になっていること。


4. **4. AppArmor / SELinux 要件の確認:** 対象: すべてのノード（ノードごとに直接確認）.
セキュリティ機能が KubeVirt や KVM の動作をアクセス拒否（Permission denied）しない状態か確認します。

```bash
# Ubuntu（AppArmor）の場合
sudo aa-status

# RHEL系（SELinux）の場合
getenforce

```

**判定基準:** AppArmor が `enforce` モードであっても、`containerd` や `cri-o` の標準プロファイルで `/dev/kvm` へのアクセスがブロックされていないこと（拒否ログが出力されないこと）。


5. **5. ネットワーク (CNI) 要件の確認:** 対象: すべてのノード.
ポッド間通信を提供する CNI が正常稼働しているか確認します。

```bash
kubectl get pods -n kube-system

```

**判定基準:** 導入されている CNI（Calico, Flannel, Cilium 等）のポッドが `Running` 状態であること。


6. **6. K8s バージョン互換性の確認:** 対象: クラスター操作を実行するノード.
動作している Kubernetes のバージョンを確認します。

```bash
kubectl version

```

**判定基準:** KubeVirt がサポートする範囲内のバージョンであること。


7. **7. 必要リソース（CPU / メモリ）の確認:** 対象: すべてのノード.
KubeVirt システムコンポーネントおよび VM を動かすための空きリソースがあるか確認します。

```bash
kubectl describe nodes | grep -A 8 "Allocated resources"

```

**判定基準:** 各ノードに十分な空きリソース（推奨: 2 CPU / 4GB メモリ以上）があること。


---

チェックリスト項目と詳細手順が1対1（全7項目）で完全に対応するよう修正いたしました。ご指摘ありがとうございました。

---

### 要点まとめ

1. **KVM (`/dev/kvm`) への権限** と **AppArmor / SELinux によるブロックが発生しないこと** が、ノード側におけるOS層の重要な要件です。
2. コマンドでの状態確認（`kubectl get nodes` 等）は操作端末から行えますが、**`/dev/kvm` や AppArmor の確認はクラスター内のすべてのノードに個別にログインして確認**する必要があります。


## 公式サイト
https://kubevirt.io/user-guide/cluster_admin/installation/