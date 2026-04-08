# Chapter 7: Managing State with Deployments

**Working directory: `~/lfs458/ch07-deployments/`**

---

## Exercise 7.1: Working with ReplicaSets

A `ReplicaSet` is a next-generation Replication Controller. The only reason to use a ReplicaSet directly is if you have no need for updating container software or update orchestration. In most cases you should use a `Deployment` instead.

```bash
cd ~/lfs458/ch07-deployments/
```

**1.** Check for any existing ReplicaSets in the default namespace.

```bash
kubectl get rs
```

```
No resources found in default namespace.
```

**2.** The `rs.yaml` file is already staged in your lab folder. Review it — it creates two replicas of nginx:1.22.1.

```bash
cat ~/lfs458/ch07-deployments/rs.yaml
```

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: rs-one
spec:
  replicas: 2
  selector:
    matchLabels:
      system: ReplicaOne
  template:
    metadata:
      labels:
        system: ReplicaOne
    spec:
      containers:
      - name: nginx
        image: nginx:1.22.1
        ports:
        - containerPort: 80
```

**3.** Create the ReplicaSet.

```bash
kubectl create -f rs.yaml
```

```
replicaset.apps/rs-one created
```

**4.** View the newly created ReplicaSet and its details.

```bash
kubectl describe rs rs-one
```

```
Name:         rs-one
Namespace:    default
Selector:     system=ReplicaOne
Labels:       <none>
Replicas:     2 current / 2 desired
Pods Status:  2 Running / 0 Waiting / 0 Succeeded / 0 Failed
Pod Template:
  Labels:  system=ReplicaOne
  Containers:
   nginx:
    Image:  nginx:1.22.1
    Port:   80/TCP
<output_omitted>
```

**5.** View the Pods created by the ReplicaSet. There should be two running.

```bash
kubectl get pods
```

```
NAME            READY   STATUS    RESTARTS   AGE
rs-one-2p9x4    1/1     Running   0          5m4s
rs-one-3c6pb    1/1     Running   0          5m4s
```

**6.** Delete the ReplicaSet but leave its Pods running using `--cascade=orphan`.

```bash
kubectl delete rs rs-one --cascade=orphan
```

```
replicaset.apps "rs-one" deleted
```

**7.** Verify the ReplicaSet is gone but the Pods remain.

```bash
kubectl describe rs rs-one
```

```
Error from server (NotFound): replicasets.apps "rs-one" not found
```

```bash
kubectl get pods
```

```
NAME            READY   STATUS    RESTARTS   AGE
rs-one-2p9x4    1/1     Running   0          7m
rs-one-3c6pb    1/1     Running   0          7m
```

**8.** Re-create the ReplicaSet. Because the selector matches the existing Pod labels, the new ReplicaSet will take ownership of the orphaned Pods. Pod software versions cannot be updated this way.

```bash
kubectl create -f rs.yaml
```

```
replicaset.apps/rs-one created
```

**9.** View the age of the ReplicaSet and the Pods — the Pods are older than the ReplicaSet, confirming ownership was assumed.

```bash
kubectl get rs
```

```
NAME     DESIRED   CURRENT   READY   AGE
rs-one   2         2         2       46s
```

```bash
kubectl get pods
```

```
NAME            READY   STATUS    RESTARTS   AGE
rs-one-2p9x4    1/1     Running   0          8m
rs-one-3c6pb    1/1     Running   0          8m
```

**10.** Isolate a Pod from its ReplicaSet by editing its label. Change `system: ReplicaOne` to `system: IsolatedPod`. Use the pod name from your output.

```bash
kubectl edit pod rs-one-3c6pb
```

```yaml
....
  labels:
    system: IsolatedPod    #<-- Change from ReplicaOne
