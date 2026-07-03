# Chapter 12 - Scheduling

## Exercises
- 12.1 Assign Pods Using Labels (nodeSelector)
- 12.2 Using Taints to Control Pod Deployment

## Emergency fallback files (solutions/)
- solutions/ssd-pod.yaml        - Pod with nodeSelector (Lab 12.1)
- solutions/affinity-pod.yaml   - Pod with nodeAffinity (Lab 12.1)
- solutions/tolerates-gpu.yaml  - Deployment with toleration (Lab 12.2)

## Notes
- All resources are created inline in the lab guide.
- Label nodes before scheduling: kubectl label node worker1 status=vip
