# Chapter 15: Security

**Working directory: `~/lfs458/ch15-security/`**

---

## Exercise 15.1: Working with TLS

Every API request flows through TLS, then authentication, then authorization, and finally admission control. In this exercise we examine how the cluster establishes TLS and how component credentials are configured.

```bash
cd ~/lfs458/ch15-security/
```

**1.** View the kubelet service status on the CP node. The output shows the configuration files in use.

```bash
systemctl status kubelet.service
```

```
kubelet.service - kubelet: The Kubernetes Node Agent
  Loaded: loaded (/lib/systemd/system/kubelet.service; enabled; vendor preset: en
  Drop-In: /etc/systemd/system/kubelet.service.d
          |__10-kubeadm.conf
<output_omitted>
```

**2.** Find the kubelet configuration file from the status output. The `--config` flag points to it.

```
CGroup: /system.slice/kubelet.service
  |--19523 /usr/bin/kubelet .... --config=/var/lib/kubelet/config.yaml ..
```

**3.** Examine the kubelet config file. Note `staticPodPath` which sets where kubelet reads static pod manifests, and that PKI files live in `/etc/kubernetes/pki/`.

```bash
sudo less /var/lib/kubelet/config.yaml
```

```yaml
<output_omitted>
rotateCertificates: true
runtimeRequestTimeout: 0s
shutdownGracePeriod: 0s
shutdownGracePeriodCriticalPods: 0s
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 0s
syncFrequency: 0s
volumeStatsAggPeriod: 0s
```

**4.** View the static pod manifests directory — these four YAML files define the control plane components that kubelet starts before the API server is available.

```bash
sudo ls /etc/kubernetes/manifests/
```

```
etcd.yaml   kube-apiserver.yaml   kube-controller-manager.yaml   kube-scheduler.yaml
```

**5.** Inspect the kube-controller-manager manifest to see how certificate paths are passed.

```bash
sudo less /etc/kubernetes/manifests/kube-controller-manager.yaml
```

```
<output_omitted>
```

**6.** Tokens are kept as Secrets in the `kube-system` namespace. Bootstrap tokens expire after 24 hours. If none exists, create a new one then list them.

```bash
sudo kubeadm token create
kubectl -n kube-system get secrets
```

```
NAME                      TYPE                            DATA   AGE
bootstrap-token-i3r13t    bootstrap.kubernetes.io/token   7      5d
<output_omitted>
```

**7.** Inspect a bootstrap token Secret in detail.

```bash
kubectl -n kube-system get secrets bootstrap-token-<Tab> -o yaml
```

```yaml
apiVersion: v1
data:
  auth-extra-groups: c3lzdGVtOmJvb3RzdHJhcHBlcnM6a3ViZWFkbTpkZWZhdWx0LW5vZGUtdG9rZW4=
  expiration: MjAyMyMyOwNiOwMlQxMjowOTowMlo=
  token-id: NXBvMGo3
  token-secret: MXhzMDgxOG1rcTFyeDQxbg==
  usage-bootstrap-authentication: dHJ1ZQ==
  usage-bootstrap-signing: dHJ1ZQ==
kind: Secret
metadata:
  name: bootstrap-token-5po0j7
  namespace: kube-system
type: bootstrap.kubernetes.io/token
```

**8.** View the current kubeconfig. Keys and cert data are redacted automatically.

```bash
kubectl config view
```

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: REDACTED
    server: https://controller:6443
  name: kubernetes