managedFields:
....
```

**11.** The ReplicaSet detects it only has one matching Pod and creates a replacement. Verify two Pods are still running.

```bash
kubectl get rs
```

```
NAME     DESIRED   CURRENT   READY   AGE
rs-one   2         2         2       4m
```

**12.** Now view pods with the `system` label column. You should see three pods — two with `ReplicaOne` and one with `IsolatedPod`.

```bash
kubectl get po -L system
```

```
NAME            READY   STATUS    RESTARTS   AGE   SYSTEM
rs-one-3c6pb    1/1     Running   0          10m   IsolatedPod
rs-one-2p9x4    1/1     Running   0          10m   ReplicaOne
rs-one-dq5xd    1/1     Running   0          30s   ReplicaOne
```

**13.** Delete the ReplicaSet, then check remaining Pods.

```bash
kubectl delete rs rs-one
```

```
replicaset.apps "rs-one" deleted
```

```bash
kubectl get po
```

```
NAME            READY   STATUS        RESTARTS   AGE
rs-one-3c6pb    1/1     Running       0          14m
rs-one-dq5xd    0/1     Terminating   0          4m
```

**14.** Wait a moment then check again. There should be no ReplicaSets but one Pod remains — the isolated one.

```bash
kubectl get rs
```

```
No resources found in default namespaces.
```

```bash
kubectl get pod
```

```
NAME            READY   STATUS    RESTARTS   AGE
rs-one-3c6pb    1/1     Running   0          16m
```

**15.** Delete the remaining isolated Pod using its label.

```bash
kubectl delete pod -l system=IsolatedPod
```

```
pod "rs-one-3c6pb" deleted
```

---

## Exercise 7.2: Working with Deployments

A `Deployment` is a watch loop object that provides declarative updates to Pods and ReplicaSets. It is the recommended way to manage stateless applications in Kubernetes.

**1.** Generate a Deployment YAML using the imperative method with `--dry-run=client`.

```bash
kubectl create deploy webserver --image nginx:1.22.1 --replicas=2 \
  --dry-run=client -o yaml | tee dep.yaml
```

```yaml
....
kind: Deployment
....
name: webserver
....
replicas: 2
....
app: webserver
....
```

**2.** Create the Deployment and verify two Pods are running.

```bash
kubectl create -f dep.yaml
```

```
deployment.apps/webserver created
```

```bash
kubectl get deploy
```

```
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
webserver   2/2     2            2           14s
```

```bash
kubectl get pod
```

```
NAME                          READY   STATUS    RESTARTS   AGE
webserver-6cbc654ddc-lssbm    1/1     Running   0          42s
webserver-6cbc654ddc-xpmtl    1/1     Running   0          42s
```

**3.** Verify the image running inside the Pods. Note this version — you will compare it after the rollout.

```bash
kubectl describe pod webserver-6cbc654ddc-lssbm | grep Image:
```

```
Image:   nginx:1.22.1
```

---

## Exercise 7.3: Rollout and Rollback using Deployment

**1.** View the current update strategy for the `webserver` Deployment.

```bash
kubectl get deploy webserver -o yaml | grep -A 4 strategy
```

```yaml
strategy:
  rollingUpdate:
    maxSurge: 25%
    maxUnavailable: 25%
  type: RollingUpdate
```

**2.** Edit the Deployment to change the strategy to `Recreate`. Remove the `rollingUpdate` lines and change the type.

```bash
kubectl edit deploy webserver
```

```yaml
....
strategy:
  rollingUpdate:            # <-- remove this line
    maxSurge: 25%           # <-- remove this line
    maxUnavailable: 25%     # <-- remove this line
  type: Recreate            # <-- edit to this value
....
```

**3.** Update the Deployment to use a newer version of nginx using the `set` command.

```bash
kubectl set image deploy webserver nginx=nginx:1.23.1-alpine
```

```
Flag has been deprecated, will be removed in the future
deployment.apps/webserver image updated
```

**4.** Verify the new Pods are using the updated image.

```bash
kubectl get pod
```

```
NAME                          READY   STATUS    RESTARTS   AGE
webserver-6cf9cd5c74-qjph4    1/1     Running   0          35s
webserver-6cf9cd5c74-zc6x9    1/1     Running   0          35s
```

```bash
kubectl describe po webserver-6cf9cd5c74-qjph4 | grep Image:
```

```
Image:   nginx:1.23.1-alpine
```

**5.** View the rollout history. You should see two revisions.

```bash
kubectl rollout history deploy webserver
```

```
deployment.apps/webserver
REVISION  CHANGE-CAUSE
1         <none>
2         kubectl set image deploy webserver nginx=nginx:1.23.1-alpine
```

**6.** View the details of each revision. The `Image:` line should be the only difference.

```bash
kubectl rollout history deploy webserver --revision=1
```

```
deployment.apps/webserver with revision #1
Pod Template:
  Labels:  app=webserver
           pod-template-hash=6cbc654ddc
  Containers:
   nginx:
    Image:  nginx:1.22.1
<output_omitted>
```

```bash
kubectl rollout history deploy webserver --revision=2
```

```
....
    Image:  nginx:1.23.1-alpine
