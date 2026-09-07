# Chapter 5: APIs and Access

**Working directory: `~/lfs458/ch05-api-access/`**

---

## Exercise 5.1: Configuring TLS Access

Using the Kubernetes API, **kubectl** makes API calls on your behalf. With the appropriate TLS keys you can also use **curl** directly to interact with the API server. API requests must pass information as JSON — kubectl converts `.yaml` to JSON automatically.

```bash
cd ~/lfs458/ch05-api-access/
```

**1.** Review the kubectl configuration file. We will use the three certificates and the API server address from this file.

```bash
less $HOME/.kube/config
```

You will see the cluster's server address, and three base64-encoded certificates: `certificate-authority-data`, `client-certificate-data`, and `client-key-data`. Press `q` to exit.

**2.** Create variables from the certificate information in the config file. Begin with the `client-certificate-data` key.

```bash
export client=$(grep client-cert $HOME/.kube/config | cut -d" " -f 6)
echo $client
```

You will see a long base64 string — this is your cluster's client certificate. The value will be unique to your cluster.

**3.** Collect the `client-key-data` as the `key` variable.

```bash
export key=$(grep client-key-data $HOME/.kube/config | cut -d" " -f 6)
echo $key
```

You will see another long base64 string — your client private key.

**4.** Set the `auth` variable with the `certificate-authority-data` key.

```bash
export auth=$(grep certificate-authority-data $HOME/.kube/config | cut -d" " -f 6)
echo $auth
```

You will see another long base64 string — the cluster's Certificate Authority (CA).

**5.** Decode and save the three keys as PEM files for use with `curl`.

```bash
echo $client | base64 -d - > ./client.pem
echo $key | base64 -d - > ./client-key.pem
echo $auth | base64 -d - > ./ca.pem
```

**6.** Pull the API server URL from the config file.

```bash
kubectl config view | grep server
```

```
server: https://controller:6443
```

**7.** Use `curl` with the PEM files to connect to the API server and list pods. Use the server address from the previous step.

```bash
curl --cert ./client.pem \
  --key ./client-key.pem \
  --cacert ./ca.pem \
  https://controller:6443/api/v1/pods
```

```json
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {
    "resourceVersion": "239414"
  },
  "items": [
    ...all running pods listed as JSON objects...
  ]
}
```

**8.** Now use `curl` to create a new pod using a JSON file. The `curlpod.json` file is already staged in your lab folder. Review it first.

```bash
cat ~/lfs458/ch05-api-access/curlpod.json
```

```json
{
    "kind": "Pod",
    "apiVersion": "v1",
    "metadata": {
        "name": "curlpod",
        "namespace": "default",
        "labels": {
            "name": "examplepod"
        }
    },
    "spec": {
        "containers": [{
            "name": "nginx",
            "image": "nginx",
            "ports": [{"containerPort": 80}]
        }]
    }
}
```

**9.** Use `curl` with an XPOST call to create the pod from the JSON file. There will be a lot of output — the last few lines should show a `Pending` phase as the pod begins creation.

```bash
curl --cert ./client.pem \
  --key ./client-key.pem \
  --cacert ./ca.pem \
  https://controller:6443/api/v1/namespaces/default/pods \
  -XPOST -H'Content-Type: application/json' \
  -d@curlpod.json
```

```json
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "curlpod",
    ...
  },
  "status": {
    "phase": "Pending"
  }
}
```

**10.** Verify the new pod exists and is running.

```bash
kubectl get pods
```

```
NAME       READY   STATUS    RESTARTS   AGE
curlpod    1/1     Running   0          45s
```

---

## Exercise 5.2: Explore API Calls

**1.** Use **strace** to observe what API calls `kubectl` makes under the hood. Install strace if not present, then check current endpoints.

```bash
sudo apt-get install -y strace
kubectl get endpoints
```

```
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME         ENDPOINTS           AGE
kubernetes   192.168.2.x:6443    3h
```

> **Note:** The deprecation warning is expected on Kubernetes 1.33+ and can be ignored.

**2.** Run the same command prefixed with `strace`. Near the end of the output you will see several `openat` calls referencing the local discovery cache directory. Redirect to a file and grep if the output is too large.

```bash
strace kubectl get endpoints
```

```
execve("/usr/bin/kubectl", ["kubectl", "get", "endpoints"], [/*....
....
openat(AT_FDCWD, "/home/<your-user>/.kube/cache/discovery/controller_6443/...
... many system calls ...
```

**3.** Change to the cache discovery directory and explore its contents.

```bash
cd $HOME/.kube/cache/discovery/
ls
```

```
controller_6443
```

```bash
cd controller_6443/
ls
```

```
admissionregistration.k8s.io   certificates.k8s.io   node.k8s.io
apiextensions.k8s.io            coordination.k8s.io   policy
apiregistration.k8s.io          crd.projectcalico.org  rbac.authorization.k8s.io
apps                            discovery.k8s.io      scheduling.k8s.io
authentication.k8s.io           events.k8s.io         servergroups.json
authorization.k8s.io            extensions            storage.k8s.io
autoscaling                     flowcontrol.apiserver.k8s.io   v1
batch                           networking.k8s.io
```

**4.** List the sub-files recursively.

```bash
find .
```

```
.
./storage.k8s.io
./storage.k8s.io/v1beta1
./storage.k8s.io/v1beta1/serverresources.json
./storage.k8s.io/v1
./storage.k8s.io/v1/serverresources.json
./rbac.authorization.k8s.io
... (one entry per API group)
```

**5.** View the objects available in version 1 of the API. For each object you can see the verbs (actions) available.

```bash
python3 -m json.tool v1/serverresources.json
```

```json
{
    "apiVersion": "v1",
    "groupVersion": "v1",
    "kind": "APIResourceList",
    "resources": [
        {
            "kind": "Binding",
            "name": "bindings",
            "namespaced": true,
            "singularName": "",
            "verbs": [
                "create"
            ]
        },
...
```

**6.** Pipe through `less` to navigate the output more easily.

```bash
python3 -m json.tool v1/serverresources.json | less
```

**7.** Find the `shortNames` for resources — these are the abbreviated names you can use with `kubectl`. Look for the endpoint shortname.

```bash
python3 -m json.tool v1/serverresources.json | grep -A 4 shortNames
```

```json
"shortNames": [
    "ep"
],
```

**8.** Use the shortName to verify it works.

```bash
kubectl get ep
```

```
NAME         ENDPOINTS           AGE
kubernetes   10.96.0.1:6443      3h
```

**9.** Count how many objects are in the v1 API group.

```bash
python3 -m json.tool v1/serverresources.json | grep kind
```

```
    "kind": "APIResourceList",
            "kind": "Binding",
            "kind": "ComponentStatus",
            "kind": "ConfigMap",
            "kind": "Endpoints",
            "kind": "Event",
... (many more resource kinds)
```

**10.** Look at the `apps/v1` API group — it contains nine more resource types.

```bash
python3 -m json.tool apps/v1/serverresources.json | grep kind
```

```
    "kind": "APIResourceList",
            "kind": "ControllerRevision",
            "kind": "DaemonSet",
            "kind": "DaemonSet",
            "kind": "Deployment",
... (more resource kinds)
```

**11.** Return to the home directory and delete the `curlpod` to recoup system resources.

```bash
cd $HOME
kubectl delete po curlpod
```

```
pod "curlpod" deleted
```

**12.** Take a look at other files in the cache directory as time permits to understand the full API surface.

---
