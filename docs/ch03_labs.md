# Chapter 3: Installation and Configuration

**Working directory: `~/lfs458/ch03-install/`**

---

## Exercise 3.1: Install Kubernetes

> **Run all steps on the CONTROL PLANE node (`controller`) unless stated otherwise.**

---

### Step 1 — Prepare the system

**1.** Update the system.

```bash
sudo apt-get update && sudo apt-get upgrade -y
```

**2.** Install required packages.

```bash
sudo apt-get install -y apt-transport-https ca-certificates curl socat tree bash-completion
```

**3.** Disable swap permanently.

```bash
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
```

Verify:

```bash
free -h | grep Swap
```

```
Swap:          0B         0B         0B
```

**4.** Load required kernel modules.

```bash
sudo modprobe overlay
sudo modprobe br_netfilter
```

Make them persist across reboots:

```bash
cat << EOF | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF
```

**5.** Configure kernel networking.

```bash
cat << EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
```

```bash
sudo sysctl --system
```

**6.** Reboot so swap stays off and modules load cleanly.

```bash
sudo reboot
```

> Reconnect via SSH after ~30 seconds, then continue.

---

### Step 2 — Install containerd

**7.** Add the Docker repository (containerd is distributed here).

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

**8.** Install containerd.

```bash
sudo apt-get update && sudo apt-get install -y containerd.io
```

**9.** Configure containerd to use systemd as the cgroup driver.

```bash
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

Verify it is running:

```bash
sudo systemctl status containerd --no-pager
```

---

### Step 3 — Install Kubernetes components

**10.** Add the Kubernetes repository.

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

**11.** Install kubeadm, kubelet and kubectl at a fixed version.

```bash
sudo apt-get update
sudo apt-get install -y kubeadm=1.33.1-1.1 kubelet=1.33.1-1.1 kubectl=1.33.1-1.1
sudo apt-mark hold kubelet kubeadm kubectl
```

**12.** Configure crictl to use containerd.

```bash
sudo crictl config \
  --set runtime-endpoint=unix:///run/containerd/containerd.sock \
  --set image-endpoint=unix:///run/containerd/containerd.sock
```

---

### Step 4 — Initialise the cluster

**13.** Review the kubeadm config file.

```bash
cat ~/lfs458/ch03-install/kubeadm-config.yaml
```

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: 1.33.1
controlPlaneEndpoint: "controller:6443"
networking:
  podSubnet: 10.244.0.0/16
```

**14.** Initialise the cluster. This takes 2–3 minutes.

```bash
sudo cp ~/lfs458/ch03-install/kubeadm-config.yaml /root/
sudo kubeadm init --config=/root/kubeadm-config.yaml \
  --upload-certs --node-name=controller \
  | sudo tee /root/kubeadm-init.out
```

> **Save the `kubeadm join` command** printed at the end — you need it in Exercise 3.2. If the token expires (2 hours) regenerate it with:
> ```bash
> sudo kubeadm token create --print-join-command
> ```

**15.** Set up kubectl access.

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**16.** Enable kubectl bash completion.

```bash
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> $HOME/.bashrc
```

---

### Step 5 — Install the network plugin (Flannel)

**17.** Apply the Flannel CNI manifest. This is pre-staged in your lab folder.

```bash
kubectl apply -f ~/lfs458/ch03-install/cni.yaml
```

```
namespace/kube-flannel created
serviceaccount/flannel created
clusterrole.rbac.authorization.k8s.io/flannel created
clusterrolebinding.rbac.authorization.k8s.io/flannel created
configmap/kube-flannel-cfg created
daemonset.apps/kube-flannel-ds created
```

**18.** Wait for the node to become Ready. This takes about 1 minute.

```bash
kubectl get nodes -w
```

```
NAME         STATUS   ROLES           AGE   VERSION
controller   Ready    control-plane   2m    v1.33.1
```

Press `Ctrl+C` when the node shows `Ready`.

---

## Exercise 3.2: Grow the Cluster

> Open a **new terminal** and SSH into each worker node. Run steps 1–5 on **each worker** (`worker1` then `worker2`).

**1.** Prepare the system — same as the controller.

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y apt-transport-https ca-certificates curl socat tree bash-completion
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
sudo modprobe overlay
sudo modprobe br_netfilter
cat << EOF | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF
cat << EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
```

**2.** Install containerd.

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update && sudo apt-get install -y containerd.io
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

**3.** Install Kubernetes components.

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubeadm=1.33.1-1.1 kubelet=1.33.1-1.1 kubectl=1.33.1-1.1
sudo apt-mark hold kubelet kubeadm kubectl
```

**4.** Configure crictl.

```bash
sudo crictl config \
  --set runtime-endpoint=unix:///run/containerd/containerd.sock \
  --set image-endpoint=unix:///run/containerd/containerd.sock
```

**5.** Join the cluster. On the **controller node** first get the join command:

```bash
sudo kubeadm token create --print-join-command
```

Then run the output on the **worker node**, adding the correct `--node-name`:

```bash
# On worker1:
sudo kubeadm join controller:6443 --token <your-token> \
  --discovery-token-ca-cert-hash sha256:<your-hash> \
  --node-name=worker1

# On worker2:
sudo kubeadm join controller:6443 --token <your-token> \
  --discovery-token-ca-cert-hash sha256:<your-hash> \
  --node-name=worker2
```

```
This node has joined the cluster.
```

---

## Exercise 3.3: Finish Cluster Setup

**1.** Back on the **controller node**, verify all nodes have joined.

```bash
kubectl get nodes
```

```
NAME         STATUS   ROLES           AGE   VERSION
controller   Ready    control-plane   10m   v1.33.1
worker1      Ready    <none>          2m    v1.33.1
worker2      Ready    <none>          1m    v1.33.1
```

**2.** Remove the taint from the controller so it can run workloads during training.

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

```
node/controller untainted
error: taint "node-role.kubernetes.io/control-plane" not found   # normal for workers
```


```bash
kubectl label node worker1 node-role.kubernetes.io/worker=worker
kubectl label node worker2 node-role.kubernetes.io/worker=worker
```

**3.** Verify all system pods are running.

```bash
kubectl get pods --all-namespaces
```

All pods should show `Running`. If any are stuck in `Pending` wait another minute and try again.

---

## Exercise 3.4: Deploy A Simple Application

**1.** Create an nginx deployment.

```bash
kubectl create deployment nginx --image=nginx
kubectl get deployments
```

```
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
nginx   1/1     1            1           8s
```

**2.** Expose it as a LoadBalancer service.

```bash
kubectl expose deployment nginx --type=LoadBalancer --port=80
kubectl get svc nginx
```

```
NAME    TYPE           CLUSTER-IP   EXTERNAL-IP    PORT(S)        AGE
nginx   LoadBalancer   10.x.x.x     192.168.2.x    80:xxxxx/TCP   6s
```

**3.** Open a browser and navigate to the `EXTERNAL-IP`. You should see the nginx welcome page.

**4.** Scale the deployment.

```bash
kubectl scale deployment nginx --replicas=3
kubectl get pods -o wide
```

**5.** Clean up.

```bash
kubectl delete deployment nginx
kubectl delete svc nginx
```

---

## Exercise 3.5: Access from Outside the Cluster

**1.** Use `exec` to inspect environment variables inside a running pod.

```bash
kubectl run testpod --image=nginx
kubectl exec testpod -- printenv | grep KUBERNETES
```

```
KUBERNETES_SERVICE_PORT=443
KUBERNETES_SERVICE_HOST=10.96.0.1
```

**2.** Clean up.

```bash
kubectl delete pod testpod
```

---
