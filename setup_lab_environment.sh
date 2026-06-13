#!/bin/bash
# =============================================================================
# LFS458 Lab Environment Setup Script
# Run this on EACH NODE before class (controller, worker1, worker2)
# Ubuntu 24.04 | kubeadm 1.33.1 | containerd | Flannel CNI
# Usage: sudo bash setup_lab_environment.sh guru
# =============================================================================

set -e

LAB_USER="${1:-guru}"
LAB_HOME="/home/${LAB_USER}/lfs458"

echo "=============================================="
echo " LFS458 Lab Environment Setup"
echo " Target user : $LAB_USER"
echo " Lab root    : $LAB_HOME"
echo "=============================================="
echo ""

# Ensure user exists
if ! id "$LAB_USER" &>/dev/null; then
    echo "[0/4] Creating user $LAB_USER..."
    useradd -m -s /bin/bash "$LAB_USER"
    echo "${LAB_USER}:lftr@in" | chpasswd
    echo "    User $LAB_USER created with password: lftr@in"
fi

# -----------------------------------------------------------------------------
# Create folder structure
# -----------------------------------------------------------------------------
echo "[1/4] Creating folder structure..."

FOLDERS=(
    "ch02-basics"
    "ch03-install"
    "ch04-architecture"
    "ch05-api-access"
    "ch06-api-objects"
    "ch07-deployments"
    "ch08-helm"
    "ch09-volumes"
    "ch10-services"
    "ch11-ingress"
    "ch12-scheduling"
    "ch13-troubleshoot"
    "ch14-crd"
    "ch15-security"
    "ch16-ha"
)

mkdir -p "$LAB_HOME"
for folder in "${FOLDERS[@]}"; do
    mkdir -p "$LAB_HOME/$folder"
done

echo "    Folders created."

# -----------------------------------------------------------------------------
# Stage lab files
# -----------------------------------------------------------------------------
echo "[2/4] Staging lab files..."

# --- ch03-install ---

cat > "$LAB_HOME/ch03-install/kubeadm-config.yaml" << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: 1.33.1
controlPlaneEndpoint: "controller:6443"
networking:
  podSubnet: 10.244.0.0/16
EOF

cat > "$LAB_HOME/ch03-install/README.md" << 'EOF'
# Chapter 3 - Installation and Configuration

## Exercises
- 3.1 Install Kubernetes
- 3.2 Grow the Cluster
- 3.3 Finish Cluster Setup
- 3.4 Deploy a Simple Application
- 3.5 Access from Outside the Cluster

## Pre-staged files
- kubeadm-config.yaml - used during kubeadm init
- cilium-cni.yaml     - Flannel CNI manifest (applied after kubeadm init)

## Notes
- Pod subnet: 10.244.0.0/16
- Control plane endpoint: controller:6443
EOF

# --- ch04-architecture ---

cat > "$LAB_HOME/ch04-architecture/low-resource-range.yaml" << 'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: low-resource-range
spec:
  limits:
  - default:
      cpu: 1
      memory: 500Mi
    defaultRequest:
      cpu: 0.5
      memory: 100Mi
    type: Container
EOF

cat > "$LAB_HOME/ch04-architecture/README.md" << 'EOF'
# Chapter 4 - Kubernetes Architecture

## Exercises
- 4.1 Basic Node Maintenance (drain, cordon, uncordon)
- 4.2 Working with CPU and Memory Constraints
- 4.3 Resource Limits for a Namespace

## Pre-staged files
- low-resource-range.yaml - LimitRange for Ex 4.3
EOF

# --- ch05-api-access ---

cat > "$LAB_HOME/ch05-api-access/curlpod.json" << 'EOF'
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
    "containers": [
      {
        "name": "curlcontainer",
        "image": "alpine/curl",
        "command": ["sleep", "3600"]
      }
    ]
  }
}
EOF

cat > "$LAB_HOME/ch05-api-access/README.md" << 'EOF'
# Chapter 5 - APIs and Access

## Exercises
- 5.1 Configuring TLS Access
- 5.2 Explore API Calls

## Pre-staged files
- curlpod.json - Pod spec used for curl-based API exploration
EOF

# --- ch06-api-objects ---

cat > "$LAB_HOME/ch06-api-objects/job.yaml" << 'EOF'
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
EOF

