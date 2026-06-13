# Chapter 4: Kubernetes Architecture

## Overview

In this lab you will:

- Back up and restore the etcd database
- Upgrade the Kubernetes cluster from 1.33 to 1.34
- Set resource requests and limits on a pod
- Configure a LimitRange to enforce default limits on a namespace

---

## Lab 4.1 — etcd Backup and Restore

### Backup etcd (controller only)

Find the etcd pod and inspect its configuration:

```bash
ETCD_POD=$(kubectl get pod -n kube-system -l component=etcd \
  -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $ETCD_POD -n kube-system | grep -E "listen-client|cert-file|key-file|trusted-ca"
```

Install `etcdctl`:

```bash
sudo apt-get install -y etcd-client
```

Take a snapshot:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /var/lib/etcd/snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

Verify the snapshot:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot status /var/lib/etcd/snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table
```

### Restore etcd

To restore, stop the API server, restore the data directory, then restart:

```bash
# Move the API server manifest to temporarily stop the pod
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/

# Restore snapshot to a new data directory
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd/snapshot.db \
  --data-dir=/var/lib/etcd-restore \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Point etcd to the restored directory (edit the etcd static pod manifest)
sudo sed -i 's|/var/lib/etcd|/var/lib/etcd-restore|g' /etc/kubernetes/manifests/etcd.yaml

# Restore the API server
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# Wait for the cluster to recover
kubectl get nodes
```

!!! warning
    In production, a full restore requires additional care (member peer URLs, cluster state). This exercise demonstrates the mechanics; the LFS458 course book covers production restore procedures in detail.

---

## Lab 4.2 — Cluster Upgrade (1.33 → 1.34)

### Upgrade the control plane (controller only)

Check available versions:

```bash
sudo apt-get update
apt-cache madison kubeadm | head -5
```

Upgrade `kubeadm`:

```bash
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.34.0-*
sudo apt-mark hold kubeadm
```

Plan the upgrade:

```bash
sudo kubeadm upgrade plan
```

Apply the upgrade:

```bash
sudo kubeadm upgrade apply v1.34.0
```

Drain the control plane node and upgrade kubelet:

```bash
kubectl drain controller --ignore-daemonsets --delete-emptydir-data

sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.34.0-* kubectl=1.34.0-*
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet

kubectl uncordon controller
kubectl get nodes
```

### Upgrade worker nodes (worker1 and worker2)

Run on each worker:

```bash
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.34.0-*
sudo apt-mark hold kubeadm

sudo kubeadm upgrade node
```

On the **controller**, drain the worker:

```bash
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data
```

Back on **worker1**:

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.34.0-* kubectl=1.34.0-*
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

On the **controller**, uncordon:

```bash
kubectl uncordon worker1
```

Repeat for `worker2`. Verify all nodes show `v1.34.0`:

```bash
kubectl get nodes
```

---

## Lab 4.3 — Resource Requests and Limits

### Deploy the hog pod

The `hog.yaml` manifest is a starting point — you will add resource constraints to it.

```bash
cp ~/lfs458/ch04-architecture/hog.yaml ~/hog.yaml
cat ~/hog.yaml
```

Edit the file to add `resources` with both `requests` and `limits`, and pass `--vm 1 --vm-bytes 100M` to the `stress` command. The solution is in `~/lfs458/ch04-architecture/solutions/hog-with-resources.yaml` if needed.

Apply it:

```bash
kubectl apply -f ~/hog.yaml
```

Watch the pod start:

```bash
kubectl get pods -w
```

Once running, view resource usage:

```bash
HOG_POD=$(kubectl get pod -l app=hog -o jsonpath='{.items[0].metadata.name}')
kubectl top pod $HOG_POD
kubectl logs $HOG_POD
```

Try creating a pod that exceeds the node's available memory — Kubernetes should schedule it only if resources are available, or leave it `Pending`.

### Clean up

```bash
kubectl delete -f ~/hog.yaml
```

---

## Lab 4.4 — LimitRange

Create a LimitRange that sets default CPU and memory limits for new pods in a namespace:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: default
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "64Mi"
    max:
      cpu: "2"
      memory: "1Gi"
EOF
```

Verify:

```bash
kubectl describe limitrange default-limits
```

Deploy a pod without explicit resources and confirm it inherits the defaults:

```bash
kubectl run testlimit --image=nginx
TEST_POD=$(kubectl get pod testlimit -o jsonpath='{.metadata.name}')
kubectl get pod $TEST_POD -o jsonpath='{.spec.containers[0].resources}' | python3 -m json.tool
```

Clean up:

```bash
kubectl delete pod testlimit
kubectl delete limitrange default-limits
```
