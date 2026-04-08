# Chapter 4: Kubernetes Architecture

**Working directory: `~/lfs458/ch04-architecture/`**

---

## Exercise 4.1: Basic Node Maintenance

In this exercise we will back up the **etcd** database and then upgrade the version of Kubernetes on the control plane and worker nodes.

```bash
cd ~/lfs458/ch04-architecture/
```

---

### Backup the etcd Database

**1.** Find the data directory of the **etcd** daemon. All settings for the pod can be found in its manifest.

```bash
sudo grep data-dir /etc/kubernetes/manifests/etcd.yaml
```

```
  - --data-dir=/var/lib/etcd
```

**2.** Log into the etcd container to explore the **etcdctl** options. Use Tab to complete the container name — it has the node name appended to it.

```bash
kubectl -n kube-system exec -it etcd-controller -- sh
```

> The following sub-steps (a), (b), (c) run **inside the etcd container shell**.

**(a)** View the arguments and options available to `etcdctl`.

```bash
etcdctl -h
```

```
NAME:
        etcdctl - A simple command line client for etcd3.

USAGE:
        etcdctl [flags]
<output_omitted>
```

**(b)** Find the TLS certificate files needed to authenticate with etcd. Newer etcd images are minimised so `find` and `ls` may not be available — use `echo` instead.

```bash
cd /etc/kubernetes/pki/etcd
echo *
```

```
ca.crt ca.key healthcheck-client.crt healthcheck-client.key
peer.crt peer.key server.crt server.key
```

**(c)** Exit the container shell.

```bash
exit
```

**3.** Check the health of the etcd database using the loopback IP and port 2379. Pass the peer cert, key, and CA as environment variables. You do not need to type out the comments or backslashes.

```bash
kubectl -n kube-system exec -it etcd-controller -- sh \
  -c "ETCDCTL_API=3 \
  ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
  ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \
  ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
  etcdctl endpoint health"
```

```
https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 11.942936ms
```

**4.** Determine how many databases are part of the cluster. Three or five members are common in production for 50%+1 quorum. In our single-node exercise environment you will only see one.

```bash
kubectl -n kube-system exec -it etcd-controller -- sh \
  -c "ETCDCTL_API=3 \
  ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
  ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \
  ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
  etcdctl --endpoints=https://127.0.0.1:2379 member list"
```

```
fb50b7ddbf4930ba, started, controller, https://192.168.2.x:2380,
https://192.168.2.x:2379, false
```

**5.** View the member list in table format using the `-w table` option.

```bash
kubectl -n kube-system exec -it etcd-controller -- sh \
  -c "ETCDCTL_API=3 \
  ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
  ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \
  ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
  etcdctl --endpoints=https://127.0.0.1:2379 member list -w table"
```

```
+------------------+---------+------+---------------------------+---------------------------+---------+
|        ID        | STATUS  | NAME |        PEER ADDRS         |       CLIENT ADDRS        | LEARNER |
+------------------+---------+------+---------------------------+---------------------------+---------+
| 802d78549985d5a8 | started | controller | https://192.168.2.x:2380  | https://192.168.2.x:2379  | false   |
+------------------+---------+------+---------------------------+---------------------------+---------+
```

**6.** Back up the etcd database using the `snapshot` argument. The snapshot is saved inside the container's data directory `/var/lib/etcd/`.

```bash
kubectl -n kube-system exec -it etcd-controller -- sh \
  -c "ETCDCTL_API=3 \
  ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
  ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \
  ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
  etcdctl --endpoints=https://127.0.0.1:2379 snapshot save /var/lib/etcd/snapshot.db"
```

```
{"level":"info",...,"msg":"created temporary db file","path":"/var/lib/etcd/snapshot.db.part"}
{"level":"info",...,"msg":"fetched snapshot","endpoint":"https://127.0.0.1:2379"}
{"level":"info",...,"msg":"saved","path":"/var/lib/etcd/snapshot.db"}
Snapshot saved at /var/lib/etcd/snapshot.db
```

**7.** Verify the snapshot file exists from the node perspective.

```bash
sudo ls -l /var/lib/etcd/
```

```
total 3888
drwx------ 4 root root    4096 Aug 25 11:22 member
-rw------- 1 root root 3973152 Aug 25 18:42 snapshot.db
```

**8.** Back up the snapshot and cluster config files locally in case the node becomes unavailable.

