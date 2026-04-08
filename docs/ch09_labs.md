# Chapter 9: Volumes and Data

**Working directory: `~/lfs458/ch09-volumes/`**

---

## Exercise 9.1: Create a ConfigMap

A `ConfigMap` decouples configuration from container images. Data is stored as key-value pairs and can be consumed as environment variables or mounted volumes. Unlike Secrets, ConfigMap data is not encoded.

```bash
cd ~/lfs458/ch09-volumes/
```

---

### ConfigMap from files and literals

**1.** Create a directory called `primary` and populate it with four color files. Also create a `favorite` file in the home directory.

```bash
mkdir primary
echo c > primary/cyan
echo m > primary/magenta
echo y > primary/yellow
echo k > primary/black
echo "known as key" >> primary/black
echo blue > favorite
```

**2.** Create a ConfigMap called `colors` from all three sources — a literal, a single file, and the entire directory.

```bash
kubectl create configmap colors \
  --from-literal=text=black \
  --from-file=./favorite \
  --from-file=./primary/
```

```
configmap/colors created
```

**3.** View the ConfigMap to understand how data is organised.

```bash
kubectl get configmap colors
```

```
NAME     DATA   AGE
colors   6      30s
```

```bash
kubectl get configmap colors -o yaml
```

```yaml
apiVersion: v1
data:
  black: |
    k
    known as key
  cyan: |
    c
  favorite: |
    blue
  magenta: |
    m
  text: black
  yellow: |
    y
kind: ConfigMap
<output_omitted>
```

**4.** Create a Pod that uses one ConfigMap key as an environment variable. The `simpleshell.yaml` file is pre-staged in your lab folder.

```bash
cat ~/lfs458/ch09-volumes/simpleshell.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shell-demo
spec:
  containers:
  - name: nginx
    image: nginx
    env:
    - name: ilike
      valueFrom:
        configMapKeyRef:
          name: colors
          key: favorite
```

```bash
kubectl create -f simpleshell.yaml
```

```
pod/shell-demo created
```

**5.** Verify the environment variable is set inside the Pod, then delete it.

```bash
kubectl exec shell-demo -- /bin/bash -c 'echo $ilike'
```

```
blue
```

```bash
kubectl delete pod shell-demo
```

```
pod "shell-demo" deleted
```

**6.** Edit `simpleshell.yaml` to load **all** ConfigMap keys as environment variables using `envFrom`. Comment out the previous `env:` block and add `envFrom:` at the same indentation as `image:`.

```bash
vim simpleshell.yaml
```

```yaml
<output_omitted>
      image: nginx
#     env:
#     - name: ilike
#       valueFrom:
#         configMapKeyRef:
#           name: colors
#           key: favorite
      envFrom:                    #<-- Same indent as image: line
      - configMapRef:
          name: colors
```

```bash
kubectl create -f simpleshell.yaml
```

```
pod/shell-demo created
```

```bash
kubectl exec shell-demo -- /bin/bash -c 'env'
```

```
black=k
known as key

KUBERNETES_SERVICE_PORT_HTTPS=443
cyan=c
<output_omitted>
```

```bash
kubectl delete pod shell-demo
```

```
pod "shell-demo" deleted
```

---

### ConfigMap from a YAML file

**7.** Create a ConfigMap from a YAML file describing a car. The `car-map.yaml` file is pre-staged.

```bash
cat ~/lfs458/ch09-volumes/car-map.yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fast-car
  namespace: default
data:
  car.make: Ford
  car.model: Mustang
  car.trim: Shelby
```

```bash
kubectl create -f car-map.yaml
```

```
configmap/fast-car created
```

```bash
kubectl get configmap fast-car -o yaml
```

```yaml
apiVersion: v1
data:
  car.make: Ford
  car.model: Mustang
  car.trim: Shelby
kind: ConfigMap
<output_omitted>
```

---

### ConfigMap as a mounted volume

**8.** Edit `simpleshell.yaml` to mount the `fast-car` ConfigMap as a volume at `/etc/cars`. Comment out the `envFrom:` block and add the `volumeMounts:` and `volumes:` sections.

