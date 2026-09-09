Kubernetes クラスターの自動化を確実に行うため、まずは **「手動で構築する場合にどのような手順・コマンドを実行しているのか」** の全体像と仕組みを理解し、それを Ansible のタスクに落とし込んでいきましょう。

---
## 全体構成

```
ansible/
├── inventory.yaml             # Terraform から自動生成されるインベントリ
├── group_vars/
│   └── all.yml                # クラスター全体で使う共通変数
├── roles/
│   ├── common/
│   │   └── tasks/
│   │       └── main.yml       # [Phase 1] OS事前設定・Swap停止・Sysctl
│   ├── container_runtime/
│   │   └── tasks/
│   │       └── main.yml       # [Phase 2] containerd インストールとCgroup設定
│   ├── k8s_packages/
│   │   └── tasks/
│   │       └── main.yml       # [Phase 3] kubeadm / kubelet / kubectl 導入
│   ├── control_plane/
│   │   └── tasks/
│   │       └── main.yml       # [Phase 4] kubeadm init / CNI(Calico) / トークン取得
│   └── worker/
│       └── tasks/
│           └── main.yml       # [Phase 4] kubeadm join 実行
└── site.yml                   # 全ロールを呼び出すメイン Playbook
```


## 1. Kubernetes インストールの基本手順と仕組み

`kubeadm` を使用して Kubernetes クラスターを構築する場合、大きく分けて **4つのフェーズ** で処理を行います。

```
[ Phase 1: OS前提条件の設定 ]
  - Swapの無効化（kubeletの要求）
  - カーネルモジュールロード (overlay, br_netfilter)
  - ネットワークSysctl設定 (IP forwarding, bridge-nf-call-iptables)
       │
       ▼
[ Phase 2: コンテナランタイム (containerd) の導入 ]
  - containerd パッケージのインストール
  - 設定ファイル生成 & Cgroup ドライバを systemd に変更
       │
       ▼
[ Phase 3: Kubernetes 関連ツールのインストール ]
  - 公式 APT リポジトリ（pkgs.k8s.io）の鍵とソース追加
  - kubeadm / kubelet / kubectl のインストールとバージョン固定
       │
       ▼
[ Phase 4: クラスター初期化と参加 ]
  - [Control Plane] kubeadm init 実行 & CNI (Calico等) 適用
  - [Worker Node]   kubeadm join 実行

```

---

## 2. コマンド対比と Ansible コード化の解説

各フェーズで実行する Linux コマンドと、それを Ansible タスク (`.yml`) に変換する考え方を順番に解説します。

---

### Phase 1: OS前提条件の設定

Kubernetes (kubelet) は標準で Swap が有効だと起動しません。また、Pod 間の通信を Linux ブリッジ経由で正しくルーティングさせるためのカーネル設定が必要です。

#### 【Linux コマンド】

```bash
# Swap の停止と永続的無効化
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 必要モジュールのロード
sudo modprobe overlay
sudo modprobe br_netfilter

# ネットワークパラメータの適用
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

```

#### 【Ansible コード化 (`roles/common/tasks/main.yml`)】

`command` や `replace`, `sysctl` などの組み込みモジュールを使って安全・冪等（何回実行しても同じ状態を保つ）に記述します。

```yaml
- name: Swap を一時的に停止
  command: swapoff -a
  when: ansible_swaptotal_mb > 0

- name: /etc/fstab 内の Swap エントリをコメントアウト（再起動対策）
  replace:
    path: /etc/fstab
    regexp: '^([^#].*?\sswap\s+sw\s+.*)$'
    replace: '# \1'

- name: 必要なカーネルモジュールを設定ファイルに記述
  copy:
    dest: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

- name: カーネルモジュールをその場でロード
  modprobe:
    name: "{{ item }}"
    state: present
  loop:
    - overlay
    - br_netfilter

- name: ネットワーク用の sysctl パラメータを設定
  sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    state: present
    sysctl_file: /etc/sysctl.d/k8s.conf
    reload: yes
  loop:
    - { key: 'net.bridge.bridge-nf-call-iptables', value: '1' }
    - { key: 'net.bridge.bridge-nf-call-ip6tables', value: '1' }
    - { key: 'net.ipv4.ip_forward', value: '1' }

```

