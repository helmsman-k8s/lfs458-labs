# LFS458 — Kubernetes Administration Lab Guide

Welcome to the **Vega Training** lab guide for the LFS458 Kubernetes Administration course.

---

## Lab Topology

Each student environment consists of **three VMs** on a shared `/24` network. The hostnames are fixed; only the IP addresses differ per student.

| Role | Hostname | IP Address |
|------|----------|------------|
| Control Plane | `controller` | *assigned by your instructor* |
| Worker 1 | `worker1` | *assigned by your instructor* |
| Worker 2 | `worker2` | *assigned by your instructor* |

!!! tip "Finding your IPs"
    Run `ip addr show` on each node to find its IP. Use `/etc/hosts` to map hostnames so you can `ssh controller`, `ssh worker1`, etc. without remembering IPs:
    ```
    <controller-ip>   controller
    <worker1-ip>      worker1
    <worker2-ip>      worker2
    ```

---

## Lab Environment

| Component | Version |
|-----------|---------|
| OS | Ubuntu 22.04 LTS |
| Kubernetes | 1.33.1 |
| Container Runtime | containerd |
| CNI | Calico (pod CIDR: 10.244.0.0/16) |
| CRI Socket | `/run/containerd/containerd.sock` |

---

## Quick Reference

### Kubectl Tips

```bash
# Get all resources in all namespaces
kubectl get all -A

# Watch pods in real time
kubectl get pods -w

# Describe a resource for event/error detail
kubectl describe pod <pod-name>

# Execute a command in a running container
kubectl exec -it <pod-name> -- bash

# Extract a field with jsonpath (use instead of copy-pasting names)
POD=$(kubectl get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
echo "Pod name: $POD"
```

### Shell Variable Patterns

Throughout these labs, use shell variables to capture dynamic values instead of copy-pasting names or IPs. This makes every command reproducible regardless of your specific environment:

```bash
# Capture a pod name
POD=$(kubectl get pod -l app=<label> -o jsonpath='{.items[0].metadata.name}')

# Capture a service ClusterIP
SVC_IP=$(kubectl get svc <svc-name> -o jsonpath='{.spec.clusterIP}')

# Capture a NodePort
NODE_PORT=$(kubectl get svc <svc-name> -o jsonpath='{.spec.ports[0].nodePort}')

# Capture an endpoint IP
ENDPOINT_IP=$(kubectl get endpoints <svc-name> -o jsonpath='{.subsets[0].addresses[0].ip}')
```

---

## Lab Files

All YAML manifests are in subdirectories under `lfs458/` in the repository root, organized by chapter. Each chapter that requires editing a manifest also has a `solutions/` subfolder with the completed version.

```
lfs458/
├── ch03-install/
├── ch04-architecture/
│   └── solutions/
├── ch06-api-objects/
│   └── solutions/
├── ch07-deployments/
│   └── solutions/
├── ch09-volumes/
│   └── solutions/
├── ch10-services/
│   └── solutions/
├── ch15-security/
│   └── solutions/
└── ...
```