```bash
vim simpleshell.yaml
```

```yaml
<output_omitted>
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: car-vol
      mountPath: /etc/cars
    volumes:
    - name: car-vol
      configMap:
        name: fast-car
    <comment out rest of file>
```

**9.** Wait, note: `volumes:` must be at the same level as `containers:` (under `spec:`), not inside `containers:`. Correct indentation:

```yaml
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: car-vol
      mountPath: /etc/cars
  volumes:
  - name: car-vol
    configMap:
      name: fast-car
```

**10.** Create the Pod and verify the volume mount exists and the ConfigMap data is accessible.

```bash
kubectl create -f simpleshell.yaml
```

```
pod/shell-demo created
```

```bash
kubectl exec shell-demo -- /bin/bash -c 'df -ha |grep car'
```

```
/dev/root   9.6G  3.2G  6.4G  34%  /etc/cars
```

```bash
kubectl exec shell-demo -- /bin/bash -c 'cat /etc/cars/car.trim'
```

```
Shelby
```

**11.** Delete the Pod and ConfigMaps.

```bash
kubectl delete pods shell-demo
kubectl delete configmap fast-car colors
```

```
pod "shell-demo" deleted
configmap "fast-car" deleted
configmap "colors" deleted
```

---

## Exercise 9.2: Creating a Persistent NFS Volume (PV)

We will deploy an NFS server on the CP node, then create a `PersistentVolume` backed by it.

**1.** Install the NFS server software on the **CP node**.

```bash
sudo apt-get update && sudo apt-get install -y nfs-kernel-server
```

**2.** Create the shared directory and populate it.

```bash
sudo mkdir /opt/sfw
sudo chmod 1777 /opt/sfw/
sudo bash -c 'echo software > /opt/sfw/hello.txt'
```

**3.** Configure the NFS export. Edit `/etc/exports` and add the following line.

```bash
sudo vim /etc/exports
```

```
/opt/sfw/ *(rw,sync,no_root_squash,subtree_check)
```

**4.** Force the NFS server to re-read the exports file.

```bash
sudo exportfs -ra
```

**5.** On the **worker1 node**, install the NFS client and verify the export is visible.

```bash
# SSH into worker1 first
ssh worker1
sudo apt-get install -y nfs-common
showmount -e controller
```

```
Export list for controller:
/opt/sfw  *
```

**6.** Test the mount from the worker1 node.

```bash
# Still on worker1
sudo mount controller:/opt/sfw /mnt
ls -l /mnt
sudo umount /mnt
exit
```

```
total 4
-rw-r--r-- 1 root root 23 Aug 28 17:55 hello.txt
```

**7.** Return to the **CP node**. The `PVol.yaml` file is pre-staged in your lab folder. Review it and ensure the `server:` field matches your CP node hostname.

```bash
cat ~/lfs458/ch09-volumes/PVol.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pvvol-1
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /opt/sfw
    server: controller    #<-- Edit to match your CP hostname if different
    readOnly: false
```

**8.** Create the PersistentVolume and verify it is `Available`.

```bash
kubectl create -f PVol.yaml
```

```
persistentvolume/pvvol-1 created
```

```bash
kubectl get pv
```

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS
pvvol-1   1Gi        RWX            Retain           Available           <unset>
```

---

## Exercise 9.3: Creating a Persistent Volume Claim (PVC)

Before Pods can use a PV, a `PersistentVolumeClaim` must be created. The claim finds a matching PV and binds to it.

**1.** Check for existing PVCs.

```bash
kubectl get pvc
```

```
No resources found in default namespace.
```

**2.** Review the pre-staged `pvc.yaml` file.

```bash
cat ~/lfs458/ch09-volumes/pvc.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-one
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 200Mi
```

**3.** Create the PVC and verify it is `Bound`. Note the bound capacity is 1Gi even though only 200Mi was requested — it bound to the smallest available PV that meets the requirements.

```bash
kubectl create -f pvc.yaml
```

```
persistentvolumeclaim/pvc-one created
```

```bash
kubectl get pvc
```

```
NAME      STATUS   VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-one   Bound    pvvol-1   1Gi        RWX                           7s
```

**4.** Verify the PV now shows `Bound` status.

```bash
kubectl get pv
```

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM             STORAGECLASS
pvvol-1   1Gi        RWX            Retain           Bound    default/pvc-one   <unset>
```

