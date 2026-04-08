# LFS458 - Kubernetes Administration Lab Guide

Welcome to the student lab guide for **LFS458 / CKA preparation**, delivered by **VEGA TRAINING & HADAR TRAINING**.

---

## How to use this guide

Each chapter corresponds to a section of the LFS458 course. Follow the exercises in order ? later chapters build on earlier ones.

Work on your assigned lab nodes:

| Node | Hostname | IP | Role |
|------|----------|----|------|
| Control Plane | `controller` | 192.168.2.32 | Kubernetes control plane |
| Worker 1 | `worker1` | 192.168.2.33 | Worker node |
| Worker 2 | `worker2` | 192.168.2.34 | Worker node |

Your username on all nodes is `guru` (password: `work`).

---

## Lab topology

| Component | Value |
|-----------|-------|
| Kubernetes version | **1.33.1** |
| Container runtime | **containerd** |
| CNI | **Flannel** (10.244.0.0/16) |
| OS | Ubuntu 22.04 |
| Control plane endpoint | `controller:6443` |

---

## Quick reference
```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check component logs
journalctl -u kubelet -f

# Lab files location
ls ~/lfs458/

# Switch context
kubectl config get-contexts
kubectl config use-context <name>
```

---

!!! tip "Lab files"
    All pre-staged YAML files for each chapter are in `~/lfs458/chXX-*/`.
    Simulation test scripts are in `~/chXX_sim.sh`.

!!! warning "Node names"
    This guide uses `controller`, `worker1`, `worker2` ? not the generic `cp`/`worker` names used in the upstream LFS458 material.

---

*HADAR TRAINING © 2025 - Validated on Kubernetes 1.33.1, April 2026*
