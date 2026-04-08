# Chapter 13: Logging and Troubleshooting

**Working directory: `~/lfs458/ch13-troubleshoot/`**

---

## Exercise 13.1: Review Log File Locations

Kubernetes distributes logs across nodes and containers. In this exercise we identify the key log locations and understand how to access them.

```bash
cd ~/lfs458/ch13-troubleshoot/
```

**1.** View the **kubelet** service logs using `journalctl`. The kubelet is the primary node agent and its logs are essential for diagnosing pod scheduling and startup issues.

```bash
journalctl -u kubelet | less
```

```
<output_omitted>
```

**2.** Major Kubernetes processes run inside containers. Use `find` to locate the **kube-apiserver** log on disk.

```bash
sudo find / -name "*apiserver*log"
```

```
/var/log/containers/kube-apiserver-controller_kube-system_kube-apiserver-423
d25701998f68b503e64d41dd786e657fc09504f13278044934d79a4019e3c.log
```

**3.** View the apiserver log file directly.

```bash
sudo less /var/log/containers/kube-apiserver-controller_kube-system_kube-apiserver-<Tab>
```

```
<output_omitted>
```

**4.** Search for and review log files for other cluster agents: `coredns`, `kube-proxy`, and others.

```bash
sudo find / -name "*coredns*log" 2>/dev/null
sudo find / -name "*kube-proxy*log" 2>/dev/null
```

**5.** On **systemd**-based clusters (all modern kubeadm deployments), component logs are in `journalctl`. On older non-systemd systems the log files below would be used instead — know these paths for reference:

**Control Plane node log files (non-systemd only):**
- `/var/log/kube-apiserver.log` — API server
- `/var/log/kube-scheduler.log` — scheduling decisions
- `/var/log/kube-controller-manager.log` — replication controllers

**Worker node log files (non-systemd only):**
- `/var/log/kubelet.log` — container runtime on the node
- `/var/log/kube-proxy.log` — service load balancing

**Container log files (all systems):**
- `/var/log/containers/` — individual container log files (symlinked)
- `/var/log/pods/` — pod-level log directories

**6.** Review the Kubernetes documentation for more troubleshooting information:
- https://kubernetes.io/docs/tasks/debug-application-cluster/troubleshooting/
- https://kubernetes.io/docs/tasks/debug-application-cluster/debug-application
- https://kubernetes.io/docs/tasks/debug-application-cluster/debug-cluster

---

## Exercise 13.2: Viewing Logs Output

Container standard output is accessible via `kubectl logs`. If a container writes no stdout there will be no log output. Logs are also lost when the container is destroyed unless an external logging agent is used.

**1.** View all pods running in the cluster across all namespaces.

```bash
kubectl get po --all-namespaces
```

```
NAMESPACE     NAME                                    READY   STATUS    RESTARTS   AGE
kube-system   cilium-operator-788c7d7585-jgn6s        1/1     Running   0          13m
kube-system   cilium-5tv9d                            1/1     Running   0          6d1h
....
kube-system   etcd-controller                                 1/1     Running   2          44h
kube-system   kube-apiserver-controller                       1/1     Running   2          44h
kube-system   kube-controller-manager-controller              1/1     Running   2          44h
kube-system   kube-scheduler-controller                       1/1     Running   2          44h
....
```

**2.** View the logs of infrastructure pods. Use Tab completion — first type the namespace, then start typing the pod name and Tab will complete it.

```bash
kubectl -n kube-system logs <Tab><Tab>
```

```
cilium-operator-788c7d7585-jgn6s
cilium-5tv9d
coredns-5644d7b6d9-k7kts
coredns-5644d7b6d9-rnr2v
etcd-controller
kube-apiserver-controller
kube-controller-manager-controller
kube-proxy-qhc4f
kube-proxy-s56hl
kube-scheduler-f-controller
<output_omitted>
```

```bash
kubectl -n kube-system logs \
  kube-apiserver-controller
```

```
Flag --insecure-port has been deprecated, This flag will be removed in a future version.
I1119 02:31:14.933023   1 server.go:623] external host was not specified, using 10.128.0.3
I1119 02:31:14.933356   1 server.go:149] Version: v1.29.1
I1119 02:31:15.595131   1 plugins.go:158] Loaded 11 mutating admission controller(s)
<output_omitted>
```

**3.** View the logs of other pods in your cluster. The `--previous` flag shows logs from a previously crashed container, which is essential for post-mortem debugging.

```bash
kubectl -n kube-system logs kube-scheduler-f-controller
kubectl -n kube-system logs etcd-controller
```

---

## Exercise 13.3: Adding Tools for Monitoring and Metrics

The **Metrics Server** exposes a standard API that `kubectl top` and the HPA controller use. If you installed it in Chapter 8 (Exercise 8.1) it should already be running — skip step 1 if so.

---