**5.** Review the pre-staged `nfs-pod.yaml` — a Deployment that mounts the PVC at `/opt`.

```bash
cat ~/lfs458/ch09-volumes/nfs-pod.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-nfs
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
    spec:
      containers:
      - image: nginx
        imagePullPolicy: Always
        name: nginx
        volumeMounts:
        - name: nfs-vol
          mountPath: /opt
        ports:
        - containerPort: 80
          protocol: TCP
      volumes:
      - name: nfs-vol
        persistentVolumeClaim:
          claimName: pvc-one
```

**6.** Create the Deployment and verify the Pod is running.

```bash
kubectl create -f nfs-pod.yaml
```

```
deployment.apps/nginx-nfs created
```

```bash
kubectl get pods
```

```
NAME                          READY   STATUS    RESTARTS   AGE
nginx-nfs-1054709768-s8g28    1/1     Running   0          3m
```

**7.** Describe the Pod and confirm the NFS volume is mounted.

```bash
kubectl describe pod <nginx-nfs-pod-name>
```

```
Name:       nginx-nfs-1054709768-s8g28
Namespace:  default
Node:       worker1/192.168.2.x
<output_omitted>
Mounts:
  /opt from nfs-vol (rw)
<output_omitted>
Volumes:
  nfs-vol:
    Type:       PersistentVolumeClaim (a reference to a PersistentV...
    ClaimName:  pvc-one
    ReadOnly:   false
```

---

## Exercise 9.4: Using a ResourceQuota to Limit PVC Count and Usage

A `ResourceQuota` limits the total consumption of resources within a namespace — including storage.

**1.** Delete the existing deployment, PVC and PV to start clean.

```bash
kubectl delete deploy nginx-nfs
kubectl delete pvc pvc-one
kubectl delete pv pvvol-1
```

**2.** Review the pre-staged `storage-quota.yaml`. It limits the namespace to 10 PVCs and 500Mi total storage.

```bash
cat ~/lfs458/ch09-volumes/storage-quota.yaml
```

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storagequota
spec:
  hard:
    persistentvolumeclaims: "10"
    requests.storage: "500Mi"
```

**3.** Create a namespace called `small`.

```bash
kubectl create namespace small
```

```
namespace/small created
```

```bash
kubectl describe ns small
```

```
Name:        small
Status:      Active
No resource quota.
No resource limits.
```

**4.** Create the PV and PVC in the `small` namespace.

```bash
kubectl -n small create -f PVol.yaml
kubectl -n small create -f pvc.yaml
```

```
persistentvolume/pvvol-1 created
persistentvolumeclaim/pvc-one created
```

**5.** Create the ResourceQuota in the `small` namespace.

```bash
kubectl -n small create -f storage-quota.yaml
```

```
resourcequota/storagequota created
```

**6.** Verify the quota is now showing in the namespace.

```bash
kubectl describe ns small
```

```
Name:    small
Status:  Active

Resource Quotas
 Name:                  storagequota
 Resource               Used    Hard
 --------               ---     ---
 persistentvolumeclaims 1       10
 requests.storage       200Mi   500Mi

No resource limits.
```

**7.** Remove the `namespace: default` line from `nfs-pod.yaml` so it can be applied to any namespace via the command line.

```bash
vim nfs-pod.yaml
```

**8.** Deploy the nginx-nfs pod into the `small` namespace.

```bash
kubectl -n small create -f nfs-pod.yaml
```

```
deployment.apps/nginx-nfs created
```

**9.** Verify the deployment has a running Pod.

```bash
kubectl -n small get deploy
```

```
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
nginx-nfs   1/1     1            1           43s
```

**10.** Verify the Pod is running.

```bash
kubectl -n small get pod
```

```
NAME                          READY   STATUS    RESTARTS   AGE
nginx-nfs-2854978848-g3khf    1/1     Running   0          37s
```

**11.** Confirm the NFS volume is mounted.

```bash
kubectl -n small describe pod <nginx-nfs-pod-name>
```

```
Mounts:
  /opt from nfs-vol (rw)