```bash
mkdir $HOME/backup
sudo cp /var/lib/etcd/snapshot.db $HOME/backup/snapshot.db-$(date +%m-%d-%y)
sudo cp /root/kubeadm-config.yaml $HOME/backup/
sudo cp -r /etc/kubernetes/pki/etcd $HOME/backup/
```

> Any mistakes during restore may render the cluster unusable. Attempt a restore only after the final lab exercise. More on the restore process: https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#restoring-an-etcd-cluster

---

### Upgrade the Cluster — Control Plane Node

**1.** Update the package metadata for APT.

```bash
sudo apt update
```

```
<output_omitted>
```

**2.** Update the Kubernetes apt repository to point to the new minor version you want to upgrade to. Replace `33` with `34` to target v1.34.

```bash
sudo sed -i 's/v1.33/v1.34/g' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
```

**3.** View the available kubeadm packages to confirm the target version is available.

```bash
sudo apt-cache madison kubeadm
```

```
kubeadm | 1.34.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
kubeadm | 1.34.0-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
<output_omitted>
```

**4.** Remove the hold on **kubeadm** and upgrade it to the next release's first patch (update 1).

```bash
sudo apt-mark unhold kubeadm
```

```
Canceled hold on kubeadm.
```

```bash
sudo apt-get install -y kubeadm=1.34.1-1.1
```

```
Reading package lists... Done
Building dependency tree
Reading state information... Done
<output_omitted>
```

**5.** Hold the package again to prevent unintended upgrades.

```bash
sudo apt-mark hold kubeadm
```

```
kubeadm set on hold.
```

**6.** Verify the new kubeadm version.

```bash
sudo kubeadm version
```

```
kubeadm version: &version.Info{Major:"1", Minor:"34", GitVersion:"v1.34.1", ...}
```

**7.** Drain the CP node to evict as many pods as possible before upgrading. DaemonSet pods such as Cilium must remain.

```bash
kubectl drain controller --ignore-daemonsets
```

```
node/controller cordoned
Warning: ignoring DaemonSet-managed Pods: kube-system/cilium-5tv9d, kube-system/kube-proxy-8x9c5
evicting pod kube-system/coredns-5d78c9869d-z5ngb
evicting pod kube-system/cilium-operator-788c7d7585-wnb5b
evicting pod kube-system/coredns-5d78c9869d-4h2bs
pod/cilium-operator-788c7d7585-wnb5b evicted
pod/coredns-5d78c9869d-z5ngb evicted
pod/coredns-5d78c9869d-4h2bs evicted
node/controller drained
```

**8.** Review the upgrade plan. Read through the output to understand what will change.

```bash
sudo kubeadm upgrade plan
```

```
[preflight] Running pre-flight checks.
[upgrade/config] Reading configuration from the cluster...
[upgrade] Running cluster health checks
[upgrade/versions] Cluster version: v1.33.1
[upgrade/versions] kubeadm version: v1.34.1
[upgrade/versions] Target version: v1.34.1
[upgrade/versions] Latest version in the v1.34 series: v1.34.1
<output_omitted>
```

**9.** Apply the upgrade. Answer **y** when prompted. This will take several minutes.

```bash
sudo kubeadm upgrade apply v1.34.1
```

```
[preflight] Running pre-flight checks.
[upgrade/config] Reading configuration from the cluster...
[upgrade/version] You have chosen to change the cluster version to "v1.34.1"
[upgrade/versions] Cluster version: v1.33.1
[upgrade/versions] kubeadm version: v1.34.1
[upgrade] Are you sure you want to proceed? [y/N]: y
[upgrade/prepull] Pulling images required for setting up a Kubernetes cluster
<output_omitted>
```

**10.** Check node status. The CP should show `Ready,SchedulingDisabled` and still show the old version until kubelet is upgraded.

```bash
kubectl get node
```

```
NAME     STATUS                     ROLES           AGE    VERSION
controller   Ready,SchedulingDisabled   control-plane   109m   v1.33.1
worker1      Ready                      <none>          61m    v1.33.1
```

**11.** Release the hold on **kubelet** and **kubectl**.

```bash
sudo apt-mark unhold kubelet kubectl
```

```
Canceled hold on kubelet.
Canceled hold on kubectl.
```

**12.** Upgrade both packages to match kubeadm.

```bash
sudo apt-get install -y kubelet=1.34.1-1.1 kubectl=1.34.1-1.1
```

```
Reading package lists... Done
<output_omitted>
```

**13.** Hold the packages again.

