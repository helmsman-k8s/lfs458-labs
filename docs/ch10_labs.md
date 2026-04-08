# Chapter 10: Services

**Working directory: `~/lfs458/ch10-services/`**

---

## Exercise 10.1: Deploy A New Service

Services provide a stable network identity to a dynamic set of Pods. They are assigned labels to allow persistent access even as Pods are terminated and replaced. In this exercise we deploy nginx in a custom namespace using a `nodeSelector`, expose it as a service, and explore endpoints.

```bash
cd ~/lfs458/ch10-services/
```

**1.** Review the pre-staged `nginx-one.yaml` — a well-documented Deployment that places pods on a node labelled `system=secondOne`, in the `accounting` namespace, exposing port 8080.

```bash
cat ~/lfs458/ch10-services/nginx-one.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-one
  labels:
    system: secondary
  namespace: accounting
spec:
  selector:
    matchLabels:
      system: secondary
  replicas: 2
  template:
    metadata:
      labels:
        system: secondary
    spec:
      containers:
      - image: nginx:1.20.1
        imagePullPolicy: Always
        name: nginx
        ports:
        - containerPort: 8080
          protocol: TCP
      nodeSelector:
        system: secondOne
```

**2.** View the existing labels on the nodes in the cluster.

```bash
kubectl get nodes --show-labels
```

```
<output_omitted>
```

**3.** Attempt to create the Deployment. It should fail because the `accounting` namespace does not exist yet.

```bash
kubectl create -f nginx-one.yaml
```

```
Error from server (NotFound): error when creating
"nginx-one.yaml": namespaces "accounting" not found
```

**4.** Create the namespace and try again.

```bash
kubectl create ns accounting
```

```
namespace/accounting created
```

```bash
kubectl create -f nginx-one.yaml
```

```
deployment.apps/nginx-one created
```

**5.** View the pods in the `accounting` namespace. They show `Pending` because no node has the required label.

```bash
kubectl -n accounting get pods
```

```
NAME                          READY   STATUS    RESTARTS   AGE
nginx-one-74dd9d578d-fcpmv    0/1     Pending   0          4m
nginx-one-74dd9d578d-r2d67    0/1     Pending   0          4m
```

**6.** Describe one of the pods to confirm the scheduling failure reason.

```bash
kubectl -n accounting describe pod <nginx-one-pod-name>
```

```
Events:
  Type     Reason            Age    From               Message
  ----     ------            ---    ----               -------
  Warning  FailedScheduling  <unknown>  default-scheduler
  0/2 nodes are available: 2 node(s) didn't match node selector.
```

**7.** Label the worker1 node with the value the `nodeSelector` expects. Note the value is case sensitive.

```bash
kubectl label node worker1 system=secondOne
```

```
node/worker1 labeled
```

```bash
kubectl get nodes --show-labels
```

```
NAME     STATUS   ROLES           AGE    VERSION   LABELS
controller       Ready    control-plane   14h    v1.34.1   beta.kubernetes.io/arch=amd64,...
worker1   Ready    <none>          14h    v1.34.1   beta.kubernetes.io/arch=amd64,...,system=secondOne,...
```

**8.** Check the pods again — they should now be `Running`. If they still show `Pending` after a minute, delete one to trigger the scheduler to re-evaluate.

```bash
kubectl -n accounting get pods
```

```
NAME                          READY   STATUS    RESTARTS   AGE
nginx-one-74dd9d578d-fcpmv    1/1     Running   0          10m
nginx-one-74dd9d578d-sts5l    1/1     Running   0          3s
```

**9.** View Pods by the `system=secondary` label across all namespaces.

```bash
kubectl get pods -l system=secondary --all-namespaces
```

```
NAMESPACE    NAME                          READY   STATUS    RESTARTS   AGE
accounting   nginx-one-74dd9d578d-fcpmv    1/1     Running   0          20m
accounting   nginx-one-74dd9d578d-sts5l    1/1     Running   0          9m
```

**10.** Expose the deployment. Port 8080 was declared in the YAML file.

