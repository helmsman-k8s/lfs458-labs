# Chapter 13: Troubleshooting

## Overview

In this lab you will:

- Locate and read Kubernetes component logs
- Use `kubectl top` and `metrics-server`
- Deploy and access the Kubernetes Dashboard
- Practice common troubleshooting patterns

---

## Lab 13.1 — Component Logs

Kubernetes control plane components run as static pods (manifests in `/etc/kubernetes/manifests/`). Their logs are accessible via `kubectl` or `journalctl`.

### API Server logs

```bash
API_POD=$(kubectl get pod -n kube-system -l component=kube-apiserver \
  -o jsonpath='{.items[0].metadata.name}')
kubectl logs $API_POD -n kube-system | tail -20
```

### Scheduler logs

```bash
SCHED_POD=$(kubectl get pod -n kube-system -l component=kube-scheduler \
  -o jsonpath='{.items[0].metadata.name}')
kubectl logs $SCHED_POD -n kube-system | tail -20
```

### Controller Manager logs

```bash
CM_POD=$(kubectl get pod -n kube-system -l component=kube-controller-manager \
  -o jsonpath='{.items[0].metadata.name}')
kubectl logs $CM_POD -n kube-system | tail -20
```

### etcd logs

```bash
ETCD_POD=$(kubectl get pod -n kube-system -l component=etcd \
  -o jsonpath='{.items[0].metadata.name}')
kubectl logs $ETCD_POD -n kube-system | tail -20
```

### kubelet logs (host systemd unit)

On each node, kubelet runs as a systemd service (not a pod):

```bash
sudo journalctl -u kubelet --since "10 minutes ago" | tail -30
```

### Locate log files

Control plane pod logs are also written to disk:

```bash
sudo ls /var/log/pods/ | grep kube-system
```

---

## Lab 13.2 — kubectl top

`metrics-server` must be installed (covered in Ch08). If it's running:

```bash
kubectl top nodes
kubectl top pods -A --sort-by=cpu | head -20
```

Watch a specific namespace:

```bash
kubectl top pods -n kube-system --sort-by=memory
```

---

## Lab 13.3 — Troubleshooting a Broken Pod

Create a pod with an intentional error:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: broken-pod
spec:
  containers:
  - name: app
    image: nginx:doesnotexist
EOF
```

Observe the failure:

```bash
kubectl get pod broken-pod
kubectl describe pod broken-pod | grep -A10 Events
```

Look at the image pull error in the `Events` section. Fix it:

```bash
kubectl patch pod broken-pod -p '{"spec":{"containers":[{"name":"app","image":"nginx:latest"}]}}'
# Patching running pods has limitations; for a real fix, delete and recreate
kubectl delete pod broken-pod

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: broken-pod
spec:
  containers:
  - name: app
    image: nginx:latest
EOF

kubectl get pod broken-pod -w
```

Clean up:

```bash
kubectl delete pod broken-pod
```

---

## Lab 13.4 — Kubernetes Dashboard

Deploy the Dashboard:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
kubectl rollout status deployment kubernetes-dashboard -n kubernetes-dashboard --timeout=120s
```

Create a ServiceAccount and ClusterRoleBinding to access the dashboard:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-admin
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: dashboard-admin
  namespace: kubernetes-dashboard
EOF
```

Get the login token:

```bash
kubectl create token dashboard-admin -n kubernetes-dashboard
```

Access the dashboard via `kubectl proxy`:

```bash
kubectl proxy --address=0.0.0.0 --accept-hosts='.*' &
echo "Dashboard URL: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
```

Open the URL in a browser and log in with the token.

### Clean up

```bash
kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
kubectl delete clusterrolebinding dashboard-admin-binding
kubectl delete serviceaccount dashboard-admin -n kubernetes-dashboard 2>/dev/null; true
```

---

## Lab 13.5 — Common Troubleshooting Patterns

| Symptom | Where to look |
|---------|--------------|
| Pod stuck in `Pending` | `kubectl describe pod` → Events; check resource requests, taints, node capacity |
| Pod in `CrashLoopBackOff` | `kubectl logs <pod>` and `kubectl logs <pod> --previous` |
| Pod in `ImagePullBackOff` | `kubectl describe pod` → check image name/tag and registry credentials |
| Node `NotReady` | `sudo journalctl -u kubelet` on the node; check CNI health |
| Service not routing | `kubectl get endpoints <svc>` — if empty, label selector doesn't match any pods |
| DNS not resolving | `kubectl exec <pod> -- nslookup kubernetes.default`; check CoreDNS pods |

```bash
# Quick cluster health overview
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```
