terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
  }
}

# ローカル KVM への接続設定
provider "libvirt" {
  uri = "qemu:///system"
}