```

**12.** View the quota usage.

```bash
kubectl describe ns small
```

```
Resource Quotas
 Name:                  storagequota
 Resource               Used    Hard
 --------               ---     ---
 persistentvolumeclaims 1       10
 requests.storage       200Mi   500Mi
```

**13.** Write a 300M file to `/opt/sfw` on the host and check quota — note NFS storage usage is not counted against the deployment quota.

```bash
sudo dd if=/dev/zero of=/opt/sfw/bigfile bs=1M count=300
```

```
300+0 records in
300+0 records out
314572800 bytes (315 MB, 300 MiB) copied
```

```bash
kubectl describe ns small
```

```
requests.storage   200Mi   500Mi
```

```bash
du -h /opt/
```

```
301M    /opt/sfw
341M    /opt/
```

**14.** Shut down the deployment.

```bash
kubectl -n small delete deploy nginx-nfs
```

**15.** Check the quota — storage is still counted even with no pods running.

```bash
kubectl describe ns small
```

```
requests.storage   200Mi   500Mi
```

**16.** View the PVC and PV, then delete the PVC. Note the PV policy is `Retain`.

```bash
kubectl -n small get pvc
kubectl -n small delete pvc pvc-one
kubectl -n small get pv
```

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM
pvvol-1   1Gi        RWX            Retain           Released   small/pvc-one
```

**17.** Manually provisioned PVs default to `Retain`. Delete and recreate the PV, then use `kubectl patch` to change the policy to `Delete`.

```bash
kubectl delete pv pvvol-1
kubectl create -f PVol.yaml
kubectl patch pv pvvol-1 -p \
  '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
```

```
persistentvolume/pvvol-1 patched
```

```bash
kubectl get pv/pvvol-1
```

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM
pvvol-1   1Gi        RWX            Delete           Available
```

**18.** Create the PVC again and verify quota usage.

```bash
kubectl -n small create -f pvc.yaml
kubectl describe ns small
```

```
requests.storage   200Mi   500Mi
```

**19.** Delete the quota and recreate it with a lower `requests.storage` of `100Mi`.

```bash
kubectl -n small delete resourcequota storagequota
vim storage-quota.yaml
```

```yaml
....
    requests.storage: "100Mi"    #<-- Edit from 500Mi
```

```bash
kubectl -n small create -f storage-quota.yaml
kubectl describe ns small
```

```
persistentvolumeclaims   1       10
requests.storage         200Mi   100Mi
```

**20.** The quota is already exceeded. Add a `LimitRange` to enforce resource constraints (reuse from Chapter 4).

```bash
kubectl -n small create -f ~/lfs458/ch04-architecture/low-resource-range.yaml
```

```
limitrange/low-resource-range created
```

**21.** View the namespace — it now shows both quota and limits.

```bash
kubectl describe ns small
```

```
Resource Limits
 Type       Resource   Min   Max   Default Request   Default Limit
 ----       --------   ---   ---   ---------------   -------------
 Container  cpu        -     -     500m              1
 Container  memory     -     -     100Mi             500Mi
```

**22.** Recreate the PV with `Recycle` policy and attempt to create the PVC. Because the quota limit is exceeded the PVC will be rejected.

```bash
kubectl delete pv pvvol-1
vim PVol.yaml    # change persistentVolumeReclaimPolicy to Recycle
kubectl -n small create -f PVol.yaml
kubectl get pv
```

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM
pvvol-1   1Gi        RWX            Recycle          Available
```

```bash
kubectl -n small create -f pvc.yaml
```

```
Error from server (Forbidden): error when creating "pvc.yaml":
persistentvolumeclaims "pvc-one" is forbidden: exceeded quota:
storagequota, requested: requests.storage=200Mi, used:
requests.storage=0, limited: requests.storage=100Mi
```

**23.** Edit the ResourceQuota to increase `requests.storage` back to `500Mi`.