cat > "$LAB_HOME/ch06-api-objects/cronjob.yaml" << 'EOF'
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
EOF

cat > "$LAB_HOME/ch06-api-objects/README.md" << 'EOF'
# Chapter 6 - API Objects

## Exercises
- 6.1 RESTful API Access
- 6.2 Using the Proxy
- 6.3 Working with Jobs

## Pre-staged files
- job.yaml     - Job manifest for Ex 6.3
- cronjob.yaml - CronJob manifest for Ex 6.3
EOF

# --- ch07-deployments ---

cat > "$LAB_HOME/ch07-deployments/rs.yaml" << 'EOF'
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
EOF

cat > "$LAB_HOME/ch07-deployments/README.md" << 'EOF'
# Chapter 7 - Managing State with Deployments

## Exercises
- 7.1 Working with ReplicaSets
- 7.2 Working with Deployments
- 7.3 Rollout and Rollback using Deployment
- 7.4 Working with DaemonSets
- 7.5 Rollout and Rollback using DaemonSet

## Pre-staged files
- rs.yaml - ReplicaSet manifest for Ex 7.1
EOF

# --- ch08-helm ---

cat > "$LAB_HOME/ch08-helm/hpa-deploy.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-hpa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-hpa
  template:
    metadata:
      labels:
        app: nginx-hpa
    spec:
      containers:
      - name: nginx
        image: nginx:1.22.1
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
        ports:
        - containerPort: 80
EOF

cat > "$LAB_HOME/ch08-helm/README.md" << 'EOF'
# Chapter 8 - Helm and Kustomize

## Exercises
- 8.1 Working with Helm and Charts
- 8.2 Horizontal Pod Autoscaler (HPA)
- 8.3 Working with Kustomize

## Pre-staged files
- hpa-deploy.yaml - Deployment with resource requests for HPA exercise
EOF

# --- ch09-volumes ---

cat > "$LAB_HOME/ch09-volumes/PVol.yaml" << 'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pvvol-1
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /opt/sfw
    server: controller
    readOnly: false
EOF

cat > "$LAB_HOME/ch09-volumes/pvc.yaml" << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-one
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 200Mi
EOF

cat > "$LAB_HOME/ch09-volumes/nfs-pod.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-nfs
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
    spec:
      containers:
      - image: nginx
        imagePullPolicy: Always
        name: nginx
        volumeMounts:
        - name: nfs-vol
          mountPath: /opt
        ports:
        - containerPort: 80
          protocol: TCP
      volumes:
      - name: nfs-vol
        persistentVolumeClaim:
          claimName: pvc-one
EOF

cat > "$LAB_HOME/ch09-volumes/simpleshell.yaml" << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: shell-demo
spec:
  containers:
  - name: nginx
    image: nginx
    env:
    - name: ilike
      valueFrom:
        configMapKeyRef:
          name: colors
          key: favorite
EOF

cat > "$LAB_HOME/ch09-volumes/car-map.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: fast-car
  namespace: default
data:
  car.make: Ford
  car.model: Mustang
  car.trim: Shelby
EOF

cat > "$LAB_HOME/ch09-volumes/storage-quota.yaml" << 'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storagequota
spec:
  hard:
    persistentvolumeclaims: "10"
    requests.storage: "500Mi"
EOF

cat > "$LAB_HOME/ch09-volumes/pvc-sc.yaml" << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-two
spec:
  storageClassName: nfs-client
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 200Mi
EOF

cat > "$LAB_HOME/ch09-volumes/pod-sc.yaml" << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web-server
spec:
  containers:
  - image: nginx
    name: web-container
    volumeMounts:
    - name: nfs-volume
      mountPath: /usr/share/nginx/html
  volumes:
  - name: nfs-volume
    persistentVolumeClaim:
      claimName: pvc-two
EOF

cat > "$LAB_HOME/ch09-volumes/README.md" << 'EOF'
# Chapter 9 - Volumes and Data

## Exercises
- 9.1 Create a ConfigMap
- 9.2 Creating a Persistent NFS Volume (PV)
- 9.3 Creating a Persistent Volume Claim (PVC)
- 9.4 Using a ResourceQuota to Limit PVC Count
- 9.5 Using StorageClass to Dynamically Provision a Volume

