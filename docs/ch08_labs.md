# Chapter 8: Helm and Kustomize

**Working directory: `~/lfs458/ch08-helm/`**

---

## Exercise 8.1: Working with Helm and Charts

**Helm** allows easy deployment of complex multi-part applications using a `Chart` — a collection of template files. Once installed you can list, upgrade, roll back, and delete releases.

```bash
cd ~/lfs458/ch08-helm/
```

---

### Install Helm

**1.** Download the Helm binary using `wget`. Check https://github.com/helm/helm/releases for the latest version.

```bash
wget https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz
```

```
helm-v3.19.0-linux-amd64.tar.gz 100%[===================>] 17.18M
2025-10-18 13:38:09 (101 MB/s) - 'helm-v3.19.0-linux-amd64.tar.gz' saved
```

**2.** Extract the archive.

```bash
tar -xvf helm-v3.19.0-linux-amd64.tar.gz
```

```
linux-amd64/
linux-amd64/helm
linux-amd64/README.md
linux-amd64/LICENSE
```

**3.** Copy the `helm` binary to your PATH.

```bash
sudo cp linux-amd64/helm /usr/local/bin/helm
```

**4.** Search for available charts on ArtifactHub.

```bash
helm search hub database
```

```
URL                                               CHART VERSION   APP VERSION   DESCRIPTION
https://artifacthub.io/packages/helm/drycc/data...   1.0.2
                                                  A PostgreSQL database used by Drycc Workflow.
<output_omitted>
```

**5.** Add an external repository. We will use the `ealenn` repository which has a useful echo server chart.

```bash
helm repo add ealenn https://ealenn.github.io/charts
```

```
"ealenn" has been added to your repositories
```

```bash
helm repo update
```

```
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ealenn" chart repository
Update Complete.  Happy Helming!
```

**6.** Install the `tester` release using the `ealenn/echo-server` chart. The `--debug` flag provides detailed output including how to access the application.

```bash
helm upgrade -i tester ealenn/echo-server --debug
```

```
history.go:56: [debug] getting history for release tester
Release "tester" does not exist. Installing it now.
install.go:173: [debug] Original chart version: ""
install.go:190: [debug] CHART PATH: /home/guru/.cache/helm/repository/echo-server-0.5.0.tgz
client.go:122: [debug] creating 4 resource(s)
NAME: tester
<output_omitted>
```

**7.** Ensure the `tester-echo-server` pod is running. Fix any issues if not.

```bash
kubectl get pods
```

```
NAME                                  READY   STATUS    RESTARTS   AGE
tester-echo-server-xxxxxxx-xxxxx      1/1     Running   0          30s
```

**8.** Find the ClusterIP of the service and send a `curl` request. You should get a large JSON response showing request details.

```bash
kubectl get svc
```

```
NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes           ClusterIP   10.96.0.1       <none>        443/TCP   26h
tester-echo-server   ClusterIP   10.98.252.11    <none>        80/TCP    11m
```

```bash
# If ClusterIP is unreachable from the node, curl the pod IP directly:
POD_IP=$(kubectl get pods -l app.kubernetes.io/instance=tester -o jsonpath='{.items[0].status.podIP}')
curl $POD_IP
```

```json
{"host":{"hostname":"10.98.252.11","ip":"::ffff:192.168.74.128","ips":
[]},"http":{"method":"GET","baseUrl":"","originalUrl":"/","protocol":
"http"},"request":{"params":{"0":"/"},"query":{},"cookies":{},"body":
{},"headers":{"host":"10.98.252.11","user-agent":"curl/7.58.0","accept":
"*/*"}},"environment":{"PATH":"/usr/local/sbin:/usr/local/bin:/usr/sbin:
<output_omitted>
```

**9.** View the chart history. The `-a` flag shows all charts including deleted and failed attempts.

```bash
helm list
```

```
NAME     NAMESPACE   REVISION   UPDATED                                   STATUS    CHART               APP VERSION
tester   default     1          2025-10-19 13:42:38.262327888 +0000 UTC   deployed  echo-server-0.5.0   0.6.0
```

