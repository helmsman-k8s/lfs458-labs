# Chapter 5: API Access

## Overview

In this lab you will:

- Use TLS certificates to authenticate directly to the Kubernetes API
- Make raw HTTPS requests with `curl` using PEM certificates
- Use `kubectl proxy` and `kubectl port-forward` to access the API
- Trace API calls with `strace`

---

## Lab 5.1 — Authenticate with Certificates

### Locate the cluster CA and client certs

```bash
# Your kubeconfig already contains base64-encoded certs; decode them to files
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > /tmp/ca.crt

kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' \
  | base64 -d > /tmp/client.crt

kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}' \
  | base64 -d > /tmp/client.key
```

### Get the API server URL

```bash
API_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
echo "API server: $API_SERVER"
```

### Query the API with curl

```bash
# List nodes
curl --cacert /tmp/ca.crt \
     --cert /tmp/client.crt \
     --key /tmp/client.key \
     "$API_SERVER/api/v1/nodes" | python3 -m json.tool | head -30

# List namespaces
curl --cacert /tmp/ca.crt \
     --cert /tmp/client.crt \
     --key /tmp/client.key \
     "$API_SERVER/api/v1/namespaces" | python3 -m json.tool | head -30
```

---

## Lab 5.2 — Bearer Token Authentication

Find the token for the `default` service account:

```bash
SA_SECRET=$(kubectl get secret -n default \
  -o jsonpath='{.items[?(@.type=="kubernetes.io/service-account-token")].metadata.name}' \
  | awk '{print $1}')

TOKEN=$(kubectl get secret $SA_SECRET -n default \
  -o jsonpath='{.data.token}' | base64 -d)
echo "Token (first 60 chars): ${TOKEN:0:60}..."
```

Use the token to query the API:

```bash
curl --cacert /tmp/ca.crt \
     -H "Authorization: Bearer $TOKEN" \
     "$API_SERVER/api/v1/namespaces" | python3 -m json.tool | head -20
```

!!! note
    The `default` service account has limited permissions. You will see `403 Forbidden` for most resources — this is expected and demonstrates RBAC in action.

---

## Lab 5.3 — kubectl proxy

`kubectl proxy` opens a local HTTP proxy to the API server, handling authentication automatically:

```bash
# Start proxy in the background
kubectl proxy --port=8001 &
PROXY_PID=$!

# Query through the proxy (no auth needed)
curl http://localhost:8001/api/v1/nodes | python3 -m json.tool | head -20

# List available API groups
curl http://localhost:8001/apis | python3 -m json.tool | head -30

# Stop the proxy
kill $PROXY_PID
```

---

## Lab 5.4 — Trace kubectl with strace

Use `strace` to observe the system calls (including network calls) kubectl makes:

```bash
sudo apt-get install -y strace

# Trace kubectl get nodes and capture output
strace -e trace=network kubectl get nodes 2>&1 | head -40
```

Observe the `connect()` calls to the API server's IP and port (6443).

---

## Lab 5.5 — API Discovery

Explore the API resource groups available in your cluster:

```bash
# All API resources
kubectl api-resources | head -20

# Available API versions
kubectl api-versions | sort

# Explain a resource schema
kubectl explain pod.spec.containers.resources
```

Check the API server's health endpoints:

```bash
curl --cacert /tmp/ca.crt \
     --cert /tmp/client.crt \
     --key /tmp/client.key \
     "$API_SERVER/healthz"

curl --cacert /tmp/ca.crt \
     --cert /tmp/client.crt \
     --key /tmp/client.key \
     "$API_SERVER/readyz"
```

Both should return `ok`.
