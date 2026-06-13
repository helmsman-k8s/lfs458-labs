# Chapter 8: Helm and Kustomize

## Overview

In this lab you will:

- Install and use Helm to deploy an application from a chart
- Install `metrics-server` with Helm and configure it for insecure TLS (lab environment)
- Configure Horizontal Pod Autoscaling (HPA) and generate load with `siege`
- Use Kustomize to manage environment-specific configuration overlays

---

## Lab 8.1 — Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

Add a repository and search it:

```bash
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm search repo bitnami/nginx
```

---

## Lab 8.2 — Deploy an Application with Helm

Install an nginx chart into its own namespace:

```bash
kubectl create namespace helm-nginx
helm install my-nginx bitnami/nginx --namespace helm-nginx
```

Watch the pods come up:

```bash
kubectl get pods -n helm-nginx -w
```

Inspect what Helm created:

```bash
helm list -n helm-nginx
helm status my-nginx -n helm-nginx
kubectl get all -n helm-nginx
```

Clean up:

```bash
helm uninstall my-nginx -n helm-nginx
kubectl delete namespace helm-nginx
```

---

## Lab 8.3 — Install metrics-server

`metrics-server` is required for `kubectl top` and for HPA to function. In a lab environment, the kubelets use self-signed certificates, so you must pass `--kubelet-insecure-tls`.

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args="{--kubelet-insecure-tls}"
```

Wait for it to be ready:

```bash
kubectl rollout status deployment metrics-server -n kube-system --timeout=120s
```

Verify:

```bash
kubectl top nodes
kubectl top pods -A
```

---

## Lab 8.4 — Horizontal Pod Autoscaler

### Deploy a CPU-hungry application

```bash
kubectl create deployment php-apache \
  --image=registry.k8s.io/hpa-example
kubectl set resources deployment php-apache --requests=cpu=200m

kubectl expose deployment php-apache --port=80
```

Create the HPA:

```bash
kubectl autoscale deployment php-apache \
  --cpu=50% \
  --min=1 \
  --max=10

kubectl get hpa php-apache -w
```

### Generate load with siege

```bash
sudo apt-get install -y siege

PHP_SVC_IP=$(kubectl get svc php-apache -o jsonpath='{.spec.clusterIP}')
siege -c 20 -t 2M http://$PHP_SVC_IP &
SIEGE_PID=$!

# Watch HPA scale up
kubectl get hpa php-apache -w
```

Stop the load:

```bash
kill $SIEGE_PID 2>/dev/null
# HPA will scale back down after ~5 minutes
kubectl get hpa php-apache -w
```

### Clean up

```bash
kubectl delete hpa php-apache
kubectl delete deployment php-apache
kubectl delete svc php-apache
```

---

## Lab 8.5 — Kustomize

Kustomize is built into `kubectl`. Create a base application and two overlays (dev and prod).

### Create the base

```bash
mkdir -p ~/kustomize/base ~/kustomize/overlays/dev ~/kustomize/overlays/prod

cat <<EOF > ~/kustomize/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: nginx:1.25
EOF

cat <<EOF > ~/kustomize/base/kustomization.yaml
resources:
- deployment.yaml
EOF
```

### Create the dev overlay

```bash
cat <<EOF > ~/kustomize/overlays/dev/kustomization.yaml
resources:
- ../../base
patches:
- patch: |-
    - op: replace
      path: /spec/replicas
      value: 1
    - op: replace
      path: /spec/template/spec/containers/0/image
      value: nginx:1.25
  target:
    kind: Deployment
    name: myapp
namePrefix: dev-
EOF
```

### Create the prod overlay

```bash
cat <<EOF > ~/kustomize/overlays/prod/kustomization.yaml
resources:
- ../../base
patches:
- patch: |-
    - op: replace
      path: /spec/replicas
      value: 3
    - op: replace
      path: /spec/template/spec/containers/0/image
      value: nginx:1.26
  target:
    kind: Deployment
    name: myapp
namePrefix: prod-
EOF
```

### Preview and apply

```bash
# Preview what will be applied
kubectl kustomize ~/kustomize/overlays/dev
kubectl kustomize ~/kustomize/overlays/prod

# Apply dev
kubectl apply -k ~/kustomize/overlays/dev
kubectl get deployments | grep dev-myapp

# Apply prod
kubectl apply -k ~/kustomize/overlays/prod
kubectl get deployments | grep prod-myapp
```

### Clean up

```bash
kubectl delete -k ~/kustomize/overlays/dev
kubectl delete -k ~/kustomize/overlays/prod
```
