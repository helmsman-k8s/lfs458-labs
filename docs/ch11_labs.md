# Chapter 11: Ingress and Gateway API

## Overview

In this lab you will:

- Install the NGINX Ingress Controller as a DaemonSet
- Create Ingress rules to route traffic to multiple backends
- Explore the Gateway API as the next-generation Ingress alternative

---

## Lab 11.1 — Install NGINX Ingress Controller

Deploy NGINX Ingress as a DaemonSet so it runs on every node:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
```

Wait for the controller to be ready:

```bash
kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx --timeout=120s
kubectl get pods -n ingress-nginx
```

Get the NodePort assigned to the ingress controller:

```bash
HTTP_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
HTTPS_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo "HTTP  NodePort: $HTTP_PORT"
echo "HTTPS NodePort: $HTTPS_PORT"
```

---

## Lab 11.2 — Create Ingress Rules

### Deploy two backend applications

```bash
kubectl create deployment app1 --image=nginx --replicas=2
kubectl expose deployment app1 --port=80

kubectl create deployment app2 --image=httpd --replicas=2
kubectl expose deployment app2 --port=80
```

### Create an Ingress resource

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apps-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: app1.vega.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1
            port:
              number: 80
  - host: app2.vega.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app2
            port:
              number: 80
EOF
```

### Test the Ingress

Add entries to `/etc/hosts` on the controller (or wherever you're running curl):

```bash
CONTROLLER_IP=$(kubectl get node controller -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
echo "$CONTROLLER_IP app1.vega.local app2.vega.local" | sudo tee -a /etc/hosts
```

Test:

```bash
HTTP_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

curl http://app1.vega.local:$HTTP_PORT
curl http://app2.vega.local:$HTTP_PORT
```

`app1` should return the nginx welcome page; `app2` should return the Apache (httpd) page.

### Clean up

```bash
kubectl delete ingress apps-ingress
kubectl delete deployment app1 app2
kubectl delete svc app1 app2
```

---

## Lab 11.3 — Gateway API

The Gateway API is the successor to Ingress. It separates infrastructure configuration (Gateway) from routing rules (HTTPRoute).

### Install Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
kubectl get crd | grep gateway
```

### Install NGINX Gateway Fabric

```bash
kubectl apply -f https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/v1.5.1/deploy/crds.yaml
kubectl apply -f https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/v1.5.1/deploy/nodeport/deploy.yaml

kubectl rollout status deployment nginx-gateway -n nginx-gateway --timeout=120s
```

Get the Gateway ports:

```bash
GW_HTTP=$(kubectl get svc nginx-gateway -n nginx-gateway \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
echo "Gateway HTTP NodePort: $GW_HTTP"
```

### Create a GatewayClass and Gateway

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx
spec:
  controllerName: gateway.nginx.org/nginx-gateway-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: default
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    port: 80
    protocol: HTTP
EOF
```

### Create a backend and HTTPRoute

```bash
kubectl create deployment gw-app --image=nginx
kubectl expose deployment gw-app --port=80

cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gw-app-route
spec:
  parentRefs:
  - name: main-gateway
  hostnames:
  - "gw-app.vega.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: gw-app
      port: 80
EOF
```

Test:

```bash
echo "$CONTROLLER_IP gw-app.vega.local" | sudo tee -a /etc/hosts
curl http://gw-app.vega.local:$GW_HTTP
```

### Clean up

```bash
kubectl delete httproute gw-app-route
kubectl delete gateway main-gateway
kubectl delete gatewayclass nginx
kubectl delete deployment gw-app
kubectl delete svc gw-app
```
