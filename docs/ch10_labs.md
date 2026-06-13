# Chapter 10: Services and Networking

## Overview

In this lab you will:

- Create a NodePort Service and test pod-to-service connectivity
- Inspect endpoints and understand how kube-proxy routes traffic
- Configure CoreDNS with a rewrite rule for a custom domain
- Use labels to manage Service traffic

Lab files are in `~/lfs458/ch10-services/`. The `solutions/` subfolder contains completed manifests for files you need to edit.

---

## Lab 10.1 — NodePort Service

### Deploy the application

```bash
cp ~/lfs458/ch10-services/nginx-one.yaml ~/nginx-one.yaml
cat ~/nginx-one.yaml
```

!!! warning "Fix the containerPort"
    The manifest has `containerPort: 8080` but nginx listens on **port 80**. Edit `~/nginx-one.yaml` and change it to `containerPort: 80` before applying. The solution is in `~/lfs458/ch10-services/solutions/nginx-one-port80.yaml`.

```bash
kubectl apply -f ~/nginx-one.yaml
kubectl get pods -l app=nginx-one -w
```

Once running:

```bash
POD=$(kubectl get pod -l app=nginx-one -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $POD | grep -E "IP:|Port:|Node:"
```

### Expose as a NodePort Service

```bash
kubectl expose pod $POD --name=nginx-one --port=80 --type=NodePort
```

Get the assigned port:

```bash
NODE_PORT=$(kubectl get svc nginx-one -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort: $NODE_PORT"
```

Test from any node:

```bash
curl http://controller:$NODE_PORT
curl http://worker1:$NODE_PORT
curl http://worker2:$NODE_PORT
```

### Inspect Endpoints

```bash
kubectl get endpoints nginx-one

ENDPOINT_IP=$(kubectl get endpoints nginx-one -o jsonpath='{.subsets[0].addresses[0].ip}')
echo "Pod endpoint IP: $ENDPOINT_IP"
curl http://$ENDPOINT_IP:80
```

### Clean up

```bash
kubectl delete svc nginx-one
kubectl delete pod $POD
```

---

## Lab 10.2 — Multi-pod Service with Labels

Create a Deployment and Service:

```bash
kubectl create deployment web --image=nginx --replicas=3
kubectl expose deployment web --port=80 --type=NodePort

NODE_PORT=$(kubectl get svc web -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort: $NODE_PORT"
curl http://controller:$NODE_PORT
```

Watch endpoint changes as you scale:

```bash
kubectl get endpoints web -w &
EP_WATCH=$!

kubectl scale deployment web --replicas=5
sleep 5

kubectl scale deployment web --replicas=1
sleep 5
kill $EP_WATCH
```

### Label-based traffic control

Add a second label to a specific pod and show how label selectors route traffic:

```bash
WEB_POD=$(kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.name}')

# Add an extra label
kubectl label pod $WEB_POD tier=canary

# Create a separate service selecting only the canary pod
kubectl expose pod $WEB_POD --name=web-canary --port=80 --type=NodePort \
  --selector="app=web,tier=canary"

CANARY_PORT=$(kubectl get svc web-canary -o jsonpath='{.spec.ports[0].nodePort}')
echo "Canary NodePort: $CANARY_PORT"
curl http://controller:$CANARY_PORT
```

### Clean up

```bash
kubectl delete deployment web
kubectl delete svc web web-canary
```

---

## Lab 10.3 — CoreDNS Custom Domain Rewrite

This exercise adds a CoreDNS rewrite rule so that `*.test.io` resolves to your cluster services via a wildcard.

Inspect the current CoreDNS ConfigMap:

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

Patch the Corefile to add a `rewrite` rule:

```bash
kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' > /tmp/Corefile.orig
cat /tmp/Corefile.orig
```

Add the rewrite rule before the `forward` block:

```bash
cat <<'EOF' > /tmp/Corefile.new
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    rewrite name suffix .test.io .default.svc.cluster.local answer auto
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
EOF

kubectl create configmap coredns -n kube-system \
  --from-file=Corefile=/tmp/Corefile.new \
  --dry-run=client -o yaml | kubectl apply -f -
```

Force CoreDNS pods to reload by deleting them (they will be recreated by the Deployment):

```bash
COREDNS_POD=$(kubectl get pod -n kube-system -l k8s-app=kube-dns \
  -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $COREDNS_POD -n kube-system

# Wait for the new pod
kubectl rollout status deployment coredns -n kube-system
```

Test the rewrite from inside a pod:

```bash
kubectl run dnstest --image=busybox --rm -it --restart=Never -- \
  nslookup kubernetes.test.io
```

This should resolve to the `kubernetes` ClusterIP service.

### Revert CoreDNS to the original config

```bash
kubectl create configmap coredns -n kube-system \
  --from-file=Corefile=/tmp/Corefile.orig \
  --dry-run=client -o yaml | kubectl apply -f -

COREDNS_POD=$(kubectl get pod -n kube-system -l k8s-app=kube-dns \
  -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $COREDNS_POD -n kube-system
kubectl rollout status deployment coredns -n kube-system
```
