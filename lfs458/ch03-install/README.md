# Chapter 3 — Installation and Configuration

## Exercises
- 3.1 Prepare All Nodes (kernel modules, sysctl, swap)
- 3.2 Install containerd
- 3.3 Install Kubernetes Packages (kubeadm, kubelet, kubectl)
- 3.4 Initialise the Control Plane (kubeadm init)
- 3.5 Install Calico CNI
- 3.6 Join Worker Nodes
- 3.7 Test the Cluster

## Pre-staged files

| File | Purpose |
|------|---------|
| `kubeadm-config.yaml` | Used during `kubeadm init` — sets pod CIDR to 10.244.0.0/16 |
| `cni.yaml` | Reference file — see Lab 3.5 for the actual install command |
| `calico-custom-resources.yaml` | Calico IPPool configured for 10.244.0.0/16 (applied after the Tigera Operator) |

## Notes
- Pod CIDR: `10.244.0.0/16` (matches Calico IPPool in calico-custom-resources.yaml)
- Control plane endpoint: `controller:6443`
- CNI: Calico v3.29.1 (Tigera Operator install method)
- Do **not** use the Calico default 192.168.0.0/16 CIDR — it overlaps with the node network 192.168.2.x
