# Chapter 3: Install Kubernetes

## Overview

In this lab you will build a three-node Kubernetes cluster from scratch using `kubeadm`. You will:

- Install the container runtime (containerd) on all nodes
- Install Kubernetes packages (`kubeadm`, `kubelet`, `kubectl`)
- Initialise the control plane with `kubeadm init`
- Install **Calico** as the CNI (pod CIDR `10.244.0.0/16`)
- Join both worker nodes to the cluster
- Deploy a test nginx workload

All steps marked **"All nodes"** must be run on `controller`, `worker1`, and `worker2` unless stated otherwise.

---

## Lab 3.1 — Prepare All Nodes

### Disable swap (All nodes)

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### Load required kernel modules (All nodes)

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### Configure sysctl (All nodes)

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

---

## Lab 3.2 — Install containerd (All nodes)

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io
```

Generate the default config and enable SystemdCgroup:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

---

## Lab 3.3 — Install Kubernetes Packages (All nodes)

```bash
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable kubelet
```

---

## Lab 3.4 — Initialise the Control Plane (controller only)

Copy the provided config file to the home directory:

```bash
cp ~/lfs458/ch03-install/kubeadm-config.yaml ~/kubeadm-config.yaml
```

Review it:

```bash
cat ~/kubeadm-config.yaml
```

The `podSubnet` is set to `10.244.0.0/16` to match the Calico CNI we will install.

Initialise the cluster:

```bash
sudo kubeadm init --config=kubeadm-config.yaml --upload-certs \
  | sudo tee /var/log/kubeadm-init.log
```

!!! note
    This will take 2–3 minutes. Save the `kubeadm join` command printed at the end — you will need it for the worker nodes.

Set up `kubectl` access for your user:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Verify the control plane is up (the node will be `NotReady` until the CNI is installed):

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

---

## Lab 3.5 — Install Calico CNI (controller only)

Install the Tigera Operator:

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml
```

Wait for the operator to be ready:

```bash
kubectl rollout status deployment tigera-operator -n tigera-operator --timeout=120s
```

Apply the custom resources to configure Calico with the `10.244.0.0/16` pod CIDR:

```bash
kubectl apply -f ~/lfs458/ch03-install/calico-custom-resources.yaml
```

Watch Calico come up:

```bash
watch kubectl get pods -n calico-system
```

Wait until all pods show `Running`. Then verify the node is `Ready`:

```bash
kubectl get nodes
```

---

## Lab 3.6 — Join Worker Nodes (worker1 and worker2)

From your `kubeadm init` output, copy the `kubeadm join` command and run it on each worker with `sudo`. It looks like:

```bash
sudo kubeadm join controller:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

!!! tip "Lost the join command?"
    Regenerate it on the controller:
    ```bash
    kubeadm token create --print-join-command
    ```

Back on the **controller**, verify all nodes joined:

```bash
kubectl get nodes -o wide
```

All three nodes should be `Ready` within a minute or two.

---

## Lab 3.7 — Test the Cluster

Deploy a simple nginx pod:

```bash
kubectl create deployment nginx --image=nginx
kubectl get pods -w
```

Wait until the pod shows `Running`, then:

```bash
POD=$(kubectl get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -- nginx -v
```

Expose it and test connectivity:

```bash
kubectl expose deployment nginx --port=80 --type=NodePort

NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort: $NODE_PORT"

curl http://controller:$NODE_PORT
```

You should see the nginx welcome page HTML.

Clean up:

```bash
kubectl delete deployment nginx
kubectl delete svc nginx
```
