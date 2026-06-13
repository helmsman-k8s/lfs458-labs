# Chapter 6: API Objects

## Overview

In this lab you will work with:

- Jobs (one-shot, parallel, deadline-bounded)
- CronJobs (scheduled Jobs)
- ConfigMaps and Secrets as API objects

The YAML files are in `~/lfs458/ch06-api-objects/`. Chapters that require editing a file have a completed version in the `solutions/` subfolder.

---

## Lab 6.1 — Jobs

### Create a basic Job

```bash
cp ~/lfs458/ch06-api-objects/job.yaml ~/job.yaml
cat ~/job.yaml
```

Apply it and watch it complete:

```bash
kubectl apply -f ~/job.yaml
kubectl get jobs -w
```

Once complete, check the pod:

```bash
JOB_POD=$(kubectl get pod -l job-name=sleepy -o jsonpath='{.items[0].metadata.name}')
kubectl logs $JOB_POD
kubectl describe job sleepy
```

### Add completions

Edit `~/job.yaml` to run the job **5 times total** by setting `spec.completions: 5`. The solution is at `~/lfs458/ch06-api-objects/solutions/job-completions.yaml`.

```bash
kubectl delete job sleepy
kubectl apply -f ~/job.yaml
kubectl get jobs -w
```

### Add parallelism

Now also set `spec.parallelism: 2` so 2 pods run at a time. The solution is at `~/lfs458/ch06-api-objects/solutions/job-parallelism.yaml`.

```bash
kubectl delete job sleepy
kubectl apply -f ~/job.yaml
kubectl get pods -w   # You should see 2 pods running simultaneously
```

### Add an active deadline

Set `spec.activeDeadlineSeconds: 15` so the job is killed if it hasn't finished in 15 seconds. The solution is at `~/lfs458/ch06-api-objects/solutions/job-deadline.yaml`.

```bash
kubectl delete job sleepy
kubectl apply -f ~/job.yaml
watch kubectl get jobs
```

Observe the job being terminated early with reason `DeadlineExceeded`.

### Clean up

```bash
kubectl delete job sleepy 2>/dev/null; true
```

---

## Lab 6.2 — CronJobs

```bash
cp ~/lfs458/ch06-api-objects/cronjob.yaml ~/cronjob.yaml
cat ~/cronjob.yaml
```

Apply and observe:

```bash
kubectl apply -f ~/cronjob.yaml
kubectl get cronjobs -w
```

The CronJob runs every minute. Wait for the first execution:

```bash
kubectl get jobs --watch
```

Once a Job appears, check its pod's logs:

```bash
CRON_POD=$(kubectl get pod -l app=date-job --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
kubectl logs $CRON_POD
```

### Add a job deadline

Edit `~/cronjob.yaml` to add `spec.jobTemplate.spec.activeDeadlineSeconds: 10` and change the sleep duration so the job exceeds the deadline. The solution is at `~/lfs458/ch06-api-objects/solutions/cronjob-deadline.yaml`.

```bash
kubectl delete cronjob date-job
kubectl apply -f ~/cronjob.yaml
kubectl get jobs -w
```

### Clean up

```bash
kubectl delete cronjob date-job 2>/dev/null; true
```

---

## Lab 6.3 — ConfigMaps

Create a ConfigMap from literal values:

```bash
kubectl create configmap app-config \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=info

kubectl describe configmap app-config
kubectl get configmap app-config -o yaml
```

Use the ConfigMap in a pod as environment variables:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: config-test
spec:
  containers:
  - name: app
    image: nginx
    envFrom:
    - configMapRef:
        name: app-config
EOF
```

Verify the env vars are present:

```bash
kubectl exec config-test -- env | grep -E "APP_ENV|LOG_LEVEL"
```

Clean up:

```bash
kubectl delete pod config-test
kubectl delete configmap app-config
```

---

## Lab 6.4 — Secrets

Create a Secret:

```bash
kubectl create secret generic db-secret \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASSWORD=s3cr3t!

kubectl get secret db-secret -o yaml
```

Notice the `data` values are base64-encoded (not encrypted at rest by default). Decode one:

```bash
kubectl get secret db-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
echo   # newline
```

Clean up:

```bash
kubectl delete secret db-secret
```
