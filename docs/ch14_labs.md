# Chapter 14: Custom Resources

## Overview

In this lab you will:

- Create a Custom Resource Definition (CRD)
- Create instances of the custom resource
- Explore CRD validation and versioning
- Understand how operators use CRDs

---

## Lab 14.1 — Create a CRD

Define a CRD for a fictional `BackupPolicy` resource:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backuppolicies.vega.training
spec:
  group: vega.training
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required:
            - schedule
            - retentionDays
            properties:
              schedule:
                type: string
                description: "Cron expression for backup schedule"
              retentionDays:
                type: integer
                minimum: 1
                maximum: 365
                description: "Number of days to retain backups"
              target:
                type: string
                description: "Target resource or namespace"
  scope: Namespaced
  names:
    plural: backuppolicies
    singular: backuppolicy
    kind: BackupPolicy
    shortNames:
    - bp
EOF
```

Verify the CRD is registered:

```bash
kubectl get crd backuppolicies.vega.training
kubectl api-resources | grep vega
```

---

## Lab 14.2 — Create Custom Resource Instances

Create a `BackupPolicy` object:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: vega.training/v1
kind: BackupPolicy
metadata:
  name: daily-backup
  namespace: default
spec:
  schedule: "0 2 * * *"
  retentionDays: 30
  target: "default"
EOF
```

Work with it using standard kubectl commands:

```bash
kubectl get backuppolicies
kubectl get bp
kubectl describe backuppolicy daily-backup
kubectl get backuppolicy daily-backup -o yaml
```

Create another instance:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: vega.training/v1
kind: BackupPolicy
metadata:
  name: hourly-backup
  namespace: default
spec:
  schedule: "0 * * * *"
  retentionDays: 7
  target: "kube-system"
EOF

kubectl get bp
```

---

## Lab 14.3 — CRD Validation

Try to create an invalid resource (retentionDays exceeds the maximum of 365):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: vega.training/v1
kind: BackupPolicy
metadata:
  name: invalid-backup
  namespace: default
spec:
  schedule: "0 0 * * *"
  retentionDays: 999
EOF
```

You should see a validation error from the API server.

Try one missing the required `schedule` field:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: vega.training/v1
kind: BackupPolicy
metadata:
  name: missing-schedule
  namespace: default
spec:
  retentionDays: 7
EOF
```

Again, a validation error.

---

## Lab 14.4 — Watch and List Custom Resources

```bash
# List with label selector (works the same as built-in resources)
kubectl get bp -l environment=prod 2>/dev/null || echo "No labeled resources"

# Add a label and filter
kubectl label backuppolicy daily-backup environment=prod
kubectl get bp -l environment=prod

# Use jsonpath to extract fields
kubectl get bp daily-backup -o jsonpath='{.spec.schedule}'
echo ""
```

---

## Lab 14.5 — Clean Up

```bash
kubectl delete bp --all
kubectl delete crd backuppolicies.vega.training
```

Verify the CRD and all instances are gone:

```bash
kubectl get crd | grep vega
kubectl api-resources | grep vega
```

---

## Understanding Operators

A **Kubernetes Operator** extends the control plane by:

1. Defining one or more CRDs that represent the desired state of an application
2. Running a controller (a Deployment) that watches those CRDs
3. Reconciling the actual state of the cluster to match the desired state declared in the custom resources

Popular operators include the Prometheus Operator, Cert-Manager, and the CloudNativePG PostgreSQL Operator. The CRD + controller pattern you practiced in this lab is exactly what they use internally.
