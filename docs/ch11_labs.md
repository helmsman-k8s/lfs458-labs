# Chapter 11: Ingress

**Working directory: `~/lfs458/ch11-ingress/`**

---

## Exercise 11.1: Service Mesh

A **service mesh** adds intelligent proxies to every pod, providing traffic management, observability, and security without code changes. We will install **Linkerd**, a lightweight service mesh, then inject it into an existing deployment and observe live traffic metrics.

```bash
cd ~/lfs458/ch11-ingress/
```

**1.** Install Linkerd using the official install script. There will be a lot of output — ensure everything shows a green check mark. Each command is listed separately here for clarity. These steps are also available in `setupLinkerd.txt`.

```bash
curl -sL run.linkerd.io/install-edge | sh
export PATH=$PATH:/home/guru/.linkerd2/bin
echo "export PATH=\$PATH:/home/guru/.linkerd2/bin" >> $HOME/.bashrc
linkerd check --pre
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/\
releases/download/v1.2.1/standard-install.yaml
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
linkerd viz install | kubectl apply -f -
linkerd viz check
linkerd viz dashboard &
```

**2.** The Linkerd dashboard starts on localhost by default. Edit the deployment to remove the `--enforced-host` restriction so it is accessible externally. Comment out line 11.

```bash
kubectl -n linkerd-viz edit deploy web
```

```yaml
spec:
  containers:
    - args:
      - -linkerd-controller-api-addr=linkerd-controller-api.linkerd.svc.cluster.local:8085
      - -linkerd-metrics-api-addr=metrics-api.linkerd-viz.svc.cluster.local:8085
      - -cluster-domain=cluster.local
      - -grafana-addr=grafana.linkerd-viz.svc.cluster.local:3000
      - -controller-namespace=linkerd
      - -viz-namespace=linkerd-viz
      - -log-level=info
      # - -enforced-host=                     #<-- Comment out this line
      image: cr.l5d.io/linkerd/web:stable-2.11.1
```

**3.** Edit the `web` service in the `linkerd-viz` namespace to expose it as a NodePort on a memorable port.

```bash
kubectl edit svc web -n linkerd-viz
```

```yaml
....
ports:
  - name: http
    nodePort: 31500           #<-- Add this line
    port: 8084
....
  sessionAffinity: None
  type: NodePort              #<-- Edit type to NodePort
....
```

**4.** Find the public IP of your node and open the Linkerd dashboard in a browser.

```bash
curl ifconfig.io
```

Browse to: `http://<your-public-ip>:31500`

**5.** Ensure the `accounting` namespace still exists and the `nginx-one` deployment is running. Re-label the worker1 node and re-apply the deployment if needed.

```bash
kubectl get ns accounting
kubectl label node worker1 system=secondOne
vim nginx-one.yaml       ## Ensure containerPort: 80 (not 8080)
kubectl apply -f nginx-one.yaml
```

**6.** Inject the Linkerd sidecar proxy into the `nginx-one` deployment by piping its YAML through `linkerd inject`.

```bash
kubectl -n accounting get deploy nginx-one -o yaml | \
  linkerd inject - | kubectl apply -f -
```

```
<output_omitted>
```

**7.** Check the Linkerd dashboard — the `accounting` namespace should now show pods as meshed.

**8.** Generate traffic to view live metrics. Use the `service-lab` ClusterIP.

```bash
kubectl -n accounting get svc
```

```
NAME          TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)
nginx-one     ClusterIP   10.107.141.227   <none>        8080/TCP
service-lab   NodePort    10.102.8.205     <none>        80:30759/TCP
```

```bash
SVC_IP=$(kubectl -n accounting get svc service-lab -o jsonpath='{.spec.clusterIP}')
curl $SVC_IP
```

**9.** Scale up the `nginx-one` deployment and generate more traffic to see per-pod metrics.

```bash
kubectl -n accounting scale deploy nginx-one --replicas=5
curl $SVC_IP   # Run several times
```

**10.** Explore the Linkerd dashboard — change the namespace to `accounting` to see per-deployment and per-pod metrics including success rates, RPS, and latencies.

---

## Exercise 11.2: Ingress Controller

An **Ingress Controller** is a Pod that watches `Ingress` resources and configures a proxy (such as NGINX) to route external HTTP traffic to services based on hostname or path rules.

**1.** Create two nginx deployments and expose them as ClusterIP services. Verify both ClusterIPs respond before continuing.

```bash
kubectl create deployment web-one --image=nginx
kubectl expose deployment web-one --port=80

kubectl create deployment web-two --image=nginx
kubectl expose deployment web-two --port=80

kubectl get svc web-one web-two
curl <web-one-cluster-ip>
curl <web-two-cluster-ip>
```

**2.** Search for available ingress controllers on ArtifactHub.

```bash
helm search hub ingress
```

**3.** Add the NGINX ingress controller Helm repository.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

**4.** Download and extract the chart to edit `values.yaml` before installing. Change the controller kind from `Deployment` to `DaemonSet` so a controller pod runs on every node.