**10.** Uninstall the `tester` chart. Verify it is no longer listed.

```bash
helm uninstall tester
```

```
release "tester" uninstalled
```

```bash
helm list
```

```
NAME   NAMESPACE   REVISION   UPDATED   STATUS   CHART   APP VERSION
```

**11.** Find the cached chart tarball under the home directory.

```bash
find $HOME -name *echo*
```

```
/home/guru/.cache/helm/repository/echo-server-0.5.0.tgz
```

**12.** Move to the cache directory and extract the tarball to explore the chart structure.

```bash
cd $HOME/.cache/helm/repository
tar -xvf echo-server-*
```

```
echo-server/Chart.yaml
echo-server/values.yaml
echo-server/templates/_helpers.tpl
echo-server/templates/configmap.yaml
echo-server/templates/deployment.yaml
<output_omitted>
```

**13.** Examine the `values.yaml` file to understand the configurable parameters.

```bash
cat echo-server/values.yaml
```

```
<output_omitted>
```

**14.** Add the metrics-server repository and download its chart to explore it.

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm fetch metrics-server/metrics-server --untar
cd metrics-server/
```

**15.** View the chart structure.

```bash
ls
```

```
Chart.lock  Chart.yaml  README.md  charts  ci  files  templates
values.schema.json  values.yaml
```

**16.** Review the `values.yaml` file. Find the `defaultArgs` section and add `--kubelet-insecure-tls` — this is required for our lab environment.

```bash
less values.yaml
```

```yaml
# Default values for metrics-server.
image:
  repository: registry.k8s.io/metrics-server/metrics-server
defaultArgs:
  - --cert-dir=/tmp
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  - --kubelet-use-node-status-port
  - --metric-resolution=15s
  - --kubelet-insecure-tls    #  <---- add this line
<output_omitted>
```

**17.** Install the metrics-server using the local `values.yaml`, deploying it into `kube-system`.

```bash
helm install metrics-server . -n kube-system
```

```
NAME: metrics-server
LAST DEPLOYED: Tue Oct 21 11:09:16 2025
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
* Metrics Server
<output_omitted>
```

**18.** Verify the metrics server pod is running and that `kubectl top` now works.

```bash
kubectl get pods -n kube-system | grep metrics
```

```
metrics-server-799f7ccf68-b9t8d   1/1   Running   0   2m38s
```

```bash
kubectl top nodes
```

```
NAME     CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
controller       202m         10%      1156Mi          14%
worker1   41m          2%       717Mi           9%
```

> Leave the metrics-server running — it is required for Exercise 8.2.

---

## Exercise 8.2: Horizontal Pod Autoscaler (HPA)

The **Horizontal Pod Autoscaler (HPA)** automatically adjusts the number of Pod replicas based on observed CPU utilisation. It requires the metrics-server to be running.

**1.** The `hpa-deploy.yaml` file is already staged in your lab folder. Review it — it defines a Deployment and a Service for a CPU-intensive test application.

```bash
cat ~/lfs458/ch08-helm/hpa-deploy.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hpa-app
  template:
    metadata:
      labels:
        app: hpa-app
    spec:
      containers:
      - name: web
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 5m
          limits:
            cpu: 10m
---
apiVersion: v1
kind: Service
metadata:
  name: hpa-app
spec:
  type: ClusterIP
  selector:
    app: hpa-app
  ports:
  - port: 80
    targetPort: 80
```

**2.** Create the Deployment and Service.

```bash
kubectl create -f ~/lfs458/ch08-helm/hpa-deploy.yaml
```

```
deployment.apps/hpa-app created
service/hpa-app created
```

**3.** Verify all resources are running. Both Pods should be on different nodes.

```bash
kubectl get deploy,rs,pods,svc -o wide
```

```
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS   IMAGES
deployment.apps/hpa-app   2/2     2            2           2m6s   web          registry.k8s.io/hpa-example

NAME                                DESIRED   CURRENT   READY   AGE    SELECTOR
replicaset.apps/hpa-app-844785cc56  2         2         2       2m6s   app=hpa-app

