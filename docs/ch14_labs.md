# Chapter 14: Custom Resource Definition

**Working directory: `~/lfs458/ch14-crd/`**

---

## Exercise 14.1: Create a Custom Resource Definition

A **Custom Resource Definition (CRD)** extends the Kubernetes API with new object types without writing a full API server. Once a CRD is registered, you can create, list, describe and delete instances of the new resource using standard `kubectl` commands.

```bash
cd ~/lfs458/ch14-crd/
```

**1.** View the existing CRDs in the cluster. You will see CRDs created by Cilium and Linkerd from previous labs.

```bash
kubectl get crd --all-namespaces
```

```
NAME                                          CREATED AT
authorizationpolicies.policy.linkerd.io       2024-08-28T11:30:34Z
ciliumcidrgroups.cilium.io                    2024-08-28T08:58:54Z
ciliumclusterwidenetworkpolicies.cilium.io    2024-08-28T08:58:57Z
<output_omitted>
```

**2.** Examine one of the existing CRDs to understand their structure. Copy the cilium CNI YAML from Chapter 3 and inspect it, then describe the CRD to see the full spec.

```bash
cp ~/lfs458/ch03-install/cilium-cni.yaml .
less cilium-cni.yaml
kubectl describe crd ciliumcidrgroups.cilium.io
```

```
Name:         ciliumcidrgroups.cilium.io
Namespace:
Labels:       io.cilium.k8s.crd.schema.version=1.26.10
API Version:  apiextensions.k8s.io/v1
Kind:         CustomResourceDefinition
<output_omitted>
```

**3.** Review the pre-staged `crd.yaml` file. It defines a new `CronTab` resource in the `stable.example.com` group with OpenAPI v3 schema validation.

```bash
cat ~/lfs458/ch14-crd/crd.yaml
```

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  # name must match the spec fields below: <plural>.<group>
  name: crontabs.stable.example.com
spec:
  # group name for REST API: /apis/<group>/<version>
  group: stable.example.com
  versions:
    - name: v1
      # Each version can be enabled/disabled by the Served flag.
      served: true
      # One and only one version must be marked as the storage version.
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                cronSpec:
                  type: string
                image:
                  type: string
                replicas:
                  type: integer
  # either Namespaced or Cluster
  scope: Namespaced
  names:
    # plural name used in the URL: /apis/<group>/<version>/<plural>
    plural: crontabs
    # singular name used as an alias on the CLI and for display
    singular: crontab
    # kind is normally the CamelCased singular type
    kind: CronTab
    # shortNames allow shorter string to match your resource on the CLI
    shortNames:
    - ct
```

**4.** Register the new CRD with the cluster.

```bash
kubectl create -f crd.yaml
```

```
customresourcedefinition.apiextensions.k8s.io/crontabs.stable.example.com created
```

**5.** List all CRDs and verify the new one appears. Then describe it to see the full details.

```bash
kubectl get crd
```

```
NAME                                          CREATED AT
<output_omitted>
crontabs.stable.example.com                  2024-08-13T03:18:07Z
<output_omitted>
```

```bash
kubectl describe crd crontab<Tab>
```

```
Name:         crontabs.stable.example.com
Namespace:
Labels:       <none>
Annotations:  <none>
API Version:  apiextensions.k8s.io/v1
Kind:         CustomResourceDefinition
<output_omitted>
```

**6.** Review the pre-staged `new-crontab.yaml` — an instance of the new `CronTab` resource type. The `apiVersion` uses the group and version from the CRD, and `kind` matches the CamelCased kind.

```bash
cat ~/lfs458/ch14-crd/new-crontab.yaml
```

```yaml
apiVersion: "stable.example.com/v1"
     # This is from the group and version of new CRD
kind: CronTab
     # The kind from the new CRD
metadata:
  name: new-cron-object
spec:
  cronSpec: "*/5 * * * *"
  image: some-cron-image
     #Does not exist
```

**7.** Create the new CronTab object and verify it can be accessed using both the full kind and the shortname `ct`.

```bash
kubectl create -f new-crontab.yaml
```

```
crontab.example.com/new-cron-object created
```

```bash
kubectl get CronTab
```

```
NAME              AGE
new-cron-object   22s
```

```bash
kubectl get ct
```

```
NAME              AGE
new-cron-object   29s
```

```bash
kubectl describe ct
```

```
Name:         new-cron-object
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  stable.example.com/v1
Kind:         CronTab
<output_omitted>
Spec:
  Cron Spec:  */5 * * * *
  Image:      some-cron-image
Events:       <none>
```

**8.** Delete the CRD. This automatically removes all instances of the resource as well.

```bash
kubectl delete -f crd.yaml
```

```
customresourcedefinition.apiextensions.k8s.io "crontabs.stable.example.com" deleted
```

---