### Configure Metrics Server

**1.** If the metrics-server is not already installed, deploy it from the official components manifest.

```bash
kubectl create -f \
  https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

```
serviceaccount/metrics-server created
clusterrole.rbac.authorization.k8s.io/system:aggregated-metrics-reader created
clusterrole.rbac.authorization.k8s.io/system:metrics-server created
rolebinding.rbac.authorization.k8s.io/metrics-server-auth-reader created
clusterrolebinding.rbac.authorization.k8s.io/metrics-server:system:auth-delegator created
clusterrolebinding.rbac.authorization.k8s.io/system:metrics-server created
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
```

**2.** Check the metrics-server pod. It may show `0/1` initially — it needs `--kubelet-insecure-tls` to become ready.

```bash
kubectl -n kube-system get pods
```

```
<output_omitted>
metrics-server-fc6d4999b-b9rjj   0/1   Running   0   42s
```

**3.** Edit the metrics-server deployment to add the `--kubelet-insecure-tls` flag. The `--kubelet-preferred-address-types` line may also be needed in some environments.

```bash
kubectl -n kube-system edit deployment metrics-server
```

```yaml
....
spec:
  containers:
  - args:
    - --cert-dir=/tmp
    - --secure-port=4443
    - --kubelet-insecure-tls                                              #<-- Add this line
    - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname   #<-- May be needed
    image: k8s.gcr.io/metrics-server/metrics-server:v0.3.7
....
```

**4.** Verify the metrics-server pod starts and the logs show it is serving.

```bash
kubectl -n kube-system logs metrics-server-<Tab>
```

```
I0207 14:08:13.383209   1 serving.go:312] Generated self-signed cert
  (/tmp/apiserver.crt, /tmp/apiserver.key)
I0207 14:08:14.078360   1 secure_serving.go:116] Serving securely on
  [::]:4443
```

**5.** Test that metrics are working. It can take up to a minute for metrics to populate.

```bash
sleep 120 ; kubectl top pod --all-namespaces
```

```
NAMESPACE     NAME                                      CPU(cores)   MEMORY(bytes)
kube-system   cilium-kube-controllers-7b9dcdcc5-qg6zd  2m           6Mi
kube-system   cilium-node-dr279                         23m          22Mi
kube-system   coredns-5644d7b6d9-k7kts                 2m           6Mi
<output_omitted>
```

```bash
kubectl top nodes
```

```
NAME     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
controller       228m         11%    2357Mi          31%
worker1   76m          3%     1385Mi          18%
```

**6.** You can also query the metrics API directly using the TLS PEM files generated in the Chapter 5 exercise.

```bash
curl --cert ./client.pem \
  --key ./client-key.pem --cacert ./ca.pem \
  https://controller:6443/apis/metrics.k8s.io/v1beta1/nodes
```

```json
{
  "kind": "NodeMetricsList",
  "apiVersion": "metrics.k8s.io/v1beta1",
  "metadata": {
    "selfLink": "/apis/metrics.k8s.io/v1beta1/nodes"
  },
  "items": [
    {
      "metadata": {
        "name": "u16-1-13-1-2f8c",
        "timestamp": "2024-08-10T20:26:18Z",
        "window": "30s",
      },
      "usage": {
        "cpu": "215675721n",
        "memory": "2414744Ki"
      }
    },
<output_omitted>
```

---

### Configure the Kubernetes Dashboard

The Kubernetes Dashboard provides a web-based GUI for cluster management.

**1.** Deploy the dashboard using the pre-staged YAML.

```bash
kubectl create -f dashboard.yaml
```

**2.** Grant the dashboard service account cluster-admin rights so it can view all resources.

```bash
kubectl get sa -n kubernetes-dashboard
```

```
NAME                   SECRETS   AGE
default                0         4m25s
kubernetes-dashboard   0         4m25s
```

```bash
kubectl create clusterrolebinding dashaccess \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:kubernetes-dashboard
```

```
clusterrolebinding.rbac.authorization.k8s.io/dashaccess created
```

**3.** Find the public IP of the CP node and find the dashboard's NodePort, then open a browser to the HTTPS URL. You will get a security exception — click **Advanced** then **Add Exception** (or equivalent in your browser).

```bash
curl ifconfig.io
kubectl -n kubernetes-dashboard get svc
```

Browse to: `https://<your-public-ip>:<nodeport>/`

**4.** Select the **Token** authentication method. Generate a token for the dashboard service account and paste it into the login page.

```bash
kubectl create token kubernetes-dashboard \
  -n kubernetes-dashboard
```

```
eyJlxvezoLAilithbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2...
<output_omitted>
```

**5.** After logging in, explore the dashboard. Switch namespace to `kube-system` to see infrastructure pods and their CPU/memory usage graphs. Try scaling a deployment up and down and observe the dashboard respond in real time.

---