## Pre-staged files
- PVol.yaml          - PersistentVolume (NFS-backed, server: controller)
- pvc.yaml           - PersistentVolumeClaim
- nfs-pod.yaml       - Deployment that mounts the PVC
- simpleshell.yaml   - Pod that uses a ConfigMap env var
- car-map.yaml       - ConfigMap for volume mount exercise
- storage-quota.yaml - ResourceQuota
- pvc-sc.yaml        - PVC using StorageClass
- pod-sc.yaml        - Pod using StorageClass PVC
EOF

# --- ch10-services ---

cat > "$LAB_HOME/ch10-services/nettool.yaml" << 'EOF'
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
EOF

cat > "$LAB_HOME/ch10-services/nginx-one.yaml" << 'EOF'
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
        - containerPort: 80
          protocol: TCP
      nodeSelector:
        system: secondOne
EOF

cat > "$LAB_HOME/ch10-services/README.md" << 'EOF'
# Chapter 10 - Services

## Exercises
- 10.1 Deploy A New Service
- 10.2 Configure a NodePort
- 10.3 Working with CoreDNS
- 10.4 Use Labels to Manage Resources

## Pre-staged files
- nettool.yaml   - Ubuntu pod for DNS/network testing
- nginx-one.yaml - Deployment for service exercises
EOF

# --- ch11-ingress ---

cat > "$LAB_HOME/ch11-ingress/ingress.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-test
  annotations:
    nginx.ingress.kubernetes.io/service-upstream: "true"
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: www.external.com
    http:
      paths:
      - backend:
          service:
            name: web-one
            port:
              number: 80
        path: /
        pathType: ImplementationSpecific
EOF

cat > "$LAB_HOME/ch11-ingress/nettool.yaml" << 'EOF'
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
EOF

cat > "$LAB_HOME/ch11-ingress/books.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: books
spec:
  replicas: 2
  selector:
    matchLabels:
      app: books
  template:
    metadata:
      labels:
        app: books
    spec:
      containers:
      - name: books
        image: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: books
spec:
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: books
EOF

cat > "$LAB_HOME/ch11-ingress/gateway.yaml" << 'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shop
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    port: 80
    protocol: HTTP
EOF

cat > "$LAB_HOME/ch11-ingress/httproute.yaml" << 'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: books
spec:
  parentRefs:
  - name: shop
  hostnames:
  - "shop.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: books
      port: 80
EOF

cat > "$LAB_HOME/ch11-ingress/README.md" << 'EOF'
# Chapter 11 - Ingress

## Exercises
- 11.1 Service Mesh (Linkerd)
- 11.2 Ingress Controller (NGINX via Helm)
- 11.3 Gateway API (NGINX Gateway Fabric)

## Pre-staged files
- ingress.yaml   - Ingress resource for Ex 11.2
- nettool.yaml   - Ubuntu pod for testing
- books.yaml     - Deployment + Service for Gateway API exercise
- gateway.yaml   - Gateway resource for Ex 11.3
- httproute.yaml - HTTPRoute resource for Ex 11.3
EOF

# --- ch12-scheduling ---

cat > "$LAB_HOME/ch12-scheduling/vip.yaml" << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vip
spec:
  containers:
  - name: vip1
    image: busybox
    args:
    - sleep
    - "1000000"
  - name: vip2
    image: busybox
    args:
    - sleep
    - "1000000"
  - name: vip3
    image: busybox
    args:
    - sleep
    - "1000000"
  - name: vip4
    image: busybox
    args:
    - sleep
    - "1000000"
  nodeSelector:
    status: vip
EOF

cat > "$LAB_HOME/ch12-scheduling/taint.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: taint-deployment
spec:
  replicas: 8
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.20.1
        ports:
        - containerPort: 80
EOF

cat > "$LAB_HOME/ch12-scheduling/README.md" << 'EOF'
# Chapter 12 - Scheduling

## Exercises
- 12.1 Assign Pods Using Labels (nodeSelector)
- 12.2 Using Taints to Control Pod Deployment

## Pre-staged files
- vip.yaml    - Pod with nodeSelector for Ex 12.1
- taint.yaml  - Deployment for taint exercise Ex 12.2

## Notes
- Label nodes before scheduling: kubectl label node worker1 status=vip
EOF

# --- ch13-troubleshoot ---

cat > "$LAB_HOME/ch13-troubleshoot/README.md" << 'EOF'
# Chapter 13 - Logging and Troubleshooting