```bash
helm fetch ingress-nginx/ingress-nginx --untar
cd ingress-nginx
vim values.yaml
```

```yaml
....
  ## DaemonSet or Deployment
  ##
  kind: DaemonSet        #<-- Change to DaemonSet (around line 204)
....
```

**5.** Install the ingress controller from the local chart directory.

```bash
helm install myingress .
```

```
NAME: myingress
LAST DEPLOYED: Thu Aug 23 13:47:16 2024
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
The ingress-nginx controller has been installed.
<output_omitted>
```

**6.** Verify no ingress rules exist yet, then watch the ingress controller service until it gets an IP (use `Ctrl+C` to quit the watch).

```bash
kubectl get ingress --all-namespaces
```

```
No resources found
```

```bash
kubectl --namespace default get services -o wide \
  myingress-ingress-nginx-controller
```

```
NAME                                TYPE           CLUSTER-IP      EXTERNAL-IP
myingress-ingress-nginx-controller  LoadBalancer   10.104.227.79   <pending>
```

```bash
kubectl get pod --all-namespaces | grep nginx
```

```
default   myingress-ingress-nginx-controller-mrqt5   1/1   Running   0   20s
default   myingress-ingress-nginx-controller-pkdxm   1/1   Running   0   62s
default   nginx-b68dd9f75-h6ww7                      1/1   Running   0   21h
```

**7.** The `ingress.yaml` file is pre-staged in your lab folder. Review it — it routes traffic with `Host: www.external.com` to the `web-one` service.

```bash
cat ~/lfs458/ch11-ingress/ingress.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-test
  annotations:
    nginx.ingress.kubernetes.io/service-upstream: "true"
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: www.external.com
    http:
      paths:
      - backend:
          service:
            name: web-one
            port:
              number: 80
        path: /
        pathType: ImplementationSpecific
```

**8.** First get the ingress controller pod IP on the controller node, then create the Ingress.

```bash
INGRESS_IP=$(kubectl get pods -o wide | grep myingress-ingress-nginx-controller | grep "controller" | awk '{print $6}')
echo $INGRESS_IP
```

**8.** Create the Ingress and verify it is active. Without a matching Host header you get a 404.

```bash
kubectl create -f ingress.yaml
```

```
ingress.networking.k8s.io/ingress-test created
```

```bash
kubectl get ingress
```

```
NAME           CLASS   HOSTS             ADDRESS   PORTS   AGE
ingress-test   nginx   www.external.com            80      5s
```

```bash
# Get the ingress controller pod IP on the controller node:
kubectl get pods -o wide | grep myingress-ingress-nginx-controller | grep " controller "
```

```
myingress-ingress-nginx-controller-mrqt5   1/1   Running   0   8m9s   10.244.0.x   controller
myingress-ingress-nginx-controller-pkdxm   1/1   Running   0   8m9s   10.244.x.x     worker1
```

```bash
curl http://$INGRESS_IP
```

```html
<html>
<head><title>404 Not Found</title></head>
...
```

**9.** Pass the correct `Host` header — traffic is now routed to `web-one` and you see the nginx welcome page.

```bash
curl -H "Host: www.external.com" http://$INGRESS_IP
```

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

**10.** Inject the Linkerd mesh annotation into the ingress controller DaemonSet (some warnings are expected but the command will work).

```bash
kubectl get ds myingress-ingress-nginx-controller -o yaml | \
  linkerd inject --ingress - | kubectl apply -f -
```

```
daemonset "myingress-ingress-nginx-controller" injected
daemonset.apps/myingress-ingress-nginx-controller configured
```

**11.** In the Linkerd dashboard go to **Tools → Top**, change namespace to `default` and resource to `daemonset/myingress-ingress-nginx-controller`. Press Start then generate more traffic to see ingress metrics.

**12.** Customise the `web-two` pod's nginx welcome page to distinguish it from `web-one`.

```bash
kubectl exec -it web-two-<Tab> -- /bin/bash
```

> Inside the container:

```bash
apt-get update
apt-get install vim -y
vim /usr/share/nginx/html/index.html
```

Edit the `<title>` line:

```html
<title>Internal Welcome Page</title>   #<-- Edit this line
```

```bash
exit
```

**13.** Add a second host rule to the Ingress pointing `internal.org` to `web-two`.

```bash
kubectl edit ingress ingress-test
```

```yaml
spec:
  rules:
  - host: internal.org
    http:
      paths:
      - backend:
          service:
            name: web-two
            port:
              number: 80
        path: /
        pathType: ImplementationSpecific
  - host: www.external.com
    http:
      paths:
      - backend:
          service:
            name: web-one
            port:
              number: 80
        path: /
        pathType: ImplementationSpecific
```

**14.** Test the second host rule — the page title should show "Internal Welcome Page".

```bash
curl -H "Host: internal.org" http://<ingress-controller-pod-ip>/
```

```html
<!DOCTYPE html>
<html>
<head>
<title>Internal Welcome Page</title>
...
```

---

## Exercise 11.3: Gateway API

