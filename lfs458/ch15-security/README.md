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