```bash
sudo apt-mark hold kubelet kubectl
```

```
kubelet set on hold.
kubectl set on hold.
```

**14.** Restart the daemons.

```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

**15.** Verify the CP node now shows the new version. The worker still shows the old version — we will upgrade it next.

```bash
kubectl get node
```

```
NAME     STATUS                     ROLES           AGE    VERSION
controller   Ready,SchedulingDisabled   control-plane   113m   v1.34.1
worker1      Ready                      <none>          65m    v1.33.1
```

**16.** Make the CP available for scheduling again.

```bash
kubectl uncordon controller
```

```
node/controller uncordoned
```

**17.** Verify the CP now shows `Ready` status.

```bash
kubectl get node
```

```
NAME     STATUS   ROLES           AGE    VERSION
controller   Ready    control-plane   114m   v1.34.1
worker1      Ready    <none>          66m    v1.33.1
```

---

### Upgrade the Cluster — Worker Node

> Open a **second terminal** connected to the **worker node** for steps 18–27. You will also need the CP terminal open.

**18.** On the **worker node**, remove the hold on kubeadm.

```bash
sudo apt-mark unhold kubeadm
```

```
Canceled hold on kubeadm.
```

**19.** Update the apt repository to point to v1.34, then update package metadata.

```bash
sudo sed -i 's/v1.33/v1.34/g' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
```

**20.** View available packages to confirm the target version.

```bash
sudo apt-cache madison kubeadm
```

```
kubeadm | 1.34.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
kubeadm | 1.34.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
kubeadm | 1.34.0-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
<output_omitted>
```

**21.** Install the updated kubeadm on the worker.

```bash
sudo apt-get update && sudo apt-get install -y kubeadm=1.34.1-1.1
```

```
<output_omitted>
Setting up kubeadm (1.34.1-1.1) ...
```

**22.** Hold kubeadm again.

```bash
sudo apt-mark hold kubeadm
```

```
kubeadm set on hold.
```

**23.** Back on the **CP node**, drain the worker node to evict its pods before upgrading.

```bash
kubectl drain worker1 --ignore-daemonsets
```

```
node/worker1 cordoned
Warning: ignoring DaemonSet-managed Pods: kube-system/cilium-gzdk6, kube-system/kube-proxy-lpsmq
evicting pod kube-system/coredns-5d78c9869d-h4p7v
evicting pod kube-system/coredns-5d78c9869d-d4nv8
pod/coredns-5d78c9869d-h4p7v evicted
pod/coredns-5d78c9869d-d4nv8 evicted
node/worker1 drained
```

**24.** Back on the **worker node**, download the updated node configuration.

```bash
sudo kubeadm upgrade node
```

```
[upgrade] Reading configuration from the cluster...
[preflight] Running pre-flight checks
[preflight] Skipping prepull. Not a control plane node.
[upgrade] Skipping phase. Not a control plane node.
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[upgrade] The configuration for this node was successfully updated!
[upgrade] Now you should go ahead and upgrade the kubelet package using your package manager.
```

**25.** Remove the hold on kubelet and kubectl, then upgrade them.

```bash
sudo apt-mark unhold kubelet kubectl
```

```
Canceled hold on kubelet.
Canceled hold on kubectl.
```

```bash
sudo apt-get install -y kubelet=1.34.1-1.1 kubectl=1.34.1-1.1
```

```
Reading package lists... Done
<output_omitted>
Setting up kubectl (1.34.1-1.1) ...
Setting up kubelet (1.34.1-1.1) ...
```

**26.** Hold the packages again.

```bash
sudo apt-mark hold kubelet kubectl
```

```
kubelet set on hold.
kubectl set on hold.
```

**27.** Restart the daemons on the worker node.

```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

**28.** Back on the **CP node**, check the status of both nodes.

```bash
kubectl get node
```

```
NAME     STATUS                     ROLES           AGE    VERSION
controller   Ready                      control-plane   118m   v1.34.1
worker1      Ready,SchedulingDisabled   <none>          70m    v1.34.1
```

**29.** Uncordon the worker node to allow pods to be scheduled on it again.

```bash
kubectl uncordon worker1
```

```
node/worker1 uncordoned
```

**30.** Verify both nodes show `Ready` and the same upgraded version.

```bash
kubectl get nodes
```

```
NAME     STATUS   ROLES           AGE    VERSION
controller   Ready    control-plane   119m   v1.34.1
worker1      Ready    <none>          71m    v1.34.1
```