```bash
kubectl -n accounting expose deployment nginx-one
```

```
service/nginx-one exposed
```

**11.** View the newly created endpoints. Each Pod's IP is listed on port 8080.

```bash
kubectl -n accounting get ep nginx-one
```

```
NAME        ENDPOINTS                                 AGE
nginx-one   192.168.1.72:8080,192.168.1.73:8080      47s
```

**12.** Test access on port 8080 (nginx is not listening there) then on port 80 (nginx default). Use the Pod IP from the endpoint output above.

```bash
curl 192.168.1.72:8080
```

```
curl: (7) Failed to connect to 192.168.1.72 port 8080: Connection refused
```

```bash
curl 192.168.1.72:80
```

```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<output_omitted>
```

**13.** Delete the deployment, fix the port in the YAML to `80`, and recreate it.

```bash
kubectl -n accounting delete deploy nginx-one
```

```
deployment.apps "nginx-one" deleted
```

```bash
vim nginx-one.yaml
```

```yaml
....
        ports:
        - containerPort: 80    #<-- Edit from 8080 to 80
          protocol: TCP
....
```

```bash
kubectl create -f nginx-one.yaml
```

```
deployment.apps/nginx-one created
```

---

## Exercise 10.2: Configure a NodePort

A `NodePort` exposes the service on a static high-numbered port on every node, making it accessible from outside the cluster.

**1.** Expose the deployment as a NodePort service with a memorable name.

```bash
kubectl -n accounting expose deployment nginx-one \
  --type=NodePort --name=service-lab
```

```
service/service-lab exposed
```

**2.** View the service details and note the auto-generated NodePort.

```bash
kubectl -n accounting describe services
```

```
....
NodePort:   <unset>  32103/TCP
....
```

**3.** Get the cluster API server URL and confirm the CP hostname.

```bash
kubectl cluster-info
```

```
Kubernetes control plane is running at https://controller:6443
CoreDNS is running at https://controller:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

**4.** Test access to the nginx web server using the CP hostname and NodePort.

```bash
curl http://controller:<nodeport>
```

```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<output_omitted>
```

**5.** You can also access the service from outside the lab using the public IP of any node and the NodePort. Find your public IP if needed.

```bash
curl ifconfig.io
```

---

## Exercise 10.3: Working with CoreDNS

**CoreDNS** provides DNS resolution within the cluster. Services are registered automatically using a predictable FQDN pattern: `<service>.<namespace>.svc.cluster.local`.

**1.** Review the pre-staged `nettool.yaml` — a long-running Ubuntu Pod for network diagnostics.

```bash
cat ~/lfs458/ch10-services/nettool.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ubuntu
spec:
  containers:
  - name: ubuntu
    image: ubuntu:latest
    command: [ "sleep" ]
    args: [ "infinity" ]
```

**2.** Create the Pod and exec into it.

```bash
kubectl create -f nettool.yaml
```

```
pod/ubuntu created
```

```bash
kubectl exec -it ubuntu -- /bin/bash
```

> The following sub-steps **(a)–(h)** run **inside the ubuntu container**.

**(a)** Install network tools.

```bash
apt-get update ; apt-get install curl dnsutils -y
```

**(b)** Run `dig` with no arguments to see the DNS server responding.

```bash
dig
```

```
; <<>> DiG 9.16.1-Ubuntu <<>>
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 3394
;; SERVER: 10.96.0.10#53(10.96.0.10)
;; Query time: 4 msec
<output_omitted>
```

**(c)** Check `/etc/resolv.conf` — the first search domain is `default.svc.cluster.local` since the Pod is in the `default` namespace.

```bash
cat /etc/resolv.conf
```

```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

**(d)** Do a reverse lookup on the CoreDNS IP. Note the domain uses `.kube-system.svc.cluster.local.` — reflecting the pod's namespace.

```bash
dig @10.96.0.10 -x 10.96.0.10
```

