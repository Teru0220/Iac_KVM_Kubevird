# KubeVirt ホスト準備ガイド

このガイドでは、本環境でKubeVirtをスムーズに稼働させるために必要なホストレベルの前提条件についてまとめます。
別環境で必要なチェックがことなると思われるので公式を確認してください

---

## 1. 仮想化支援機能の検証と権限設定 (`virt-host-validate`)

KubeVirtをデプロイする前に、ホストマシンがハードウェア支援による仮想化（Intel VT-x または AMD-V）をサポートしており、必要なデバイスファイルにアクセス可能であることを確認します。

### 実行手順
QEMU/KVM向けにバリデーションツールを実行します：
```bash
virt-host-validate qemu
```

### 期待される結果
* すべての主要なチェック項目が `PASS` を返すこと。
* `/dev/kvm` に関する `FAIL` や権限の警告が表示された場合は、以下の手順で権限を修正します。

### `/dev/kvm` 権限の修正（必要な場合）
ユーザーアカウントやコンテナランタイムが `/dev/kvm` へのアクセス権を持たない場合は、パーミッションとグループ所属を調整します：

```bash
# /dev/kvm の現在のパーミッションとグループを確認
ls -l /dev/kvm

# 現在のユーザーを kvm グループに追加し、権限を調整
sudo usermod -aG kvm $USER
sudo chmod 660 /dev/kvm
```
*確認:* 再度 `virt-host-validate qemu` を実行し、`/dev/kvm` のチェックが `PASS` に変わることを確認します。

---

## 2. AppArmor のステータス確認と無効化（テアダウン）

Ubuntuベースのホストでは、AppArmorがデフォルトで有効になっています。厳格なセキュリティプロファイルがQEMU、libvirt、またはKubeVirtのランチャーポッドに干渉し、起動失敗を引き起こすことがあります。

### 実行手順

1. **現在のAppArmorステータスとロードされているプロファイルの確認：**
   ```bash
   sudo aa-status
   ```

2. **プロファイルの強制アンロードとAppArmorの完全停止：**
   仮想化ワークロードにおける競合を防ぐため、`aa-teardown` を使用してプロファイルをアンロードし、サービスを無効化します：
   ```bash
   # すべてのAppArmorプロファイルを強制アンロード
   sudo aa-teardown

   # AppArmorサービスの停止と自動起動の無効化
   sudo systemctl stop apparmor
   sudo systemctl disable apparmor
   ```

3. **停止の確認：**
   ```bash
   sudo systemctl status apparmor
   ```
   *確認:* ステータスが `inactive (dead)` になっていることを確認します。

---

## 参考文献

* [Server World - Ubuntu 22.04 AppArmor 設定ガイド](https://www.server-world.info/query?os=Ubuntu_22.04&p=apparmor&f=1)
* [KubeVirt 公式ドキュメント - 前提条件チェック](https://kubevirt.io/)