<output_omitted>
```

**9.** View the help for `kubectl config set-credentials` to understand how to configure user credentials.

```bash
kubectl config set-credentials -h
```

```
Sets a user entry in kubeconfig
<output_omitted>
```

**10.** Make a backup of the current kubeconfig before modifying it.

```bash
cp $HOME/.kube/config $HOME/cluster-api-config
```

**11.** Explore the full range of `kubectl config` subcommands and `kubeadm` security commands.

```bash
kubectl config <Tab><Tab>
```

```
current-context   get-contexts    set-context      view
delete-cluster    rename-context  set-credentials
delete-context    set             unset
get-clusters      set-cluster     use-context
```

```bash
sudo kubeadm token -h
sudo kubeadm config -h
```

**12.** Review the kubeadm default configuration to understand cluster defaults such as token TTL and DNS settings.

```bash
sudo kubeadm config print init-defaults
```

```yaml
apiVersion: kubeadm.k8s.io/v1beta2
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
<output_omitted>
```

---

## Exercise 15.2: Authentication and Authorization

Kubernetes has two user types: **service accounts** (API objects) and **normal users** (managed externally via certificates). We will configure RBAC for a contractor `DevDan` who has full access to `development` but read-only access to `production`.

**1.** Create the two namespaces.

```bash
kubectl create ns development
kubectl create ns production
```

**2.** View the current contexts — only the `kubernetes-admin` context should exist.

```bash
kubectl config get-contexts
```

```
CURRENT   NAME                          CLUSTER      AUTHINFO           NAMESPACE
*         kubernetes-admin@kubernetes   kubernetes   kubernetes-admin
```

**3.** Create a Linux OS user `DevDan` with a password.

```bash
sudo useradd -s /bin/bash DevDan
sudo passwd DevDan
```

```
Enter new UNIX password:  lftr@in
Retype new UNIX password:  lftr@in
passwd: password updated successfully
```

**4.** Generate a 2048-bit RSA private key and a Certificate Signing Request (CSR) for `DevDan`. The `touch` command avoids a random-number-generator error on some Ubuntu systems.

```bash
openssl genrsa -out DevDan.key 2048
```

```
Generating RSA private key, 2048 bit long modulus
.......+++
.........+++
e is 65537 (0x10001)
```

```bash
touch $HOME/.rnd
openssl req -new -key DevDan.key \
  -out DevDan.csr -subj "/CN=DevDan/O=development"
```

**5.** Sign the CSR using the cluster's CA to produce a certificate valid for 45 days. `sudo` is required to read the cluster CA private key.

```bash
sudo openssl x509 -req -in DevDan.csr \
  -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial \
  -out DevDan.crt -days 45
```

```
Signature ok
subject=/CN=DevDan/O=development
Getting CA Private Key
```

**6.** Register the new user credentials in kubeconfig.

```bash
kubectl config set-credentials DevDan \
  --client-certificate=/home/guru/DevDan.crt \
  --client-key=/home/guru/DevDan.key
```

```
User "DevDan" set.
```

**7.** Verify the kubeconfig now contains DevDan's entry by diffing against the backup.

```bash
diff cluster-api-config .kube/config
```

```
16a,19d15
> - name: DevDan
>   user:
>     as-user-extra: {}
>     client-certificate: /home/guru/DevDan.crt
>     client-key: /home/guru/DevDan.key
```

**8.** Create a context that maps DevDan to the `development` namespace on the `kubernetes` cluster.

```bash
kubectl config set-context DevDan-context \
  --cluster=kubernetes \
  --namespace=development \
  --user=DevDan
```

```
Context "DevDan-context" created.
```

**9.** Test access using DevDan's context. It should fail — no RBAC rules exist yet.

```bash
kubectl --context=DevDan-context get pods
```

```
Error from server (Forbidden): pods is forbidden: User "DevDan"
cannot list pods in the namespace "development"
```

**10.** Verify both contexts are listed.

```bash
kubectl config get-contexts
```

```
CURRENT   NAME                          CLUSTER      AUTHINFO           NAMESPACE
          DevDan-context                kubernetes   DevDan             development
*         kubernetes-admin@kubernetes   kubernetes   kubernetes-admin
```

---

### Create Role and RoleBinding for development

**11.** Check the diff again to see the new context entry.

```bash
diff cluster-api-config .kube/config
```

**12.** Review the pre-staged `role-dev.yaml` — a Role giving DevDan full CRUD access to deployments, replicasets, and pods in the `development` namespace.

```bash
cat ~/lfs458/ch15-security/role-dev.yaml
```

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: development
  name: developer
rules:
- apiGroups: ["", "extensions", "apps"]
  resources: ["deployments", "replicasets", "pods"]
  verbs: ["list", "get", "watch", "create", "update", "patch", "delete"]
  # You can use ["*"] for all verbs
```

**13.** Create the Role.

```bash
kubectl create -f role-dev.yaml
```

```
role.rbac.authorization.k8s.io/developer created
```

**14.** Review the pre-staged `rolebind.yaml` — a RoleBinding connecting the `developer` Role to the `DevDan` user.

```bash
cat ~/lfs458/ch15-security/rolebind.yaml
```

```yaml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: developer-role-binding
  namespace: development
subjects:
- kind: User
  name: DevDan
  apiGroup: ""
roleRef:
  kind: Role
  name: developer
  apiGroup: ""
```