```
;; ANSWER SECTION:
10.0.96.10.in-addr.arpa.   30  IN  PTR  kube-dns.kube-system.svc.cluster.local.
```

**(e)** Use the full FQDN of the `service-lab` service to access nginx. This works because the service is in the `accounting` namespace.

```bash
curl service-lab.accounting.svc.cluster.local.
```

```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<output_omitted>
```

**(f)** Try using just the short service name. It fails because `nettool` is in the `default` namespace and `service-lab` is in `accounting`.

```bash
curl service-lab
```

```
curl: (6) Could not resolve host: service-lab
```

**(g)** Add the namespace to the short name and try again.

```bash
curl service-lab.accounting
```

```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<output_omitted>
```

**(h)** Exit the container.

```bash
exit
```

**3.** Examine the `kube-dns` service in `kube-system`. Note the selector that routes DNS traffic.

```bash
kubectl -n kube-system get svc kube-dns -o yaml
```

```yaml
...
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: CoreDNS
...
  selector:
    k8s-app: kube-dns
  sessionAffinity: None
  type: ClusterIP
...
```

**4.** Find all pods with the `k8s-app` label across all namespaces — these are the infrastructure pods served by this selector, including `coredns`.

```bash
kubectl get pod -l k8s-app --all-namespaces
```

```
NAMESPACE     NAME                              READY   STATUS    RESTARTS   AGE
kube-system   cilium-5tv9d                      1/1     Running   0          136m
kube-system   cilium-gzdk6                      1/1     Running   0          54m
kube-system   coredns-5d78c9869d-44qvq          1/1     Running   0          31m
kube-system   coredns-5d78c9869d-j6tqx          1/1     Running   0          31m
kube-system   kube-proxy-lpsmq                  1/1     Running   0          35m
kube-system   kube-proxy-pvl8w                  1/1     Running   0          34m
```

**5.** Inspect a CoreDNS pod. Note the configuration is loaded from a ConfigMap mounted at `/etc/coredns/Corefile`.

```bash
kubectl -n kube-system get pod <coredns-pod-name> -o yaml
```

```yaml
...
spec:
  containers:
  - args:
    - -conf
    - /etc/coredns/Corefile
    image: k8s.gcr.io/coredns:1.7.0
...
    volumeMounts:
    - mountPath: /etc/coredns
      name: config-volume
      readOnly: true
...
  volumes:
  - configMap:
      items:
      - key: Corefile
        path: Corefile
      name: coredns
    name: config-volume
...
```

**6.** View the ConfigMaps in `kube-system`. The `coredns` ConfigMap holds the Corefile.

```bash
kubectl -n kube-system get configmaps
```

```
NAME                                 DATA   AGE
cilium-config                        4      43h
coredns                              1      43h
extension-apiserver-authentication   6      43h
kube-proxy                           2      43h
kubeadm-config                       2      43h
kubelet-config                       1      43h
```

**7.** View the CoreDNS Corefile configuration. Note `cluster.local` is the default domain and `forward` sends unknown queries to `/etc/resolv.conf`.

```bash
kubectl -n kube-system get configmaps coredns -o yaml
```

```yaml
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
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
kind: ConfigMap
...
```

**8.** Back up the CoreDNS ConfigMap before editing.

```bash
kubectl -n kube-system get configmaps coredns -o yaml > coredns-backup.yaml
```

**9.** Edit the CoreDNS ConfigMap to add a `rewrite` rule so that `*.test.io` domains resolve to `*.default.svc.cluster.local`. Add the rewrite line as the **first** entry inside the `.:53` block.

```bash
kubectl -n kube-system edit configmaps coredns
```

```yaml
....
    .:53 {
        rewrite name regex (.*)\.test\.io {1}.default.svc.cluster.local  #<-- Add this line
        errors
        health {
          lameduck 5s
        }
....
```

**10.** Delete the CoreDNS pods to force them to re-read the updated ConfigMap.

```bash
kubectl -n kube-system delete pod <coredns-pod-1> <coredns-pod-2>
```

