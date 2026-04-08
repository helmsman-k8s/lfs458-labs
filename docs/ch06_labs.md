# Chapter 6: API Objects

**Working directory: `~/lfs458/ch06-api-objects/`**

---

## Exercise 6.1: RESTful API Access

We will use the `curl` command to make API requests to the cluster using a Bearer token. Once we know the IP and port of the API server we can retrieve cluster data in a RESTful manner.

```bash
cd ~/lfs458/ch06-api-objects/
```

**1.** Get the overall cluster configuration and find the API server address and port.

```bash
kubectl config view
```

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: DATA+OMITTED
    server: https://controller:6443
  name: kubernetes
<output_omitted>
```

**2.** Create a Bearer token from the default service account. Token secrets are no longer created automatically in recent Kubernetes releases so we generate one explicitly.

```bash
export token=$(kubectl create token default)
```

**3.** Test basic API access using the token. Pass the server name and port and use `-k` to skip certificate verification.

```bash
curl https://controller:6443/apis --header "Authorization: Bearer $token" -k
```

```json
{
  "kind": "APIGroupList",
  "apiVersion": "v1",
  "groups": [
    {
      "name": "apiregistration.k8s.io",
      "versions": [
        {
          "groupVersion": "apiregistration.k8s.io/v1",
          "version": "v1"
        }
      ],
<output_omitted>
```

**4.** Try the same command but look at API v1. Note the path has changed from `/apis` to `/api`.

```bash
curl https://controller:6443/api/v1 --header "Authorization: Bearer $token" -k
```

```
<output_omitted>
```

**5.** Now try to get a list of namespaces. This will return an error — the default service account does not have RBAC authorization to list namespaces.

```bash
curl https://controller:6443/api/v1/namespaces \
  --header "Authorization: Bearer $token" -k
```

```json
<output_omitted>
  "message": "namespaces is forbidden: User \"system:serviceaccount:default...
<output_omitted>
```

---

## Exercise 6.2: Using the Proxy

Another way to interact with the Kubernetes API is via a local proxy. The proxy runs from a node or within a Pod via a sidecar and handles authentication on your behalf. If a `curl` request works through the proxy but not directly, the issue is authentication rather than connectivity.

**1.** Review the proxy help output to understand the available options.

```bash
kubectl proxy -h
```

```
Creates a proxy server or application-level gateway between localhost
and the Kubernetes API Server. It also allows serving static content
over specified HTTP path. All incoming data enters through one port
and gets forwarded to the remote kubernetes API Server port, except
for the path matching the static content path.

Examples:
  # To proxy all of the kubernetes api and nothing else, use:
  $ kubectl proxy --api-prefix=/
<output_omitted>
```

**2.** Start the proxy in the background with a full API prefix. Note the process ID — you will need it to stop the proxy later.

```bash
kubectl proxy --api-prefix=/ &
```

```
[1] 22500
Starting to serve on 127.0.0.1:8001
```

**3.** Use `curl` through the proxy. The output should be the same as the direct API call but may be formatted differently. No token or certificate flags are needed.

```bash
curl http://127.0.0.1:8001/api/
```

```
<output_omitted>
```

**4.** Now try to retrieve namespaces through the proxy. This should work because the proxy uses the cluster admin credentials.

```bash
curl http://127.0.0.1:8001/api/v1/namespaces
```

```json
{
  "kind": "NamespaceList",
  "apiVersion": "v1",
  "metadata": {
    "selfLink": "/api/v1/namespaces",
    "resourceVersion": "86902"
  },
<output_omitted>
```

**5.** Stop the proxy using the process ID from step 2. Your process ID will be different.

```bash
kill 22500
```

---

## Exercise 6.3: Working with Jobs

While most API objects run continuously, a `Job` runs a Pod to completion a specified number of times. A `CronJob` creates Jobs on a schedule using standard Linux cron syntax.

---

### Create a Job

**1.** The `job.yaml` file is already staged in your lab folder. Review it.

```bash
cat ~/lfs458/ch06-api-objects/job.yaml
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sleepy
spec:
  template:
    spec:
      containers:
      - name: resting
        image: busybox
        command: ["/bin/sleep"]
        args: ["3"]
      restartPolicy: Never
```

**2.** Create the Job and verify it. Check the output a few seconds in — you may catch it mid-run — then again after it completes.

```bash
kubectl create -f job.yaml
```

```
job.batch/sleepy created
```

```bash
kubectl get job
```

```
NAME     STATUS    COMPLETIONS   DURATION   AGE
sleepy   Running    0/1           3s         3s
```

```bash
kubectl describe jobs.batch sleepy
```

```
Name:         sleepy
Namespace:    default
Parallelism:  1
Completions:  1
Start Time:   Thu, 23 Aug 2024 10:47:53 +0000
Completed At: Thu, 23 Aug 2024 10:48:00 +0000
Duration:     5s
Pods Statuses: 0 Running / 1 Succeeded / 0 Failed
<output_omitted>
```

```bash
kubectl get job
```

```
NAME     STATUS    COMPLETIONS   DURATION   AGE
sleepy   Complete   1/1           5s         17s
```

**3.** View the Job configuration in YAML format. Note the `backoffLimit`, `completions`, and `parallelism` fields — we will use these next.

```bash
kubectl get jobs.batch sleepy -o yaml
```

```yaml
<output_omitted>
spec:
  backoffLimit: 6
  completions: 1
  parallelism: 1
  selector:
<output_omitted>
```

**4.** Delete the Job as it has aged past completion.

```bash
kubectl delete jobs.batch sleepy
```

```
job.batch "sleepy" deleted
```

**5.** Edit `job.yaml` and add `completions: 5` to the spec. This will require the Job to run 5 successful Pods.

```bash
vim job.yaml
```

```yaml
<output_omitted>
metadata:
  name: sleepy
spec:
  completions: 5    #<-- Add this line
  template:
<output_omitted>
```

**6.** Create the Job again. Watch the completions count increase from 0 to 5.

```bash
kubectl create -f job.yaml
```

```
job.batch/sleepy created
```

```bash
kubectl get jobs.batch
```

```
NAME     STATUS    COMPLETIONS   DURATION   AGE
sleepy   Running    0/5           5s         5s
```

**7.** View the Pods as the Job runs.

```bash
kubectl get pods
```

```
NAME            READY   STATUS      RESTARTS   AGE
sleepy-z5tnh    0/1     Completed   0          8s
sleepy-zd692    1/1     Running     0          3s
<output_omitted>
```

**8.** Wait until all completions finish then delete the Job.

```bash
kubectl get jobs
```

```
NAME     STATUS    COMPLETIONS   DURATION   AGE
sleepy   Complete   5/5           26s        10m
```

```bash
kubectl delete jobs.batch sleepy
```

```
job.batch "sleepy" deleted
```

**9.** Edit `job.yaml` and add `parallelism: 2` so two Pods run at the same time.

```bash
vim job.yaml
```

```yaml
....
spec:
  completions: 5
  parallelism: 2    #<-- Add this line
  template:
....
```

**10.** Create the Job. You should see two Pods running simultaneously until all 5 completions are reached.

```bash
kubectl create -f job.yaml
```

```
job.batch/sleepy created
```

```bash
kubectl get pods
```

```
NAME            READY   STATUS    RESTARTS   AGE
sleepy-8xwpc    1/1     Running   0          5s
sleepy-xjqnf    1/1     Running   0          5s
<output_omitted>
```

```bash
kubectl get jobs
```

```
NAME     STATUS    COMPLETIONS   DURATION   AGE
sleepy   Running    3/5           11s        11s
```

**11.** Add `activeDeadlineSeconds: 15` to stop the Job after 15 seconds regardless of completions. Also increase the sleep to 5 seconds to ensure the deadline is hit.

```bash
vim job.yaml
```

```yaml
....
spec:
  completions: 5
  parallelism: 2
  activeDeadlineSeconds: 15    #<-- Add this line
  template:
    spec:
      containers:
      - name: resting
        image: busybox
        command: ["/bin/sleep"]
        args: ["5"]            #<-- Edit from "3" to "5"
....
```

**12.** Delete and recreate the Job. It should run for 15 seconds then stop — usually completing around 3/5.

```bash
kubectl delete jobs.batch sleepy
```

```
job.batch "sleepy" deleted
```

```bash
kubectl create -f job.yaml
```

```
job.batch/sleepy created
```

```bash
kubectl get jobs
```

```
NAME     STATUS    COMPLETIONS   DURATION   AGE
sleepy   1/5           6s         6s
```

```bash
kubectl get jobs
```

```
NAME     STATUS    COMPLETIONS   DURATION   AGE
sleepy   Running    3/5           16s        16s
```

**13.** View the `status.message` in the Job YAML to confirm it was stopped by the deadline.

```bash
kubectl get job sleepy -o yaml
```

```yaml
<output_omitted>
status:
  conditions:
  - lastProbeTime: 2024-08-23T10:48:00Z
    lastTransitionTime: 2024-08-23T10:48:00Z
    message: Job was active longer than specified deadline
    reason: DeadlineExceeded
    status: "True"
    type: Failed
  failed: 2
  startTime: 2024-08-23T10:48:00Z
  succeeded: 3
```

**14.** Delete the Job.

```bash
kubectl delete jobs.batch sleepy
```

```
job.batch "sleepy" deleted
```

---

### Create a CronJob

A `CronJob` creates a watch loop that generates a batch Job on your behalf when the scheduled time becomes true. It uses the same time syntax as a standard Linux cron job.

**1.** The `cronjob.yaml` file is already staged in your lab folder. Review it.

```bash
cat ~/lfs458/ch06-api-objects/cronjob.yaml
```

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sleepy
spec:
  schedule: "*/2 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: resting
            image: busybox
            command: ["/bin/sleep"]
            args: ["5"]
          restartPolicy: Never
```

**2.** Create the CronJob and verify it exists. No Jobs will run immediately — wait two minutes.

```bash
kubectl create -f cronjob.yaml
```

```
cronjob.batch/sleepy created
```

```bash
kubectl get cronjobs.batch
```

```
NAME     SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
sleepy   */2 * * * *   False     0        <none>          8s
```

```bash
kubectl get jobs.batch
```

```
No resources found.
```

**3.** After two minutes, Jobs will start spawning.

```bash
kubectl get cronjobs.batch
```

```
NAME     SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
sleepy   */2 * * * *   False     0        21s             2m1s
```

```bash
kubectl get jobs.batch
```

```
NAME                STATUS    COMPLETIONS   DURATION   AGE
sleepy-1539722040   Complete   1/1           5s         18s
```

```bash
kubectl get jobs.batch
```

```
NAME                STATUS    COMPLETIONS   DURATION   AGE
sleepy-1539722040   Complete   1/1           5s         5m17s
sleepy-1539722160   Complete   1/1           6s         3m17s
sleepy-1539722280   Complete   1/1           6s         77s
```

**4.** Edit the CronJob to add `activeDeadlineSeconds: 10` to the job template spec, and change the sleep argument to 30 seconds. This ensures any job running longer than 10 seconds is terminated.

```bash
vim cronjob.yaml
```

```yaml
....
  jobTemplate:
    spec:
      template:
        spec:
          activeDeadlineSeconds: 10    #<-- Add this line
          containers:
          - name: resting
            image: busybox
            command: ["/bin/sleep"]
            args: ["30"]               #<-- Edit from "5" to "30"
          restartPolicy: Never
....
```

**5.** Delete and recreate the CronJob. Watch as Jobs are created but terminated by the deadline timer.

```bash
kubectl delete cronjobs.batch sleepy
```

```
cronjob.batch "sleepy" deleted
```

```bash
kubectl create -f cronjob.yaml
```

```
cronjob.batch/sleepy created
```

```bash
kubectl get jobs
```

```
NAME                STATUS    COMPLETIONS   DURATION   AGE
sleepy-1539723240   Running    0/1           61s        61s
```

```bash
kubectl get cronjobs.batch
```

```
NAME     SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
sleepy   */2 * * * *   False     1        72s             94s
```

```bash
kubectl get jobs
```

```
NAME                STATUS    COMPLETIONS   DURATION   AGE
sleepy-1539723240   Running    0/1           2m19s      2m19s
sleepy-1539723360   Running    0/1           19s        19s
```

```bash
kubectl get cronjobs.batch
```

```
NAME     SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
sleepy   */2 * * * *   False     2        31s             2m53s
```

**6.** Clean up by deleting the CronJob. Deleting a CronJob also removes its associated Jobs and Pods.

```bash
kubectl delete cronjobs.batch sleepy
```

```
cronjob.batch "sleepy" deleted
```

---