---

## Exercise 4.2: Working with CPU and Memory Constraints

We will deploy a **stress** application inside a container and use `resource limits` to constrain what it can consume.

```bash
cd ~/lfs458/ch04-architecture/
```

**1.** Create a deployment called `hog` using the `vish/stress` container image and verify it is running.

```bash
kubectl create deployment hog --image vish/stress
```

```
deployment.apps/hog created
```

```bash
kubectl get deployments
```

```
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
hog    1/1     1            1           13s
```

**2.** Describe the deployment and view the output in YAML format. Note there are no resource limits set — the `resources:` field shows empty curly brackets `{}`.

```bash
kubectl describe deployment hog
```

```
Name:       hog
Namespace:  default
Labels:     app=hog
Annotations: deployment.kubernetes.io/revision: 1
<output_omitted>
```

```bash
kubectl get deployment hog -o yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
<output_omitted>
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: hog
    spec:
      containers:
      - image: vish/stress
        imagePullPolicy: Always
        name: stress
        resources: {}
<output_omitted>
```

**3.** Save the deployment YAML to a file.

```bash
kubectl get deployment hog -o yaml > hog.yaml
```

**4.** Edit the file to remove the `status:` section, `creationTimestamp`, and other generated fields. Then add memory resource limits as shown below. Find the `resources: {}` line and replace it with the limits block.

```bash
vim hog.yaml
```

```yaml
....
        name: hog
        resources:             # Edit to remove {}
          limits:              # Add these 4 lines
            memory: "4Gi"
          requests:
            memory: "2500Mi"
        terminationMessagePath: /dev/termination-log
....
```

**5.** Replace the deployment using the edited file.

```bash
kubectl replace -f hog.yaml
```

```
deployment.apps/hog replaced
```

**6.** Verify the deployment now shows the memory resource limits.

```bash
kubectl get deployment hog -o yaml
```

```yaml
....
        resources:
          limits:
            memory: 4Gi
          requests:
            memory: 2500Mi
        terminationMessagePath: /dev/termination-log
....
```

**7.** View the pod name and check its logs to see the stress application output.

```bash
kubectl get po
```

```
NAME                    READY   STATUS    RESTARTS   AGE
hog-64cbfcc7cf-lwq66    1/1     Running   0          2m
```

```bash
kubectl logs <hog-pod-name>
```

```
I1102 16:16:42.638972  1 main.go:26] Allocating "0" memory, in
  "4Ki" chunks, with a 1ms sleep between allocations
I1102 16:16:42.639064  1 main.go:29] Allocated "0" memory
```

**8.** Open a second and third terminal to access both CP and worker nodes. Run `top` on each to monitor resource usage. The **stress** command is not consuming resources yet since no `args:` have been set.

**9.** Edit `hog.yaml` to add CPU and memory consumption arguments for the **stress** container. The `args:` entry should be indented at the same level as `resources:`.

```bash
vim hog.yaml
```

```yaml
....
        resources:
          limits:
            cpu: "1"
            memory: "4Gi"
          requests:
            cpu: "0.5"
            memory: "500Mi"
        args:
        - -cpus
        - "2"
        - -mem-total
        - "950Mi"
        - -mem-alloc-size
        - "100Mi"
        - -mem-alloc-sleep
        - "1s"
....
```

**10.** Delete and recreate the deployment. Watch the `top` output on both nodes — you should see CPU usage spike and memory allocated in 100Mi chunks.

```bash
kubectl delete deployment hog
```

```
deployment.apps "hog" deleted
```

```bash
kubectl create -f hog.yaml
```

```
deployment.apps/hog created
```

> If `top` does not show high usage, check the pod logs for errors. A common mistake is using `Mi` (case sensitive) — `mi` will cause the container to panic.

```bash
kubectl get pod
kubectl logs <hog-pod-name>
```

---

## Exercise 4.3: Resource Limits for a Namespace

The previous exercise set limits on a specific deployment. You can also set limits on an entire **namespace** using a `LimitRange` object. When set, the `hog` deployment should not be able to exceed those namespace-level limits.

```bash
cd ~/lfs458/ch04-architecture/
```

**1.** Create a new namespace called `low-usage-limit` and verify it exists.

```bash
kubectl create namespace low-usage-limit
```

```
namespace/low-usage-limit created
```

```bash
kubectl get namespace
```