The **Gateway API** is the modern successor to Ingress, with better role separation, native support for advanced routing, and a vendor-neutral spec. We will install NGINX Gateway Fabric and route traffic using a `Gateway` and `HTTPRoute`.

**1.** Install the Gateway API CRDs.

```bash
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/\
  config/crd/gateway-api/standard-ref=v1.6.1" | kubectl apply -f -
```

```
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io created
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io created
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io configured
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io configured
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io created
```

**2.** Deploy the NGINX Gateway Fabric CRDs.

```bash
kubectl apply -f https://raw.githubusercontent.com/nginx/\
  nginx-gateway-fabric/v1.6.1/deploy/crds.yaml
```

```
customresourcedefinition.apiextensions.k8s.io/clientsettingspolicies.gateway.nginx.org created
customresourcedefinition.apiextensions.k8s.io/nginxgateways.gateway.nginx.org created
<output_omitted>
```

**3.** Deploy the NGINX Gateway Fabric itself.

```bash
kubectl apply -f https://raw.githubusercontent.com/nginx/\
  nginx-gateway-fabric/v1.6.1/deploy/default/deploy.yaml
```

```
namespace/nginx-gateway created
serviceaccount/nginx-gateway created
clusterrole.rbac.authorization.k8s.io/nginx-gateway created
clusterrolebinding.rbac.authorization.k8s.io/nginx-gateway created
configmap/nginx-includes-bootstrap created
service/nginx-gateway created
deployment.apps/nginx-gateway created
gatewayclass.gateway.networking.k8s.io/nginx created
nginxgateway.gateway.nginx.org/nginx-gateway-config created
```

**4.** Verify the NGINX Gateway Fabric is running.

```bash
kubectl get all -n nginx-gateway
```

```
NAME                                READY   STATUS    RESTARTS   AGE
pod/nginx-gateway-7c59cd4cc6-5m84b  2/2     Running   0          92s

NAME                    TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)
service/nginx-gateway   LoadBalancer   10.111.70.106    <pending>     80:32500/TCP,443:32730/TCP

NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx-gateway   1/1     1            1           92s
```

**5.** The service is `LoadBalancer` type with `EXTERNAL-IP: <pending>`. Patch it to `NodePort` for lab access.

```bash
kubectl patch service/nginx-gateway -n nginx-gateway \
  -p '{"spec": {"type": "NodePort"}}'

kubectl get service/nginx-gateway -n nginx-gateway
```

```
NAME            TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)
nginx-gateway   NodePort   10.111.70.106    <none>        80:32500/TCP,443:32730/TCP
```

**6.** Deploy the `books` application (Deployment + Service). The `books.yaml` file is pre-staged in your lab folder.

```bash
cat ~/lfs458/ch11-ingress/books.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: books
spec:
  replicas: 2
  selector:
    matchLabels:
      app: books
  template:
    metadata:
      labels:
        app: books
    spec:
      containers:
      - name: books
        image: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: books
spec:
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: books
```

```bash
kubectl create -f books.yaml
```

```
deployment.apps/books created
service/books created
```

**7.** Verify the books deployment and service are running.

```bash
kubectl get svc/books deploy/books
```

```
NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/books    ClusterIP   10.111.164.248   <none>        80/TCP    2m57s

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/books   2/2     2            2           2m57s
```

**8.** Review the pre-staged `gateway.yaml` — it creates a Gateway named `shop` using the `nginx` GatewayClass, listening on port 80.

```bash
cat ~/lfs458/ch11-ingress/gateway.yaml
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shop
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    port: 80
    protocol: HTTP
```

```bash
kubectl create -f gateway.yaml
```

```
gateway.gateway.networking.k8s.io/shop created
```

**9.** Verify the Gateway is programmed and ready.

```bash
kubectl get gateway
```

```
NAME   CLASS   ADDRESS   PROGRAMMED   AGE
shop   nginx             True         2m9s
```

**10.** Review the pre-staged `httproute.yaml` — it routes all traffic for `shop.example.com` to the `books` service.

```bash
cat ~/lfs458/ch11-ingress/httproute.yaml
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: books
spec:
  parentRefs:
  - name: shop
  hostnames:
  - "shop.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: books
      port: 80
```

```bash
kubectl create -f httproute.yaml
```

```
httproute.gateway.networking.k8s.io/books created
```

**11.** Verify the HTTPRoute is deployed.

```bash
kubectl get httproute
```

```
NAME    HOSTNAMES               AGE
books   ["shop.example.com"]    35s
```

**12.** Get the nginx-gateway pod IP first, then test routing.

```bash
GW_IP=$(kubectl get pods -n nginx-gateway -o jsonpath='{.items[0].status.podIP}')
echo $GW_IP
```

**12.** Test the Gateway API routing. Use `--resolve` to map the hostname to the node IP and the NodePort. Get the node IP with `hostname -i`.

```bash
curl --resolve shop.example.com:80:$GW_IP \
  http://shop.example.com/
```

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

**13.** Verify hostname-based routing is enforced — requests to a different hostname return 404.

```bash
curl --resolve test.example.com:80:$GW_IP \
  http://test.example.com/
```

```html
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

---