## Exercises
- 13.1 Review Log File Locations
- 13.2 Viewing Logs Output
- 13.3 Adding Tools for Monitoring and Metrics

## Key log locations
- /var/log/pods/
- /var/log/containers/
- journalctl -u kubelet
- kubectl logs <pod>
- kubectl describe pod <pod>
EOF

# --- ch14-crd ---

cat > "$LAB_HOME/ch14-crd/crd.yaml" << 'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com
spec:
  group: stable.example.com
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
              properties:
                cronSpec:
                  type: string
                image:
                  type: string
                replicas:
                  type: integer
  scope: Namespaced
  names:
    plural: crontabs
    singular: crontab
    kind: CronTab
    shortNames:
    - ct
EOF

cat > "$LAB_HOME/ch14-crd/new-crontab.yaml" << 'EOF'
apiVersion: "stable.example.com/v1"
kind: CronTab
metadata:
  name: new-cron-object
spec:
  cronSpec: "*/5 * * * *"
  image: some-cron-image
EOF

cat > "$LAB_HOME/ch14-crd/README.md" << 'EOF'
# Chapter 14 - Custom Resource Definitions

## Exercises
- 14.1 Create a Custom Resource Definition

## Pre-staged files
- crd.yaml          - CRD definition for CronTab resource
- new-crontab.yaml  - Instance of the custom CronTab resource
EOF

# --- ch15-security ---

cat > "$LAB_HOME/ch15-security/role-dev.yaml" << 'EOF'
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: development
  name: developer
rules:
- apiGroups: ["", "extensions", "apps"]
  resources: ["deployments", "replicasets", "pods"]
  verbs: ["list", "get", "watch", "create", "update", "patch", "delete"]
EOF

cat > "$LAB_HOME/ch15-security/rolebind.yaml" << 'EOF'
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
EOF

cat > "$LAB_HOME/ch15-security/README.md" << 'EOF'
# Chapter 15 - Security

## Exercises
- 15.1 Working with TLS
- 15.2 Authentication and Authorization (RBAC)
- 15.3 Admission Controllers

## Pre-staged files
- role-dev.yaml   - RBAC Role for development namespace
- rolebind.yaml   - RoleBinding for DevDan user

## Notes
- Always back up kube-apiserver.yaml before editing:
  sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/
EOF

# --- ch16-ha ---

cat > "$LAB_HOME/ch16-ha/README.md" << 'EOF'
# Chapter 16 - High Availability

## Exercises
- 16.1 High Availability Steps (overview)
- 16.2 Detailed Steps

## Notes
- This chapter requires 3 additional nodes beyond the standard lab.
- Delivered as instructor demo.
- Key tools: HAProxy as load balancer, kubeadm join --control-plane
EOF

# -----------------------------------------------------------------------------
# Download Flannel CNI manifest
# -----------------------------------------------------------------------------
echo "[3/4] Downloading Flannel CNI manifest..."
FLANNEL_DEST="$LAB_HOME/ch03-install/cilium-cni.yaml"
if curl -sL \
    https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml \
    -o "$FLANNEL_DEST"; then
    echo "    Flannel manifest downloaded successfully."
else
    echo "    WARNING: Download failed. Run manually:"
    echo "    curl -L https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml \\"
    echo "      -o $FLANNEL_DEST"
fi

# -----------------------------------------------------------------------------
# Fix permissions
# -----------------------------------------------------------------------------
echo "[4/4] Setting permissions..."
chown -R "${LAB_USER}:${LAB_USER}" "$LAB_HOME"
find "$LAB_HOME" -type f | xargs chmod 644 2>/dev/null || true
find "$LAB_HOME" -type d | xargs chmod 755

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo " Setup complete!"
echo "=============================================="
echo ""
echo " Lab root   : $LAB_HOME"
echo " Folders    : $(find $LAB_HOME -mindepth 1 -maxdepth 1 -type d | wc -l)"
echo " YAML files : $(find $LAB_HOME -name '*.yaml' | wc -l)"
echo " JSON files : $(find $LAB_HOME -name '*.json' | wc -l)"
echo ""
echo " Verify with:"
echo "   ls -la $LAB_HOME"
echo "   find $LAB_HOME -name '*.yaml' | sort"
echo ""