```
NAME              STATUS   AGE
default           Active   1h
kube-node-lease   Active   1h
kube-public       Active   1h
kube-system       Active   1h
low-usage-limit   Active   42s
```

**2.** The `low-resource-range.yaml` file is already staged in your lab folder. Review it.

```bash
cat ~/lfs458/ch04-architecture/low-resource-range.yaml
```

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: low-resource-range
spec:
  limits:
  - default:
      cpu: 1
      memory: 500Mi
    defaultRequest:
      cpu: 0.5
      memory: 100Mi
    type: Container
```

**3.** Apply the LimitRange to the `low-usage-limit` namespace.

```bash
kubectl create -f ~/lfs458/ch04-architecture/low-resource-range.yaml \
  -n low-usage-limit
```

```
limitrange/low-resource-range created
```

**4.** Verify the LimitRange was created. Note it only exists in the `low-usage-limit` namespace — the default namespace shows nothing.

```bash
kubectl get LimitRange
```

```
No resources found in default namespace.
```

```bash
kubectl get LimitRange --all-namespaces
```

```
NAMESPACE         NAME                CREATED AT
low-usage-limit   low-resource-range  2024-06-23T10:23:57Z
```

**5.** Create a new deployment in the `low-usage-limit` namespace.

```bash
kubectl -n low-usage-limit \
  create deployment limited-hog --image vish/stress
```

```
deployment.apps/limited-hog created
```

**6.** List deployments across all namespaces. Note that `hog` continues to run in the `default` namespace.

```bash
kubectl get deployments --all-namespaces
```

```
NAMESPACE         NAME              READY   UP-TO-DATE   AVAILABLE   AGE
default           hog               1/1     1            1           7m57s
kube-system       cilium-operator   1/1     1            1           2d10h
kube-system       coredns           2/2     2            2           2d10h
low-usage-limit   limited-hog       1/1     1            1           9s
```

**7.** View the pods in the `low-usage-limit` namespace.

```bash
kubectl -n low-usage-limit get pods
```

```
NAME                            READY   STATUS    RESTARTS   AGE
limited-hog-2556092078-wnpnv    1/1     Running   0          2m11s
```

**8.** Look at the pod details. Notice it has inherited the resource limits from the namespace LimitRange.

```bash
kubectl -n low-usage-limit \
  get pod <limited-hog-pod-name> -o yaml
```

```yaml
<output_omitted>
spec:
  containers:
  - image: vish/stress
    imagePullPolicy: Always
    name: stress
    resources:
      limits:
        cpu: "1"
        memory: 500Mi
      requests:
        cpu: 500m
        memory: 100Mi
    terminationMessagePath: /dev/termination-log
<output_omitted>
```

**9.** Copy `hog.yaml` to a new file and add a `namespace:` line so the deployment runs in `low-usage-limit`. Delete the `selfLink:` line if it exists.

```bash
cp hog.yaml hog2.yaml
vim hog2.yaml
```

```yaml
....
  labels:
    app: hog
  name: hog
  namespace: low-usage-limit    #<-- Add this line, delete selfLink below if present
spec:
....
```

**10.** Create the deployment in the `low-usage-limit` namespace.

```bash
kubectl create -f hog2.yaml
```

```
deployment.apps/hog created
```

**11.** List all deployments. You should see two deployments with the same name `hog` — one in `default` and one in `low-usage-limit`.

```bash
kubectl get deployments --all-namespaces
```

```
NAMESPACE         NAME              READY   UP-TO-DATE   AVAILABLE   AGE
default           hog               1/1     1            1           24m
kube-system       cilium-operator   1/1     0            0           4h
kube-system       coredns           2/2     2            2           4h
low-usage-limit   hog               1/1     1            1           26s
low-usage-limit   limited-hog       1/1     1            1           5m11s
```

**12.** Check `top` on both node terminals. Both `hog` deployments should be consuming about the same resources — the per-deployment settings from `hog.yaml` override the global namespace limits.

```
25128 root   20   0  958532 954672  3180 R 100.0 11.7   0:52.27 stress
24875 root   20   0  958532 954800  3180 R 100.3 11.7  41:04.97 stress
```

**13.** Delete all `hog` deployments to recover cluster resources.

```bash
kubectl -n low-usage-limit delete deployment hog limited-hog
```

```
deployment.apps "hog" deleted
deployment.apps "limited-hog" deleted
```

```bash
kubectl delete deployment hog
```

```
deployment.apps "hog" deleted
```

---