NAME                          READY   STATUS    RESTARTS   AGE    IP             NODE
pod/hpa-app-844785cc56-djrtq  1/1     Running   0          2m6s   192.168.0.1    controller
pod/hpa-app-844785cc56-zbklc  1/1     Running   0          2m6s   192.168.1.68   worker1

NAME                  TYPE        CLUSTER-IP       PORT(S)    AGE
service/hpa-app       ClusterIP   10.107.208.86    80/TCP     2m6s
service/kubernetes    ClusterIP   10.96.0.1        443/TCP    20m
```

**4.** Generate the HPA YAML using `--dry-run=client`. The HPA targets 50% CPU utilisation with a minimum of 2 and maximum of 10 replicas.

```bash
kubectl autoscale deployment hpa-app \
  --cpu-percent=50 --min=2 --max=10 \
  --dry-run=client -o yaml > hpa.yaml
cat hpa.yaml
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
...
```

**5.** Apply the HPA and verify it is being tracked. The `TARGETS` column will show `0%/50%` until load is detected.

```bash
kubectl apply -f hpa.yaml
kubectl get hpa
```

```
NAME      REFERENCE              TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
hpa-app   Deployment/hpa-app    cpu: 20%/50%   2         10        2          33s
```

**6.** In a **second terminal**, install `siege` and run a 2-minute load test against the service ClusterIP. Use the IP from your `kubectl get svc` output.

```bash
sudo apt-get update && sudo apt-get install -y siege
siege -q -c 5 -t 2m http://<hpa-app-cluster-ip>
```

**7.** In the **first terminal**, watch the HPA scale up as CPU usage rises above 50%.

```bash
watch kubectl get hpa
```

```
NAME      REFERENCE              TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
hpa-app   Deployment/hpa-app    210%/50%        2         10        6          3m
```

**8.** Watch the Pods scale dynamically across both nodes.

```bash
watch kubectl get pods -o wide
```

```
NAME                          READY   STATUS    RESTARTS   AGE   NODE
hpa-app-6d7d9c7c9c-hbw9t      1/1     Running   0          6m    worker1
hpa-app-6d7d9c7c9c-8qj9d      1/1     Running   0          2m    controller
hpa-app-6d7d9c7c9c-7k2h4      1/1     Running   0          1m    worker1
...
```

**9.** Once the load test finishes (`Ctrl+C` in the siege window), the HPA will gradually scale back down. Scaling down is intentionally slower to avoid oscillation.

```bash
watch kubectl get hpa
```

```
NAME      REFERENCE              TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
hpa-app   Deployment/hpa-app    cpu: 20%/50%   2         10        10         7m20s
```

> Scaling down to 2 replicas may take several minutes after load stops.

**10.** Troubleshooting tips if HPA shows `<unknown>` metrics:
- Ensure `metrics-server` is healthy: `kubectl get pods -n kube-system | grep metrics`
- Verify the container defines a `cpu` request (HPA uses requests, not limits)
- Check live usage: `kubectl top pods`

**11.** Clean up all resources.

```bash
kubectl delete -f hpa.yaml -f ~/lfs458/ch08-helm/hpa-deploy.yaml
```

```
horizontalpodautoscaler.autoscaling "hpa-app" deleted from default namespace
deployment.apps "hpa-app" deleted from default namespace
service "hpa-app" deleted from default namespace
```

---

## Exercise 8.3: Working with Kustomize

**Kustomize** is built into `kubectl` and allows you to customise Kubernetes configurations using a base/overlay pattern — no templating language required.

```bash
cd ~/lfs458/ch08-helm/
```

**1.** Verify kustomize is available as part of kubectl.

```bash
kubectl kustomize --help
```

```
Build a set of KRM resources using a 'kustomization.yaml' file. The DIR
argument must be a path to a directory containing 'kustomization.yaml',
or a git repository URL with a path suffix specifying same with respect
to the repository root. If DIR is omitted, '.' is assumed.

Examples:
  # Build the current working directory
  kubectl kustomize
