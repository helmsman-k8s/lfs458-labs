# Chapter 9: Volumes and Storage

## Overview

In this lab you will:

- Use ConfigMaps and Secrets as volumes
- Create a PersistentVolume backed by NFS
- Bind a PersistentVolumeClaim and use it in a pod
- Configure ResourceQuotas for storage
- Set up dynamic provisioning with a StorageClass

Lab files are in `~/lfs458/ch09-volumes/`. Completed YAMLs for files you need to edit are in the `solutions/` subfolder.

---

## Lab 9.1 — ConfigMaps as Volumes

Create a ConfigMap containing an nginx config:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-conf
data:
  nginx.conf: |
    server {
      listen 80;
      root /usr/share/nginx/html;
      index index.html;
    }
EOF
```

Mount it into a pod:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-configmap
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: config-vol
      mountPath: /etc/nginx/conf.d
  volumes:
  - name: config-vol
    configMap:
      name: nginx-conf
EOF
```

```bash
CM_POD=$(kubectl get pod nginx-configmap -o jsonpath='{.metadata.name}')
kubectl exec $CM_POD -- cat /etc/nginx/conf.d/nginx.conf
```

Clean up:

```bash
kubectl delete pod nginx-configmap
kubectl delete configmap nginx-conf
```

---

## Lab 9.2 — Using simpleshell.yaml

The `simpleshell.yaml` file defines a basic container. You will modify it in two stages.

```bash
cp ~/lfs458/ch09-volumes/simpleshell.yaml ~/simpleshell.yaml
cat ~/simpleshell.yaml
```

### Stage 1 — Add envFrom

Edit `~/simpleshell.yaml` to add an `envFrom` section referencing the `nginx-conf` configmap (create a simple one first):

```bash
kubectl create configmap shell-config \
  --from-literal=MY_VAR=hello \
  --from-literal=ANOTHER_VAR=world
```

Add to `~/simpleshell.yaml` under `spec.containers[0]`:

```yaml
envFrom:
- configMapRef:
    name: shell-config
```

The solution is at `~/lfs458/ch09-volumes/solutions/simpleshell-envfrom.yaml`.

Apply and verify:

```bash
kubectl apply -f ~/simpleshell.yaml
SS_POD=$(kubectl get pod simpleshell -o jsonpath='{.metadata.name}')
kubectl exec $SS_POD -- env | grep -E "MY_VAR|ANOTHER_VAR"
kubectl delete pod simpleshell
```

### Stage 2 — Add a volumeMount

Edit `~/simpleshell.yaml` further to mount a volume using a `hostPath`. The solution is at `~/lfs458/ch09-volumes/solutions/simpleshell-volume.yaml`.

Apply and verify:

```bash
kubectl apply -f ~/simpleshell.yaml
SS_POD=$(kubectl get pod simpleshell -o jsonpath='{.metadata.name}')
kubectl exec $SS_POD -- ls /mnt/data
kubectl delete pod simpleshell
kubectl delete configmap shell-config
```

---

## Lab 9.3 — NFS PersistentVolume

!!! info "NFS Server"
    This lab assumes an NFS server is available. In the lab environment, the `controller` node can act as the NFS server.

### Set up NFS server (controller only)

```bash
sudo apt-get install -y nfs-kernel-server
sudo mkdir -p /opt/sfw
sudo chmod 777 /opt/sfw
echo "/opt/sfw *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

Verify the export:

```bash
showmount -e controller
```

### Install NFS client on workers (worker1 and worker2)

```bash
sudo apt-get install -y nfs-common
```

### Create the PersistentVolume

```bash
cp ~/lfs458/ch09-volumes/PVol.yaml ~/PVol.yaml
cat ~/PVol.yaml
```

Note the `persistentVolumeReclaimPolicy`. Edit `~/PVol.yaml` to change it to `Retain`. The solution is at `~/lfs458/ch09-volumes/solutions/PVol-retain.yaml`.

```bash
kubectl apply -f ~/PVol.yaml
kubectl get pv
```

### Create a PersistentVolumeClaim

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 200Mi
  storageClassName: ""
EOF

kubectl get pvc nfs-pvc
```

### Use the PVC in a pod

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-nfs
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: nfs-vol
      mountPath: /usr/share/nginx/html
  volumes:
  - name: nfs-vol
    persistentVolumeClaim:
      claimName: nfs-pvc
EOF
```

```bash
NFS_POD=$(kubectl get pod nginx-nfs -o jsonpath='{.metadata.name}')
kubectl describe pod $NFS_POD | grep -A5 Volumes
```

Write a test file from the controller and read it in the pod:

```bash
sudo bash -c 'echo "<h1>Hello from NFS</h1>" > /opt/sfw/index.html'
kubectl exec $NFS_POD -- cat /usr/share/nginx/html/index.html
```

### Clean up

```bash
kubectl delete pod nginx-nfs
kubectl delete pvc nfs-pvc
kubectl delete pv nfs-pv
```

---

## Lab 9.4 — ResourceQuota for Storage

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: default
spec:
  hard:
    requests.storage: "500Mi"
    persistentvolumeclaims: "3"
EOF

kubectl describe resourcequota storage-quota
```

Try to create a PVC that exceeds the quota:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: big-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 600Mi
  storageClassName: ""
EOF
```

You should see a `forbidden: exceeded quota` error.

Clean up:

```bash
kubectl delete resourcequota storage-quota
kubectl delete pvc big-pvc 2>/dev/null; true
```
