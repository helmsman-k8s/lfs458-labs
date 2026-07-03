# Chapter 12: Scheduling

## Overview

In this lab you will:

- Use `nodeSelector` to pin pods to specific nodes
- Work with node labels
- Apply Taints and Tolerations (`PreferNoSchedule`, `NoSchedule`, `NoExecute`)
- Understand how the scheduler makes placement decisions

---

## Lab 12.1 — nodeSelector

Label a node:

```bash
kubectl label node worker1 disktype=ssd
kubectl get nodes --show-labels | grep disktype
```

Create a pod that requires `disktype=ssd`:

> **Emergency fallback:** `kubectl apply -f ~/lfs458/ch12-scheduling/solutions/ssd-pod.yaml`

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ssd-pod
spec:
  nodeSelector:
    disktype: ssd
  containers:
  - name: nginx
    image: nginx
EOF
```

Verify it landed on `worker1`:

```bash
kubectl get pod ssd-pod -o wide
```

Delete and remove the label:

```bash
kubectl delete pod ssd-pod
kubectl label node worker1 disktype-
```

---

## Lab 12.2 — Node Affinity

Node Affinity is a more expressive replacement for `nodeSelector`.

Label nodes:

```bash
kubectl label node worker1 zone=west
kubectl label node worker2 zone=east
```

Create a pod with `preferredDuringSchedulingIgnoredDuringExecution` (soft requirement):

> **Emergency fallback:** `kubectl apply -f ~/lfs458/ch12-scheduling/solutions/affinity-pod.yaml`

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: affinity-pod
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: zone
            operator: In
            values:
            - west
  containers:
  - name: nginx
    image: nginx
EOF
```

```bash
kubectl get pod affinity-pod -o wide
```

Clean up:

```bash
kubectl delete pod affinity-pod
kubectl label node worker1 zone-
kubectl label node worker2 zone-
```

---

## Lab 12.3 — Taints and Tolerations

### PreferNoSchedule

Apply a `PreferNoSchedule` taint to `worker2` — the scheduler will try to avoid it but will use it if necessary:

```bash
kubectl taint node worker2 gpu=true:PreferNoSchedule
kubectl describe node worker2 | grep -A3 Taints
```

Deploy many replicas and observe where they land:

```bash
kubectl create deployment no-pref --image=nginx --replicas=6
kubectl get pods -l app=no-pref -o wide
```

Most pods should land on `controller` and `worker1`; some may land on `worker2`.

Remove the taint:

```bash
kubectl taint node worker2 gpu=true:PreferNoSchedule-
kubectl delete deployment no-pref
```

### NoSchedule

`NoSchedule` is a hard rule — no new pods will be scheduled on the tainted node unless they tolerate the taint.

```bash
kubectl taint node worker2 gpu=true:NoSchedule
```

Deploy without a toleration — pods should NOT land on `worker2`:

```bash
kubectl create deployment no-sched --image=nginx --replicas=4
kubectl get pods -l app=no-sched -o wide
```

Now deploy with a toleration:

> **Emergency fallback:** `kubectl apply -f ~/lfs458/ch12-scheduling/solutions/tolerates-gpu.yaml`

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tolerates-gpu
spec:
  replicas: 4
  selector:
    matchLabels:
      app: tolerates-gpu
  template:
    metadata:
      labels:
        app: tolerates-gpu
    spec:
      tolerations:
      - key: gpu
        operator: Equal
        value: "true"
        effect: NoSchedule
      containers:
      - name: nginx
        image: nginx
EOF
```

```bash
kubectl get pods -l app=tolerates-gpu -o wide
```

These pods can land on `worker2`.

Remove the taint and clean up:

```bash
kubectl taint node worker2 gpu=true:NoSchedule-
kubectl delete deployment no-sched tolerates-gpu
```

### NoExecute

`NoExecute` evicts already-running pods that lack the toleration.

```bash
kubectl create deployment evict-test --image=nginx --replicas=4
kubectl get pods -l app=evict-test -o wide
```

Note some pods on `worker2`. Now taint it with `NoExecute`:

```bash
kubectl taint node worker2 maintenance=true:NoExecute
kubectl get pods -l app=evict-test -o wide -w
```

Pods on `worker2` will be evicted immediately and rescheduled on the other nodes.

Remove the taint and clean up:

```bash
kubectl taint node worker2 maintenance=true:NoExecute-
kubectl delete deployment evict-test
```