---

### Phase 2: コンテナランタイム (`containerd`) の導入

Pod を動かすための低レイヤーランタイムです。ポイントは **`SystemdCgroup = true`** の設定です。Kubernetes の `kubelet` と `containerd` で Cgroup の管理方式（systemd）を統一しないと動作が不安定になります。

#### 【Linux コマンド】

```bash
# containerd インストール
sudo apt-get update && sudo apt-get install -y containerd

# 設定ファイル生成と Cgroup 設定の変更
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# サービス再起動
sudo systemctl restart containerd

```

#### 【Ansible コード化 (`roles/container_runtime/tasks/main.yml`)】

```yaml
- name: 依存パッケージのインストール
  apt:
    name:
      - ca-certificates
      - curl
      - gnupg
    state: present
    update_cache: yes

- name: containerd のインストール
  apt:
    name: containerd
    state: present

- name: /etc/containerd ディレクトリの作成
  file:
    path: /etc/containerd
    state: directory
    mode: '0755'

- name: デフォルト設定の出力と SystemdCgroup の有効化
  shell: |
    containerd config default | tee /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

- name: containerd サービスの再起動と有効化
  systemd:
    name: containerd
    enabled: yes
    state: restarted

```

---

### Phase 3: Kubernetes パッケージのインストール

公式リポジトリ (`pkgs.k8s.io`) から最新の安定版パッケージを導入します。自動アップデートでバージョンがずれないよう `apt-mark hold` に相当する処理を行います。

#### 【Linux コマンド】

```bash
# APT GPG キーとリポジトリの追加 (例: v1.30)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# パッケージインストールとバージョン固定
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

```

#### 【Ansible コード化 (`roles/k8s_packages/tasks/main.yml`)】

```yaml
- name: GPG キー用ディレクトリの作成
  file:
    path: /etc/apt/keyrings
    state: directory
    mode: '0755'

- name: Kubernetes APT GPG キーの取得
  get_url:
    url: "https://pkgs.k8s.io/core:/stable:/v{{ k8s_version }}/deb/Release.key"
    dest: /etc/apt/keyrings/kubernetes-apt-keyring.asc
    mode: '0644'

- name: Kubernetes APT リポジトリの登録
  apt_repository:
    repo: "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.asc] https://pkgs.k8s.io/core:/stable:/v{{ k8s_version }}/deb/ /"
    state: present
    filename: kubernetes

- name: kubelet, kubeadm, kubectl のインストール
  apt:
    name:
      - kubelet
      - kubeadm
      - kubectl
    state: present
    update_cache: yes

- name: パッケージの自動更新を防止 (apt-mark hold)
  dpkg_selections:
    name: "{{ item }}"
    selection: hold
  loop:
    - kubelet
    - kubeadm
    - kubectl

```

---

Standard な Role 構成（`tasks/main.yml`）で進めていきます。

Phase 1〜3（OS前提条件・containerd・K8sパッケージ）で全ノードの下準備が完了したら、いよいよ **Phase 4「クラスター初期化と参加（`kubeadm init` / `join`）」** に入ります。

---

## Phase 4: クラスター初期化とノード参加の仕組み

Phase 4 は、以下の 2 つの役割に分かれます。

1. **Control Plane (`control_plane` ロール)**: `kubeadm init` でクラスターを生成し、ネットワークプラグイン（CNI）をデプロイして、参加用の**トークン**を発行する。
2. **Worker Node (`worker` ロール)**: 発行されたトークン（`kubeadm join ...`）を使ってクラスターに参加する。

```
[ control-plane-01 ]                                [ worker-node-01 / 02 ]
         │                                                     │
 1. kubeadm init 実行                                           │
         │                                                     │
 2. kubectl 設定 (admin.conf)                                   │
         │                                                     │
 3. CNI (Calico) デプロイ                                       │
         │                                                     │
 4. Join トークン生成 ───────────(Ansible 変数で共有)───────────► 5. kubeadm join 実行

```

---

## 1. 手動コマンドと Ansible コードの対比解説

---

### Step 1: Control Plane の初期化 (`roles/control_plane/tasks/main.yml`)

#### 【手動 Linux コマンド】

