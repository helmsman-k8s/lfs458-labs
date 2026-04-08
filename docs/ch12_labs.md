# Chapter 12: Scheduling

**Working directory: `~/lfs458/ch12-scheduling/`**

---

## Exercise 12.1: Assign Pods Using Labels

The scheduler places Pods on nodes based on available resources. You can influence placement using `nodeSelector`, `nodeAffinity`, and `podAffinity` rules. In this exercise we use labels and `nodeSelector` to pin Pods to specific nodes.

```bash
cd ~/lfs458/ch12-scheduling/
```

**1.** Verify both nodes are `Ready` and note their current state.

```bash
kubectl get nodes
```

```
NAME     STATUS   ROLES           AGE   VERSION
controller       Ready    control-plane   44h   v1.34.1
worker1   Ready    <none>          43h   v1.34.1
```

**2.** View the current labels and taints on all nodes.

```bash
kubectl describe nodes | grep -A5 -i label
```

```
Labels:   beta.kubernetes.io/arch=amd64
          beta.kubernetes.io/os=linux
          kubernetes.io/arch=amd64
          kubernetes.io/hostname=controller
          kubernetes.io/os=linux
          node-role.kubernetes.io/control-plane=
--
Labels:   beta.kubernetes.io/arch=amd64
          beta.kubernetes.io/os=linux
          kubernetes.io/arch=amd64
          kubernetes.io/hostname=worker1
          kubernetes.io/os=linux
          system=secondOne
```

```bash
kubectl describe nodes | grep -i taint
```

```
Taints:   <none>
Taints:   <none>
```

**3.** Count how many containers are currently running on each node. Note the numbers — you will compare them after scheduling. Open a second terminal connected to the worker1 node.

```bash
sudo crictl ps | wc -l
```

```
24
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
21
```

**4.** Label the CP node as VIP hardware and the worker1 as other hardware.

```bash
kubectl label nodes controller status=vip
```

```
node/controller labeled
```

```bash
kubectl label nodes worker1 status=other
```

```
node/worker1 labeled
```

**5.** Verify the labels are set.

```bash
kubectl get nodes --show-labels
```

```
NAME     STATUS   ROLES           AGE   VERSION   LABELS
controller       Ready    control-plane   35h   v1.34.1   ...,status=vip
worker1   Ready    <none>          35h   v1.34.1   ...,status=other,system=secondOne
```

**6.** Review the pre-staged `vip.yaml` — a Pod with four busybox containers that sleep indefinitely, with a `nodeSelector` targeting `status=vip`.

```bash
cat ~/lfs458/ch12-scheduling/vip.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vip
spec:
  containers:
  - name: vip1
    image: busybox
    args:
    - sleep
    - "1000000"
  - name: vip2
    image: busybox
    args:
    - sleep
    - "1000000"
  - name: vip3
    image: busybox
    args:
    - sleep
    - "1000000"
  - name: vip4
    image: busybox
    args:
    - sleep
    - "1000000"
  nodeSelector:
    status: vip
```

**7.** Deploy the pod and verify the four containers land on the CP node.

```bash
kubectl create -f vip.yaml
```

```
pod/vip created
```

```bash
sudo crictl ps | wc -l
```

```
28   # Four more than before (controller)
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
21   # Unchanged — no new containers on worker1
```

**8.** Delete the pod and comment out the `nodeSelector` lines in `vip.yaml`.

```bash
kubectl delete pod vip
vim vip.yaml
```

```yaml
....
  # nodeSelector:
  #   status: vip
```

**9.** Recreate the pod. Without a `nodeSelector` containers can now land on either node.

```bash
kubectl create -f vip.yaml
```

```
pod/vip created
```

**10.** Check the container counts on both nodes. They should now be more evenly spread.

```bash
sudo crictl ps | wc -l
```

```
24
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
25
```

**11.** Create an `other.yaml` for non-VIP pods by copying `vip.yaml`, substituting names, and uncommenting the `nodeSelector` with `status=other`.

```bash
cp vip.yaml other.yaml
sed -i 's/vip/other/g' other.yaml
vim other.yaml
```

```yaml
....
  nodeSelector:
    status: other    #<-- Uncomment and set to other
```

**12.** Create the other pod and verify containers land on the worker1 node.

```bash
kubectl create -f other.yaml
```

```
pod/other created
```

```bash
sudo crictl ps | wc -l
```

```
24    # controller unchanged
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
25    # worker1 increased
```

**13.** Clean up both pods.

```bash
kubectl delete pods vip other
kubectl get pods
```

---