```
pod "coredns-f9fd979d6-s4j98" deleted
pod "coredns-f9fd979d6-xlpzf" deleted
```

**11.** Create an nginx deployment and expose it as a ClusterIP service to test the rewrite rule.

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=ClusterIP --port=80
kubectl get svc
```

```
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1        <none>        443/TCP   3d15h
nginx        ClusterIP   10.104.248.141   <none>        80/TCP    7s
```

**12.** Exec into the ubuntu container and test the rewrite rule.

```bash
kubectl exec -it ubuntu -- /bin/bash
```

**(a)** Do a reverse lookup to get the FQDN of the nginx service IP.

```bash
dig -x 10.104.248.141
```

```
;; ANSWER SECTION:
141.248.104.10.in-addr.arpa.  30  IN  PTR  nginx.default.svc.cluster.local.
```

**(b)** Do a forward lookup using the full FQDN.

```bash
dig nginx.default.svc.cluster.local.
```

```
;; ANSWER SECTION:
nginx.default.svc.cluster.local.  30  IN  A  10.104.248.141
```

**(c)** Test the `test.io` rewrite rule — `nginx.test.io` should resolve to the same IP as `nginx.default.svc.cluster.local`.

```bash
dig nginx.test.io
```

```
;; ANSWER SECTION:
nginx.default.svc.cluster.local.  30  IN  A  10.104.248.141
```

**(d)** Exit the container.

```bash
exit
```

**13.** Edit the CoreDNS configmap again to upgrade the rewrite rule to also return the `test.io` name in the answer (using `rewrite stop` with an `answer` clause).

```bash
kubectl -n kube-system edit configmaps coredns
```

```yaml
....
    .:53 {
        rewrite stop {                                                    #<-- Edit these 3 lines
          name regex (.*)\.test\.io {1}.default.svc.cluster.local
          answer name (.*)\.default\.svc\.cluster\.local {1}.test.io
          }
        errors
        health {
....
```

**14.** Delete the CoreDNS pods again to pick up the new config.

```bash
kubectl -n kube-system delete pod <coredns-pod-1> <coredns-pod-2>
```

**15.** Exec into ubuntu and test again. This time the answer section should return the `test.io` FQDN rather than the internal one.

```bash
kubectl exec -it ubuntu -- /bin/bash
```

```bash
dig nginx.test.io
```

```
;; ANSWER SECTION:
nginx.test.io.   30  IN  A  10.104.248.141
```

```bash
exit
```

**16.** Delete the ubuntu nettool container to free up resources.

```bash
kubectl delete -f nettool.yaml
```

---

## Exercise 10.4: Use Labels to Manage Resources

Labels provide a powerful way to select and manage groups of resources across namespaces.

**1.** Delete all Pods with the `system=secondary` label across all namespaces. The Deployment controller will immediately create replacement Pods.

```bash
kubectl delete pods -l system=secondary \
  --all-namespaces
```

```
pod "nginx-one-74dd9d578d-fcpmv" deleted
pod "nginx-one-74dd9d578d-sts5l" deleted
```

**2.** Check the `accounting` namespace — new Pods are already running.

```bash
kubectl -n accounting get pods
```

```
NAME                          READY   STATUS    RESTARTS   AGE
nginx-one-74dd9d578d-ddt5r    1/1     Running   0          1m
nginx-one-74dd9d578d-hfzml    1/1     Running   0          1m
```

**3.** View the deployment label to confirm it still carries the `system=secondary` label.

```bash
kubectl -n accounting get deploy --show-labels
```

```
NAME        READY   UP-TO-DATE   AVAILABLE   AGE   LABELS
nginx-one   2/2     2            2           10m   system=secondary
```

**4.** Delete the deployment using its label.

```bash
kubectl -n accounting delete deploy -l system=secondary
```

```
deployment.apps "nginx-one" deleted
```

**5.** Remove the `system` label from the worker1 node. The syntax is the key name followed immediately by a minus sign.

```bash
kubectl label node worker1 system-
```

```
node/worker1 unlabeled
```

---