```bash
kubectl create -f rolebind.yaml
```

```
rolebinding.rbac.authorization.k8s.io/developer-role-binding created
```

**15.** Test again — DevDan should now be able to list pods in `development`.

```bash
kubectl --context=DevDan-context get pods
```

```
No resources found in development namespace.
```

**16.** Create a deployment, verify it, then delete it — all as DevDan.

```bash
kubectl --context=DevDan-context \
  create deployment nginx --image=nginx
```

```
deployment.apps/nginx created
```

```bash
kubectl --context=DevDan-context get pods
```

```
NAME                     READY   STATUS    RESTARTS   AGE
nginx-7c87f569d-7gb9k    1/1     Running   0          5s
```

```bash
kubectl --context=DevDan-context delete \
  deploy nginx
```

```
deployment.apps "nginx" deleted
```

---

### Create read-only Role for production

**17.** Create a read-only Role for `production` by copying and editing the dev role. Change the namespace, name, and verbs.

```bash
cp role-dev.yaml role-prod.yaml
vim role-prod.yaml
```

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: production    #<-- Edit to production
  name: dev-prod           #<-- Edit name
rules:
- apiGroups: ["", "extensions", "apps"]
  resources: ["deployments", "replicasets", "pods"]
  verbs: ["get", "list", "watch"]    #<-- Read-only verbs only
```

**18.** Create a matching production RoleBinding by copying and editing the dev binding. Update the name, namespace, and roleRef.

```bash
cp rolebind.yaml rolebindprod.yaml
vim rolebindprod.yaml
```

```yaml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: production-role-binding    #<-- Edit name
  namespace: production            #<-- Edit namespace
subjects:
- kind: User
  name: DevDan
  apiGroup: ""
roleRef:
  kind: Role
  name: dev-prod                   #<-- Edit to match role name
  apiGroup: ""
```

```bash
kubectl create -f role-prod.yaml
```

```
role.rbac.authorization.k8s.io/dev-prod created
```

```bash
kubectl create -f rolebindprod.yaml
```

```
rolebinding.rbac.authorization.k8s.io/production-role-binding created
```

**19.** Create a production context for DevDan.

```bash
kubectl config set-context ProdDan-context \
  --cluster=kubernetes \
  --namespace=production \
  --user=DevDan
```

```
Context "ProdDan-context" created.
```

**20.** Verify DevDan can list pods in production.

```bash
kubectl --context=ProdDan-context get pods
```

```
No resources found in production namespace.
```

**21.** Verify DevDan cannot create resources in production.

```bash
kubectl --context=ProdDan-context create \
  deployment nginx --image=nginx
```

```
Error from server (Forbidden): deployments.apps is forbidden:
User "DevDan" cannot create deployments.apps in the
namespace "production"
```

**22.** View the `dev-prod` Role details to confirm the verbs.

```bash
kubectl -n production describe role dev-prod
```

```
Name:         dev-prod
Labels:       <none>
PolicyRule:
  Resources          Non-Resource URLs   Resource Names   Verbs
  ---------          -----------------   --------------   -----
  deployments        []                  []               [get list watch]
  deployments.apps   []                  []               [get list watch]
<output_omitted>
```

**23.** Experiment with other subcommands in both contexts. They should match the verbs configured in each role.

**24.** **Optional challenge:** Switch to the `DevDan` Linux user and verify the contexts available. Try creating a deployment in `development` and `production` and compare the results. Configure so DevDan only has the two limited contexts available.

```bash
# As guru user — switch to DevDan
su - DevDan
kubectl config get-contexts
```

```
CURRENT   NAME              CLUSTER      AUTHINFO   NAMESPACE
*         DevDan-context    kubernetes   DevDan     development
          ProdDan-context   kubernetes   DevDan     production
```

---

## Exercise 15.3: Admission Controllers

**Admission controllers** intercept API requests after authentication and authorization. They can mutate (modify) or validate objects before they are persisted. In modern Kubernetes they are compiled into the API server binary.

**1.** View the admission plugins currently enabled. The static pod manifest for the API server shows the flags.

```bash
sudo grep admission \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

```
- --enable-admission-plugins=NodeRestriction
```

> Only `NodeRestriction` is explicitly enabled here. The full default list of enabled plugins can be found at https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#which-plugins-are-enabled-by-default

---