## Exercise 12.2: Using Taints to Control Pod Deployment

**Taints** repel Pods from nodes. Only Pods with a matching **toleration** can be scheduled on a tainted node. There are three taint effects:

- `NoSchedule` — do not schedule new Pods here (existing Pods unaffected)
- `PreferNoSchedule` — avoid this node if possible, but will use it if needed
- `NoExecute` — evict existing Pods and stop scheduling new ones here

**1.** Review the pre-staged `taint.yaml` — a Deployment of 8 nginx replicas.

```bash
cat ~/lfs458/ch12-scheduling/taint.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: taint-deployment
spec:
  replicas: 8
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name:  nginx
        image: nginx:1.20.1
        ports:
        - containerPort: 80
```

**2.** Deploy it and note the container counts on both nodes. You should see roughly 3 on the CP and 5 on the worker1 (your numbers may differ).

```bash
kubectl apply -f taint.yaml
```

```
deployment.apps/taint-deployment created
```

```bash
sudo crictl ps | grep nginx
sudo crictl ps | wc -l
```

```
27    # controller
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
17    # worker1
```

**3.** Check the container grep output on the CP to confirm nginx pods are present, then check the worker1.

```bash
sudo crictl ps | grep nginx
```

**4.** Delete the deployment and confirm containers return to baseline.

```bash
kubectl delete deployment taint-deployment
sudo crictl ps | wc -l
```

```
21
```

---

### PreferNoSchedule taint

**5.** Taint the worker1 node with `PreferNoSchedule` — new pods will prefer to avoid it but can still land there if needed.

```bash
kubectl taint nodes worker1 \
  bubba=value:PreferNoSchedule
```

```
node/worker1 tainted
```

```bash
kubectl describe node | grep Taint
```

```
Taints:   bubba=value:PreferNoSchedule
Taints:   <none>
```

```bash
kubectl apply -f taint.yaml
```

```
deployment.apps/taint-deployment created
```

**6.** Check container distribution. More containers should land on the CP, but the worker1 still gets some since `PreferNoSchedule` is not absolute.

```bash
sudo crictl ps | wc -l
```

```
21    # controller (roughly same)
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
23    # worker1 still got some
```

Delete the deployment after recording the numbers.

```bash
kubectl delete deployment taint-deployment
```

---

### NoSchedule taint

**7.** Remove the previous taint and replace it with `NoSchedule`. New containers will not be scheduled on the worker1 at all (DaemonSet pods are exempt).

```bash
kubectl taint nodes worker1 bubba-
```

```
node/worker1 untainted
```

```bash
kubectl taint nodes worker1 \
  bubba=value:NoSchedule
```

```
node/worker1 tainted
```

```bash
kubectl apply -f taint.yaml
```

```
deployment.apps/taint-deployment created
```

```bash
sudo crictl ps | wc -l
```

```
21    # controller
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
23    # worker1: no new nginx containers, only daemonset pods
```

**8.** Verify no new nginx containers are on the worker1.

```bash
sudo crictl ps | grep nginx
```

**9.** Remove the `NoSchedule` taint and delete the deployment. Without any taint containers spread across both nodes again.

```bash
kubectl delete deployment taint-deployment
kubectl taint nodes worker1 bubba-
```

```
node/worker1 untainted
```

```bash
kubectl apply -f taint.yaml
kubectl describe node | grep Taint
```

```
Taints:   <none>
Taints:   <none>
```

```bash
sudo crictl ps | wc -l
```

```
27    # controller - more containers spread across both
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
17
```

---

### NoExecute taint

**10.** Apply `NoExecute` to the worker1 node. This will evict existing Pods from the worker1 and prevent new scheduling.

```bash
kubectl taint nodes worker1 \
  bubba=value:NoExecute
```

```
node "worker1" tainted
```

```bash
sudo crictl ps | wc -l
```

```
37    # controller: pods evacuated from worker1 land here
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
5     # worker1: only essential daemonset containers remain
```

**11.** Remove the `NoExecute` taint. Note that containers do NOT automatically return to the worker1 — they stay on the CP where they were rescheduled.

```bash
kubectl taint nodes worker1 bubba-
```

```
node/worker1 untainted
```

```bash
sudo crictl ps | wc -l
```

```
32    # controller still has extra containers
```

On the **worker1 node**:

```bash
sudo crictl ps | wc -l
```

```
6     # worker1 still low — containers don't migrate back
```

**12.** Remove the deployment to free cluster resources.

```bash
kubectl delete deployment taint-deployment
```

```
deployment.apps "taint-deployment" deleted
```

---