....
```

**7.** Roll back the Deployment to the previous version.

```bash
kubectl rollout undo deploy webserver
```

```
deployment.apps/webserver rolled back
```

```bash
kubectl get pod
```

```
NAME                          READY   STATUS    RESTARTS   AGE
webserver-6cbc654ddc-7wb5q    1/1     Running   0          37s
webserver-6cbc654ddc-svbtj    1/1     Running   0          37s
```

```bash
kubectl describe pod webserver-6cbc654ddc-7wb5q | grep Image:
```

```
Image:   nginx:1.22.1
```

**8.** Try the `RollingUpdate` strategy. Edit the Deployment, change the strategy back to `RollingUpdate`, then update the image to `nginx:1.26-alpine`. Observe how pods are replaced one at a time.

```bash
kubectl edit deploy webserver
```

```yaml
....
strategy:
  rollingUpdate:
    maxSurge: 25%
    maxUnavailable: 25%
  type: RollingUpdate
....
```

```bash
kubectl set image deploy webserver nginx=nginx:1.26-alpine
```

**9.** Clean up by deleting the Deployment.

```bash
kubectl delete deploy webserver
```

```
deployment.apps "webserver" deleted
```

---

## Exercise 7.4: Working with DaemonSets

A `DaemonSet` ensures that a single Pod runs on every node in the cluster. It is useful for node-level services like logging, metrics, and security agents.

**1.** Copy `rs.yaml` to a new file and edit it to create a DaemonSet. Change the `kind`, `name`, both `system:` label references, and remove the `replicas:` line.

```bash
cp rs.yaml ds.yaml
vim ds.yaml
```

```yaml
....
kind: DaemonSet         #<-- change from ReplicaSet
....
  name: ds-one          #<-- change name
....
  replicas: 2           #<-- remove this line entirely
....
      system: DaemonSetOne    #<-- edit both references
....
```

**2.** Create the DaemonSet and verify one Pod is running on each node.

```bash
kubectl create -f ds.yaml
```

```
daemonset.apps/ds-one created
```

```bash
kubectl get ds
```

```
NAME     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE-SELECTOR   AGE
ds-one   3         3         3       3            3           <none>          1m
```

```bash
kubectl get pod
```

```
NAME            READY   STATUS    RESTARTS   AGE
ds-one-b1dcv    1/1     Running   0          2m
ds-one-z31r4    1/1     Running   0          2m
```

**3.** Verify the image version running in the Pods.

```bash
kubectl describe pod ds-one-b1dcv | grep Image:
```

```
Image:   nginx:1.22.1
```

---

## Exercise 7.5: Rollout and Rollback using DaemonSet

**1.** View the current `updateStrategy` for the DaemonSet.

```bash
kubectl get ds ds-one -o yaml | grep -A 4 Strategy
```

```yaml
updateStrategy:
  rollingUpdate:
    maxSurge: 0
    maxUnavailable: 1
  type: RollingUpdate
```

**2.** Edit the DaemonSet to change the update strategy to `OnDelete`. This means Pods are only updated when manually deleted.

```bash
kubectl edit ds ds-one
```

```yaml
....
updateStrategy:
  rollingUpdate:
    maxUnavailable: 1
  type: OnDelete    #<-- Edit to this value
status:
....
```

**3.** Update the DaemonSet to use a newer version of nginx.

```bash
kubectl set image ds ds-one nginx=nginx:1.26-alpine
```

```
Flag has been deprecated, will be removed in the future
daemonset.apps/ds-one image updated
```

**4.** Verify the existing Pod still shows the old image — it has not been updated yet because of `OnDelete` strategy.

```bash
kubectl describe po ds-one-b1dcv | grep Image:
```

```
Image:   nginx:1.22.1
```

**5.** Delete one Pod. Wait for its replacement to start, then check the new Pod's image version.

```bash
kubectl delete po ds-one-b1dcv
```

```
pod "ds-one-b1dcv" deleted
```

```bash
kubectl get pod
```

```
NAME            READY   STATUS    RESTARTS   AGE
ds-one-xc86w    1/1     Running   0          19s
ds-one-z31r4    1/1     Running   0          4m8s
```

```bash
kubectl describe po ds-one-xc86w | grep Image:
```

```
Image:   nginx:1.26-alpine
```

**6.** The older Pod still shows the old version.

```bash
kubectl describe po ds-one-z31r4 | grep Image:
```

```
Image:   nginx:1.22.1
```

**7.** View the rollout history for the DaemonSet.

```bash
kubectl rollout history ds ds-one
```

```
daemonset.apps/ds-one
REVISION  CHANGE-CAUSE
1         <none>
2         kubectl set image ds ds-one nginx=nginx:1.26-alpine
```

**8.** View details for each revision.

```bash
kubectl rollout history ds ds-one --revision=1
```

```
daemonsets "ds-one" with revision #1
Pod Template:
  Labels:  system=DaemonSetOne
  Containers:
   nginx:
    Image:  nginx:1.22.1
