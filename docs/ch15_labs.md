# Chapter 15: Security

## Overview

In this lab you will:

- Create a new user with TLS certificates (DevDan)
- Configure RBAC: Roles, ClusterRoles, RoleBindings
- Restrict a namespace with a NetworkPolicy
- Explore Admission Controllers

Lab files are in `~/lfs458/ch15-security/`. The `solutions/` subfolder contains completed manifests.

---

## Lab 15.1 — Create a User with TLS Certificates

Kubernetes doesn't manage user accounts directly — users are identified by the Common Name (CN) in their TLS certificate, signed by the cluster CA.

### Generate a key and CSR for DevDan

```bash
mkdir -p ~/devdan
openssl genrsa -out ~/devdan/devdan.key 2048

openssl req -new \
  -key ~/devdan/devdan.key \
  -out ~/devdan/devdan.csr \
  -subj "/CN=devdan/O=developers"
```

### Submit a CertificateSigningRequest to Kubernetes

```bash
CSR_BASE64=$(cat ~/devdan/devdan.csr | base64 | tr -d '\n')

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: devdan
spec:
  request: $CSR_BASE64
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF
```

Approve the CSR:

```bash
kubectl certificate approve devdan
kubectl get csr devdan
```

Retrieve the signed certificate:

```bash
kubectl get csr devdan -o jsonpath='{.status.certificate}' | base64 -d > ~/devdan/devdan.crt
```

### Add DevDan to kubeconfig

```bash
kubectl config set-credentials devdan \
  --client-certificate=$HOME/devdan/devdan.crt \
  --client-key=$HOME/devdan/devdan.key

kubectl config set-context devdan-context \
  --cluster=$(kubectl config view -o jsonpath='{.clusters[0].name}') \
  --user=devdan

kubectl config get-contexts
```

Test that DevDan currently has no permissions:

```bash
kubectl get pods --context=devdan-context
```

You should see a `Forbidden` error.

---

## Lab 15.2 — RBAC: Role and RoleBinding

### Create a namespace for DevDan

```bash
kubectl create namespace prod
```

### Create a Role in the prod namespace

```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: prod
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
EOF
```

### Bind the Role to DevDan

> **Emergency fallback:** `kubectl apply -f ~/lfs458/ch15-security/solutions/rolebinding-devdan.yaml`

```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: devdan-pod-reader
  namespace: prod
subjects:
- kind: User
  name: devdan
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Test DevDan's access

```bash
# Update the devdan context to use the prod namespace
kubectl config set-context devdan-context \
  --namespace=prod \
  --cluster=$(kubectl config view -o jsonpath='{.clusters[0].name}') \
  --user=devdan

# DevDan can list pods in prod
kubectl get pods --context=devdan-context -n prod

# DevDan cannot create pods
kubectl run test --image=nginx --context=devdan-context -n prod
```

The last command should return `Forbidden`.

### Grant more permissions (edit the Role)

Edit the role to also allow creating pods. The solution is at `~/lfs458/ch15-security/solutions/role-prod-create.yaml`.

```bash
kubectl edit role pod-reader -n prod
# Add "create", "delete" to the verbs list
```

---

## Lab 15.3 — ClusterRole and ClusterRoleBinding

Create a read-only ClusterRole and bind it to DevDan cluster-wide:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-viewer
rules:
- apiGroups: [""]
  resources: ["nodes", "namespaces", "persistentvolumes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: devdan-cluster-viewer
subjects:
- kind: User
  name: devdan
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
```

Test:

```bash
kubectl get nodes --context=devdan-context
kubectl get namespaces --context=devdan-context
kubectl get secrets --context=devdan-context -n default  # Should be Forbidden
```

### Check permissions with auth can-i

```bash
kubectl auth can-i list pods --as=devdan -n prod
kubectl auth can-i create secrets --as=devdan -n prod
kubectl auth can-i get nodes --as=devdan
```

---

## Lab 15.4 — NetworkPolicy

By default, pods can communicate freely across namespaces. NetworkPolicies restrict this.

Create two namespaces and deploy pods:

```bash
kubectl create namespace frontend
kubectl create namespace backend

kubectl run frontend-pod --image=nginx -n frontend --labels=app=frontend
kubectl run backend-pod --image=nginx -n backend --labels=app=backend
```

Allow only the `frontend` namespace to reach `backend` on port 80:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
    ports:
    - protocol: TCP
      port: 80
EOF
```

Test connectivity:

```bash
BACKEND_IP=$(kubectl get pod backend-pod -n backend -o jsonpath='{.status.podIP}')
echo "Backend pod IP: $BACKEND_IP"

# From frontend — should work
kubectl exec -n frontend frontend-pod -- curl -s --max-time 5 http://$BACKEND_IP | head -5

# From default namespace — should be blocked
kubectl run testpod --image=busybox --rm -i --restart=Never -- \
  wget -O- --timeout=5 http://$BACKEND_IP
```

### Clean up

```bash
kubectl delete networkpolicy allow-frontend -n backend
kubectl delete pod frontend-pod -n frontend
kubectl delete pod backend-pod -n backend
kubectl delete namespace frontend backend
```

---

## Lab 15.5 — Clean Up

```bash
kubectl delete rolebinding devdan-pod-reader -n prod
kubectl delete role pod-reader -n prod
kubectl delete clusterrolebinding devdan-cluster-viewer
kubectl delete clusterrole cluster-viewer
kubectl delete namespace prod
kubectl delete csr devdan
kubectl config delete-context devdan-context
kubectl config delete-user devdan
```
