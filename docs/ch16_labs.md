# Chapter 16: High Availability

## Overview

In this lab you will:

- Set up HAProxy as a load balancer in front of multiple control plane nodes
- Join a second control plane node to the cluster
- Test etcd leader election
- Simulate a control plane failure and verify workloads continue running

!!! note "Lab topology"
    This chapter assumes you have access to an additional VM for a second control plane node. If not, you can still follow the HAProxy and etcd sections on the existing 3-node cluster.

---

## Lab 16.1 — HAProxy Load Balancer

HAProxy will distribute API server traffic across all control plane nodes on port 6443.

> **Note:** HAProxy must run on a **dedicated load balancer node** — it cannot run on the controller itself. Both HAProxy and `kube-apiserver` bind to port 6443, so they cannot coexist on the same host. This lab requires a 4th VM. In a standard 3-node training environment this lab is demonstrated by the instructor rather than executed by students.

### Install HAProxy (dedicated LB node required)

```bash
sudo apt-get install -y haproxy
```

### Configure HAProxy

Replace `/etc/haproxy/haproxy.cfg` with:

```bash
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend kubernetes-api
    bind *:6443
    mode tcp
    default_backend kubernetes-masters

backend kubernetes-masters
    mode tcp
    balance roundrobin
    option tcp-check
    server controller controller:6443 check
    # Add additional control plane nodes here:
    # server controller2 controller2:6443 check
EOF

sudo systemctl restart haproxy
sudo systemctl enable haproxy
sudo systemctl status haproxy
```

Verify HAProxy is listening:

```bash
ss -tlnp | grep 6443
```

---

## Lab 16.2 — Add a Second Control Plane Node

On the **controller**, generate a new join command with the `--control-plane` flag:

```bash
# Generate a new certificate key
CERT_KEY=$(kubeadm certs certificate-key)
echo "Certificate key: $CERT_KEY"

# Upload certs
sudo kubeadm init phase upload-certs --upload-certs --certificate-key $CERT_KEY

# Generate the join command
kubeadm token create --print-join-command --certificate-key $CERT_KEY
```

On the **second control plane node** (e.g., `controller2`), run the join command with `--control-plane`:

```bash
sudo kubeadm join <load-balancer-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key>
```

Set up kubectl on the new node:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Back on the **original controller**, verify:

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep etcd
```

You should now see two etcd pods and two `controller` nodes.

---

## Lab 16.3 — etcd Leader Election

Inspect the etcd cluster members:

```bash
ETCD_POD=$(kubectl get pod -n kube-system -l component=etcd \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec $ETCD_POD -n kube-system -- \
  etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table
```

Identify the leader:

```bash
kubectl exec $ETCD_POD -n kube-system -- \
  etcdctl endpoint status \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table
```

The `IS LEADER` column shows the current etcd leader.

---

## Lab 16.4 — Control Plane Failover Test

This test shows that workloads continue running even if the primary control plane is unavailable.

### Deploy a workload

```bash
kubectl create deployment failover-test --image=nginx --replicas=4
kubectl get pods -l app=failover-test -o wide
```

### Simulate a control plane failure

Stop the kubelet on the primary controller:

```bash
# On the controller node:
sudo systemctl stop kubelet
```

From another machine (or `controller2`), verify the workload still runs:

```bash
kubectl get pods -l app=failover-test -o wide
kubectl get nodes
```

The pods should still be `Running`. The `controller` node will show `NotReady` after the node lease expires (~40 seconds).

### Restore the controller

```bash
# On the controller node:
sudo systemctl start kubelet
```

Verify it rejoins:

```bash
kubectl get nodes -w
```

### Clean up

```bash
kubectl delete deployment failover-test
```

---

## Lab 16.5 — kube-vip (Optional)

For a production-grade virtual IP (VIP) approach instead of HAProxy, `kube-vip` provides a Layer 2 VIP for the control plane endpoint. It runs as a DaemonSet on control plane nodes and elects a leader that holds the VIP.

```bash
# Generate kube-vip manifest (example — adjust VIP and interface to your environment)
VIP=<your-vip-address>
IFACE=eth0

kubectl apply -f https://kube-vip.io/manifests/rbac.yaml

docker run --rm ghcr.io/kube-vip/kube-vip:latest manifest daemonset \
  --interface $IFACE \
  --address $VIP \
  --inCluster \
  --taint \
  --controlplane \
  --services \
  --arp \
  --leaderElection | kubectl apply -f -
```

This is advanced and environment-specific — refer to the kube-vip documentation for your network setup.