```bash
kubectl -n small edit resourcequota
```

```yaml
....
spec:
  hard:
    persistentvolumeclaims: "10"
    requests.storage: 500Mi    #<-- Edit back to 500Mi
```

**24.** Create the PVC and Deployment again — they should now succeed.

```bash
kubectl -n small create -f pvc.yaml
kubectl -n small create -f nfs-pod.yaml
```

**25.** View namespace settings and confirm everything is running.

```bash
kubectl -n small get pod
kubectl describe ns small
```

**26.** Delete the Deployment, PVC, then observe the PV status — the `Recycle` policy scrubs the data automatically.

```bash
kubectl -n small delete deploy nginx-nfs
kubectl -n small delete pvc pvc-one
kubectl -n small get pv
```

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM
pvvol-1   1Gi        RWX            Recycle          Available
```

**27.** Remove all remaining resources from this exercise.

```bash
kubectl delete pv pvvol-1
```

---

## Exercise 9.5: Using StorageClass to Dynamically Provision a Volume

A `StorageClass` enables **dynamic provisioning** — PVs are created automatically when a PVC is submitted, eliminating the need for admin-managed PVs.

**1.** Verify no StorageClass exists yet.

```bash
kubectl get sc
```

```
No resources found
```

**2.** Deploy the `nfs-subdir-external-provisioner` via Helm. This provides an NFS-backed StorageClass.

```bash
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

helm install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=controller \
  --set nfs.path=/opt/sfw/
```

```
NAME: nfs-subdir-external-provisioner
LAST DEPLOYED: Mon Jan  8 12:11:39 2024
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

**3.** Verify the provisioner created a StorageClass automatically.

```bash
kubectl get sc
```

```
NAME         PROVISIONER                                    RECLAIMPOLICY   VOLUMEBINDINGMODE
nfs-client   cluster.local/nfs-subdir-external-provisioner Delete          Immediate
```

**4.** Confirm there are no existing PVs or PVCs.

```bash
kubectl get pv,pvc
```

```
No resources found
```

**5.** Review the pre-staged `pvc-sc.yaml` — note it references the StorageClass by name.

```bash
cat ~/lfs458/ch09-volumes/pvc-sc.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-two
spec:
  storageClassName: nfs-client
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 200Mi
```

**6.** Create the PVC and observe that a PV is dynamically provisioned immediately.

```bash
kubectl create -f pvc-sc.yaml
kubectl get pv,pvc
```

```
NAME                                         CAPACITY   ACCESS MODES   RECLAIM   POLICY   STATUS   CLAIM
persistentvolume/pvc-71149612-33f1-4b18...   200Mi      RWX            Delete             Bound    default/pvc-two

NAME                       STATUS   VOLUME                             CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/pvc-two   Bound  pvc-71149612-33f1-4b18...   200Mi      RWX            nfs-client
```

**7.** Review the pre-staged `pod-sc.yaml` — a Pod that mounts the PVC.

```bash
cat ~/lfs458/ch09-volumes/pod-sc.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-server
spec:
  containers:
  - image: nginx
    name: web-container
    volumeMounts:
    - name: nfs-volume
      mountPath: /usr/share/nginx/html
  volumes:
  - name: nfs-volume
    persistentVolumeClaim:
      claimName: pvc-two
```

**8.** Create the Pod.

```bash
kubectl create -f pod-sc.yaml
```

```
pod/web-server created
```

**9.** Write a file and copy it into the Pod's volume mount path.

```bash
echo "Welcome to the demo of storage class" > index.html
kubectl cp index.html web-server:/usr/share/nginx/html
```

**10.** Verify the file was saved to the NFS server directly (not in the ephemeral container layer).

```bash
ls -l /opt/sfw/default-pvc-two-pvc-<Tab>
```

```
-rw-rw-r-- 1 guru guru 37 Jan  8 13:08 index.html
```

**11.** Clean up the Pod and PVC.

```bash
kubectl delete pod/web-server pvc/pvc-two
```

```
pod "web-server" deleted
persistentvolumeclaim "pvc-two" deleted
```

---