<output_omitted>
```

```bash
kubectl rollout history ds ds-one --revision=2
```

```
....
    Image:  nginx:1.26-alpine
....
```

**9.** Roll back the DaemonSet to revision 1. Since we are using `OnDelete` strategy there will be no change to running Pods yet.

```bash
kubectl rollout undo ds ds-one --to-revision=1
```

```
daemonset.apps/ds-one rolled back
```

```bash
kubectl describe po ds-one-xc86w | grep Image:
```

```
Image:   nginx:1.26-alpine
```

**10.** Delete the recently updated Pod. The replacement should use the rolled-back image.

```bash
kubectl delete po ds-one-xc86w
```

```
pod "ds-one-xc86w" deleted
```

```bash
kubectl get pod
```

```
NAME            READY   STATUS        RESTARTS   AGE
ds-one-qc72k    1/1     Running       0          10s
ds-one-xc86w    0/1     Terminating   0          12m
ds-one-z31r4    1/1     Running       0          28m
```

```bash
kubectl describe po ds-one-qc72k | grep Image:
```

```
Image:   nginx:1.22.1
```

**11.** View the DaemonSet — the `updateStrategy` is still `OnDelete`. Check the YAML to confirm.

```bash
kubectl describe ds | grep Image:
```

```
Image:   nginx:1.22.1
```

```bash
kubectl get ds ds-one -o yaml
```

```yaml
apiVersion: apps/v1
kind: DaemonSet
....
      terminationGracePeriodSeconds: 30
  updateStrategy:
    type: OnDelete
status:
  currentNumberScheduled: 2
....
```

**12.** Create a second DaemonSet using `RollingUpdate` strategy. Generate the config from the existing DaemonSet, then edit it.

```bash
kubectl get ds ds-one -o yaml > ds2.yaml
vim ds2.yaml
```

```yaml
....
  name: ds-two          #<-- change name (around line 69)
....
  type: RollingUpdate   #<-- change strategy back (around line 100)
....
```

**13.** Create the new DaemonSet and verify the image version.

```bash
kubectl create -f ds2.yaml
```

```
daemonset.apps/ds-two created
```

```bash
kubectl get pod
```

```
NAME            READY   STATUS    RESTARTS   AGE
ds-one-qc72k    1/1     Running   0          28m
ds-one-z31r4    1/1     Running   0          57m
ds-two-10khc    1/1     Running   0          5m
ds-two-kzp9g    1/1     Running   0          5m
```

```bash
kubectl describe po ds-two-10khc | grep Image:
```

```
Image:   nginx:1.22.1
```

**14.** Update the `ds-two` DaemonSet to a newer image version using `edit`.

```bash
kubectl edit ds ds-two
```

```yaml
....
      - image: nginx:1.26-alpine
....
```

**15.** View the DaemonSet age — it should be about 10 minutes old.

```bash
kubectl get ds ds-two
```

```
NAME     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE-SELECTOR   AGE
ds-two   2         2         2       2            2           <none>          10m
```

**16.** View the Pods. The `ds-two` pods should be much newer than the DaemonSet — they were replaced by the rolling update.

```bash
kubectl get pod
```

```
NAME            READY   STATUS    RESTARTS   AGE
ds-one-qc72k    1/1     Running   0          36m
ds-one-z31r4    1/1     Running   0          1h
ds-two-2p8vz    1/1     Running   0          34s
ds-two-81x7k    1/1     Running   0          32s
```

**17.** Verify the new Pods are running the updated image.

```bash
kubectl describe po ds-two-81x7k | grep Image:
```

```
Image:   nginx:1.26-alpine
```

**18.** View the rollout status and history of `ds-two`.

```bash
kubectl rollout status ds ds-two
```

```
daemon set "ds-two" successfully rolled out
```

**19.** Check rollout history.

```bash
kubectl rollout history ds ds-two
```

```
daemonset.apps/ds-two
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

**20.** View detailed revision history.

```bash
kubectl rollout history ds ds-two --revision=1
kubectl rollout history ds ds-two --revision=2
```

**21.** Clean up by removing both DaemonSets.

```bash
kubectl delete ds ds-one ds-two
```

```
daemonset.apps "ds-one" deleted
daemonset.apps "ds-two" deleted
```

---
