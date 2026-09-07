# Chapter 7: Deployments, ReplicaSets, and DaemonSets

## Overview

In this lab you will:

- Work with ReplicaSets directly
- Create and manage Deployments (scale, rollout, rollback)
- Create a DaemonSet with `OnDelete` and `RollingUpdate` strategies

Lab files are in `~/lfs458/ch07-deployments/`. The `solutions/` subfolder contains completed manifests for files you need to edit.

---

## Lab 7.1 — ReplicaSets

Create a ReplicaSet:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: webserver
  labels:
    app: webserver
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webserver
  template:
    metadata:
      labels:
        app: webserver
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF
```

List pods managed by the ReplicaSet:

```bash
kubectl get rs webserver
kubectl get pods -l app=webserver
```

Delete one pod and watch the ReplicaSet recreate it:

```bash
RS_POD=$(kubectl get pod -l app=webserver -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $RS_POD
kubectl get pods -l app=webserver -w
```

### Clean up

```bash
kubectl delete rs webserver
```

---

## Lab 7.2 — Deployments

Create a Deployment:

```bash
kubectl create deployment webserver --image=nginx:1.25 --replicas=3
kubectl rollout status deployment webserver
kubectl get pods -l app=webserver
```

Inspect the Deployment:

```bash
WEB_POD=$(kubectl get pod -l app=webserver -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $WEB_POD | grep Image:
```

### Scale the Deployment

```bash
kubectl scale deployment webserver --replicas=5
kubectl get pods -l app=webserver -w
```

### Update the image (rolling update)

```bash
kubectl set image deployment/webserver nginx=nginx:1.26
```

Watch the update progress — old pods are terminated one by one as new ones become ready. Press `Ctrl+C` once the pod count settles:

```bash
kubectl get pods -l app=webserver -w
```

Confirm the rollout has finished:

```bash
kubectl rollout status deployment webserver
```

```
deployment "webserver" successfully rolled out
```

Verify the new image is running:

```bash
WEB_POD=$(kubectl get pod -l app=webserver -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $WEB_POD | grep Image:
```

### Rollback

```bash
kubectl rollout history deployment webserver
kubectl rollout undo deployment webserver
kubectl rollout status deployment webserver

WEB_POD=$(kubectl get pod -l app=webserver -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $WEB_POD | grep Image:
```

The image should be back to `nginx:1.25`.

### Pause and resume a rollout

```bash
# Start an update and immediately pause
kubectl set image deployment/webserver nginx=nginx:1.27
kubectl rollout pause deployment webserver

# Inspect — only some pods updated
kubectl get pods -l app=webserver

# Resume
kubectl rollout resume deployment webserver
kubectl rollout status deployment webserver
```

### Clean up

```bash
kubectl delete deployment webserver
```

---

## Lab 7.3 — DaemonSets

Create a DaemonSet with the `OnDelete` update strategy so you control when each node's pod is updated:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ds-one
  labels:
    app: ds-one
spec:
  updateStrategy:
    type: OnDelete
  selector:
    matchLabels:
      system: ds-one
  template:
    metadata:
      labels:
        system: ds-one
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF
```

Verify the DaemonSet runs one pod per node:

```bash
kubectl get ds ds-one
kubectl get pods -l system=ds-one -o wide
```

Update the image:

```bash
kubectl set image ds/ds-one nginx=nginx:1.26
```

> **Note:** `rollout status` is not supported for `OnDelete` DaemonSets — pods are only updated when you delete them manually.

With `OnDelete`, pods are only updated when you delete them manually:

```bash
DS_POD=$(kubectl get pod -l system=ds-one -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $DS_POD
# A new pod is created with the updated image
kubectl get pods -l system=ds-one -o wide
```

Verify the updated pod runs the new image:

```bash
DS_POD=$(kubectl get pod -l system=ds-one -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $DS_POD | grep Image:
```

### Switch to RollingUpdate

Edit the DaemonSet in place:

```bash
kubectl patch ds ds-one -p '{"spec":{"updateStrategy":{"type":"RollingUpdate"}}}'
kubectl get ds ds-one -o jsonpath='{.spec.updateStrategy.type}'
```

Now update the image — all pods roll over automatically:

```bash
kubectl set image ds/ds-one nginx=nginx:1.27
kubectl rollout status ds/ds-one
```

### Clean up

```bash
kubectl delete ds ds-one
```
