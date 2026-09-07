# Chapter 3 — Installation and Configuration

## Exercises
- 3.1 Install Kubernetes (prepare nodes, containerd, kubeadm init, Calico)
- 3.2 Grow the Cluster (join worker nodes)
- 3.3 Finish Cluster Setup (remove taint, label workers)
- 3.4 Deploy A Simple Application
- 3.5 Access from Outside the Cluster

## Pre-staged files

| File | Purpose |
|------|---------|
| `kubeadm-config.yaml` | Used during `kubeadm init` — sets pod CIDR to 10.244.0.0/16 |
| `calico-custom-resources.yaml` | Calico IPPool configured for 10.244.0.0/16 (applied after the Tigera Operator) |

## Notes
- Kubernetes: 1.36.1 (upgraded to 1.36.2 in Chapter 4)
- Pod CIDR: `10.244.0.0/16` (matches Calico IPPool in calico-custom-resources.yaml)
- Control plane endpoint: `controller:6443`
- CNI: Calico v3.32.1 (Tigera Operator install method)
- From v3.32 the `projectcalico.org` CRDs install from a separate manifest **before** the operator — see Exercise 3.1 step 18
- Do **not** use the Calico default 192.168.0.0/16 CIDR — it overlaps with the node network 192.168.2.x