...
<output_omitted>
```

**2.** Create the directory structure for a base and two overlay environments.

```bash
mkdir -p myapp/base myapp/overlays/dev myapp/overlays/prod
tree myapp
```

```
myapp
|--base
|-- overlays
    |-- dev
    |-- prod
```

**3.** Copy the base and overlay resource files from the Solutions folder.

```bash
cp ~/lfs458/ch08-helm/kustomize-base/* myapp/base/
cp ~/lfs458/ch08-helm/kustomize-dev/* myapp/overlays/dev/
cp ~/lfs458/ch08-helm/kustomize-prod/* myapp/overlays/prod/
```

> If the kustomize files are not pre-staged, rename the solution files: files ending in `.yaml-base` go to `base/`, `.yaml-dev` to `overlays/dev/`, `.yaml-prod` to `overlays/prod/`, stripping the suffix.

**4.** Rename the manifest files in the base directory.

```bash
cd myapp/base
for file in *.yaml-base; do mv "$file" "${file/-base/}"; done
ls *.yaml
```

```
deployment.yaml  kustomization.yaml  service.yaml
```

**5.** Rename the manifest files in the overlays/dev directory.

```bash
cd ../overlays/dev
for file in *.yaml-dev; do mv "$file" "${file/-dev/}"; done
ls *.yaml
```

```
deployment-patch.yaml  kustomization.yaml  service-patch.yaml
```

**6.** Rename the manifest files in the overlays/prod directory.

```bash
cd ../prod
for file in *.yaml-prod; do mv "$file" "${file/-prod/}"; done
ls *.yaml
```

```
deployment-patch.yaml  kustomization.yaml  service-patch.yaml
```

**7.** Return to the home directory and verify the full directory structure.

```bash
cd
tree myapp
```

```
myapp
|-- base
|   |-- deployment.yaml
|   |-- kustomization.yaml
|   `-- service.yaml
|-- overlays
    |-- dev
    |   |-- deployment-patch.yaml
    |   |-- kustomization.yaml
    |   `-- service-patch.yaml
    `-- prod
        |-- deployment-patch.yaml
        |-- kustomization.yaml
        `-- service-patch.yaml

5 directories, 9 files
```

**8.** Review the base `kustomization.yaml`. It sets a `namePrefix`, lists the resources, adds a common label, and injects it into selectors.

```bash
vim myapp/base/kustomization.yaml
```

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namePrefix: lf-
resources:
- deployment.yaml
- service.yaml
labels:
- includeSelectors: true
  pairs:
    company: linux-foundation
```

**9.** Preview the output for each environment before applying. Notice how each overlay applies different patches on top of the base.

```bash
kubectl kustomize myapp/base
kubectl kustomize myapp/overlays/dev
kubectl kustomize myapp/overlays/prod
```

**10.** Apply the base configuration to the cluster.

```bash
kubectl apply -k myapp/base/
```

```
service/lf-myapp created
deployment.apps/lf-myapp created
```

**11.** Verify all resources have been deployed with the injected label.

```bash
kubectl get all -l company=linux-foundation
```

```
NAME                              READY   STATUS    RESTARTS   AGE
pod/lf-myapp-5b68c7d779-ngsq4     1/1     Running   0          3m23s
pod/lf-myapp-5b68c7d779-z8pth     1/1     Running   0          3m23s

NAME                TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/lf-myapp    ClusterIP   10.104.21.181    <none>        80/TCP    3m23s

NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/lf-myapp    2/2     2            2           3m23s

NAME                                   DESIRED   CURRENT   READY   AGE
replicaset.apps/lf-myapp-5b68c7d779    2         2         2       3m23s
```

**12.** Apply the dev overlay patch on top of the running base.

```bash
kubectl apply -k myapp/overlays/dev/
```

```
service/lf-myapp configured
deployment.apps/lf-myapp configured
```

**13.** Verify the resources have been updated according to the dev overlay configuration.

**14.** Clean up all resources created by the overlay.

```bash
kubectl delete -k myapp/overlays/dev/
```

```
service "lf-myapp" deleted
deployment.apps "lf-myapp" deleted
```

---
