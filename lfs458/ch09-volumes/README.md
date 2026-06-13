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