```bash
# クラスターの初期化 (Pod用ネットワーク範囲を指定)
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=192.168.122.28

# 一般ユーザー (ubuntu) で kubectl コマンドを使えるように設定
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Pod 間通信ネットワーク (Calico CNI) の導入
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# Worker 参加用コマンド（トークン付き）の取得
kubeadm token create --print-join-command

```

#### 【Ansible コード化】

ポイントは **「`kubeadm init` を二重実行しない（冪等性の確保）」** と **「取得した Join コマンドを全ノードで共有できる変数に代入する」** 点です。

```yaml
- name: kubeadm init の実行
  shell: |
    kubeadm init --pod-network-cidr={{ pod_network_cidr }} --apiserver-advertise-address={{ ansible_host }}
  args:
    creates: /etc/kubernetes/admin.conf  # このファイルが既に存在する場合はスキップする (冪等性)

- name: .kube ディレクトリの作成
  file:
    path: "/home/{{ ansible_user }}/.kube"
    state: directory
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0755'

- name: admin.conf を ubuntu ユーザーの kubeconfig としてコピー
  copy:
    src: /etc/kubernetes/admin.conf
    dest: "/home/{{ ansible_user }}/.kube/config"
    remote_src: yes
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0600'

- name: CNI (Calico) のマニフェストを適用
  become_user: "{{ ansible_user }}"
  command: kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

- name: Worker 参加用の Join コマンドを取得
  command: kubeadm token create --print-join-command
  register: join_command_raw

- name: Join コマンドを k8s_cluster 全体のファクト（変数）として保存
  set_fact:
    join_command: "{{ join_command_raw.stdout }}"
  delegate_to: "{{ item }}"
  delegate_facts: true
  loop: "{{ groups['k8s_cluster'] }}"

```

> **解説 (`set_fact` & `delegate_to`)**:
> `kubeadm token create` で取得した文字列（例: `kubeadm join 192.168.122.28:6443 --token ...`）は、そのままでは `control-plane-01` のローカル変数です。これを `delegate_to` を使って `worker-node` 側からも参照できるグローバルな変数として登録しています。

---

### Step 2: Worker ノードの参加 (`roles/worker/tasks/main.yml`)

#### 【手動 Linux コマンド】

```bash
# Control Plane で生成されたトークンコマンドを実行
sudo kubeadm join 192.168.122.28:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

```

#### 【Ansible コード化】

Worker ノード側では、Control Plane 側で生成されて共有された `join_command` 変数を実行するだけです。

```yaml
- name: Worker ノードをクラスターに参加させる
  shell: "{{ join_command }}"
  args:
    creates: /etc/kubernetes/kubelet.conf  # 既に参加済み（kubelet.confが存在する）場合はスキップ

```

---

## 2. 実行用 Playbook (`site.yml`) の全体像

それぞれの Role をどのホストグループに適用するかを整理します。

```yaml
# 1. 全ノードに Phase 1 〜 Phase 3 を適用
- name: 全ノード共通セットアップ (Phase 1-3)
  hosts: k8s_cluster
  become: yes
  roles:
    - common
    - container_runtime
    - k8s_packages

# 2. Control Plane のみ Phase 4 (初期化) を適用
- name: Control Plane の初期化 (Phase 4)
  hosts: control_plane
  become: yes
  roles:
    - control_plane

# 3. Worker ノードのみ Phase 4 (参加) を適用
- name: Worker ノードのクラスター参加 (Phase 4)
  hosts: worker_node
  become: yes
  roles:
    - worker

```

---

## 実行と確認手順

これで全ロールの準備が整いました。以下の順序で作成・実行してみてください。

1. ディレクトリとファイルを配置します（`roles/common`, `roles/container_runtime`, `roles/k8s_packages`, `roles/control_plane`, `roles/worker`）。
2. Ansible Playbook を実行します：
```bash
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ./ansible/inventory.yaml ./ansible/site.yml

```


3. 完了後、`control-plane-01` に SSH ログインしてノード状態を確認します：
```bash
ssh ubuntu@192.168.122.28 "kubectl get nodes"

```


全ノード（`control-plane-01`, `worker-node-01`, `worker-node-02`）が **`Ready`** になっていればクラスター構築成功です！