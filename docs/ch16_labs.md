# Chapter 16: High Availability

**Working directory: `~/lfs458/ch16-ha/`**

> **Lab Environment Note:** This chapter requires **three additional nodes** beyond the standard two-node lab: one HAProxy load balancer node, and two additional control plane nodes (`secondcp` and `thirdcp`). If your classroom environment does not provision these extra nodes, follow along with the steps conceptually — the commands and configurations shown are what you would run in a production HA scenario.

---

## Exercise 16.1: High Availability Steps (Summary)

The high-level steps to build a highly available Kubernetes cluster are:

**1.** Deploy an HAProxy load balancer on the proxy node, initially forwarding only to the existing CP.

**2.** Install Kubernetes software on the second and third CP nodes (same steps as Chapter 3, up to but not including `kubeadm init`).

**3.** Use `kubeadm join` on the second CP with `--control-plane` to add it to the cluster.

**4.** Join the third CP using the same command, changing `--node-name` to `thirdcp`.

**5.** Update the HAProxy configuration to load-balance across all three CP nodes.

**6.** Temporarily shut down the first CP and observe automatic failover in the etcd logs and HAProxy stats.

---

## Exercise 16.2: Detailed Steps

### Deploy a Load Balancer

**1.** On the **proxy node**, update and install HAProxy.

```bash
sudo apt-get update ; sudo apt-get install -y haproxy vim
```

**2.** Edit the HAProxy configuration file. Add TCP frontend/backend blocks. Comment out the second and third CP nodes until they are ready.

```bash
sudo vim /etc/haproxy/haproxy.cfg
```

```
....
defaults
        log global           #<-- Edit these three lines starting around line 23
        option tcplog
        mode tcp
....
        errorfile 503 /etc/haproxy/errors/503.http
        errorfile 504 /etc/haproxy/errors/504.http

frontend proxynode                    #<-- Add to bottom of file
   bind *:80
   bind *:6443
   stats uri /proxystats
   default_backend k8sServers

backend k8sServers
   balance roundrobin
   server controller 192.168.2.10:6443 check      #<-- Edit with your CP IP
#  server secondcp 192.168.2.11:6443 check   #<-- Comment out until ready
#  server thirdcp  192.168.2.12:6443 check   #<-- Comment out until ready

listen stats
   bind :9999
   mode http
   stats enable
   stats hide-version
   stats uri /stats
```

**3.** Restart HAProxy and verify both frontend and backend proxies report as started.

```bash
sudo systemctl restart haproxy.service
sudo systemctl status haproxy.service
```

```
Aug 08 18:43:08 ha-proxy systemd[1]: Starting HAProxy Load Balancer...
Aug 08 18:43:08 ha-proxy systemd[1]: Started HAProxy Load Balancer.
Aug 08 18:43:08 ha-proxy haproxy[13603]: Proxy proxynode started.
Aug 08 18:43:08 ha-proxy haproxy[13603]: Proxy k8sServers started.
```

**4.** On the **CP node**, update `/etc/hosts` to point the `controller` alias at the proxy IP instead of the CP IP directly.

```bash
sudo vim /etc/hosts
```

```
192.168.2.20 controller      #<-- Add alias pointing to proxy IP
#192.168.2.10 controller     #<-- Comment out the old direct alias
127.0.0.1 localhost
....
```

**5.** Find the proxy's public IP and open a browser to the HAProxy stats page. Leave it open and refresh as you work through the following steps.

```bash
curl ifconfig.io
```

Browse to: `http://<proxy-public-ip>:9999/stats`

**6.** From the CP node, verify the cluster is still accessible via the proxy.

```bash
kubectl get nodes
```

```
NAME     STATUS   ROLES           AGE    VERSION
controller       Ready    control-plane   2d6h   v1.34.1
worker1   Ready    <none>          2d3h   v1.34.1
```

---

### Install Software on New CP Nodes

**1.** On the **second CP** and **third CP** nodes, install the Kubernetes software using the same steps from Chapter 3 — up to but **not including** `kubeadm init` or `kubeadm join`. Use the `k8sWorker.sh` script from the course tarball as a reference, edited to use the correct Kubernetes version.

**2.** Ensure all three CP nodes have `/etc/hosts` entries pointing `controller` to the proxy IP.

```bash
sudo vim /etc/hosts
```

```
192.168.2.20 controller
127.0.0.1 localhost
....
```

---

### Join Control Plane Nodes

**1.** Ensure `/etc/hosts` on **all nodes** (controller, secondcp, thirdcp, worker1, proxy) resolves `controller` to the proxy IP.

**2.** On the **first CP**, generate the tokens and hashes needed for the join command.

**3.** Create a new bootstrap token.

```bash
sudo kubeadm token create
```

```
jasg79.fdh4p279l320cz1g
```

**4.** Generate the CA certificate hash.

```bash
openssl x509 -pubkey \
  -in /etc/kubernetes/pki/ca.crt | openssl rsa \
  -pubin -outform der 2>/dev/null | openssl dgst \
  -sha256 -hex | sed 's/^.* //'
```

```
f62bf97d4fba6876e4c3ff645df3fca969c06169dee3865aab9d0bca8ec9f8cd
```

**5.** Generate a new certificate key so the new CPs can download the cluster certificates.

```bash
sudo kubeadm init phase upload-certs --upload-certs
```

```
[upload-certs] Storing the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
[upload-certs] Using certificate key:
5610b6f73593049acddee6b59994360aa4441be0c0d9277c76705d129ba18d65
```

**6.** On the **second CP**, run the join command using all three outputs above. Paste one line at a time if using Windows or macOS to avoid paste issues.

```bash
sudo kubeadm join controller:6443 \
  --token jasg79.fdh4p279l320cz1g \
  --discovery-token-ca-cert-hash sha256:f62bf97d4fba6876e4c3ff645df3fca969c06169dee3865aab9d0bca8ec9f8cd \
  --control-plane --node-name=secondcp \
  --certificate-key 5610b6f73593049acddee6b59994360aa4441be0c0d9277c76705d129ba18d65
```

```
[preflight] Running pre-flight checks
<output_omitted>
```

**7.** From the **first CP**, verify the second CP joined successfully.

```bash
kubectl get nodes
```

```
NAME       STATUS   ROLES           AGE    VERSION
controller         Ready    control-plane   2d6h   v1.34.1
secondcp   Ready    control-plane   10m    v1.34.1
worker1     Ready    <none>          2d3h   v1.34.1
```

**8.** Repeat the join command on the **third CP**, changing `--node-name` to `thirdcp`. Then verify all three control planes are listed.

```bash
kubectl get nodes
```

```
NAME       STATUS   ROLES           AGE    VERSION
controller         Ready    control-plane   2d6h   v1.34.1
secondcp   Ready    control-plane   13m    v1.34.1
thirdcp    Ready    control-plane   3m     v1.34.1
worker1     Ready    <none>          2d3h   v1.34.1
```

**9.** On each new CP node, copy the kubeconfig as suggested in the join output.

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**10.** On the **proxy node**, update HAProxy to include all three CPs and restart.

```bash
sudo vim /etc/haproxy/haproxy.cfg
```

```
....
backend k8sServers
   balance roundrobin
   server controller        192.168.2.10:6443 check
   server secondcp  192.168.2.11:6443 check   #<-- Uncomment
   server thirdcp   192.168.2.12:6443 check   #<-- Uncomment
....
```

```bash
sudo systemctl restart haproxy.service
```

**11.** Refresh the HAProxy stats page — all three CP backends should now appear. As you run `kubectl get nodes`, the byte count on each backend should increase, showing traffic is distributed.

---

### Verify etcd Cluster Health

**12.** View the etcd pods and tail the logs of the newest etcd instance. Leave this running in a separate terminal while you proceed.

```bash
kubectl -n kube-system get pods | grep etcd
```

```
etcd-controller         1/1   Running   0   2d12h
etcd-secondcp   1/1   Running   0   22m
etcd-thirdcp    1/1   Running   0   18m
```

```bash
kubectl -n kube-system logs -f etcd-thirdcp
```

```
2025-10-09 01:58:03.768858 I | mvcc: store.index: compact 300473
2025-10-09 01:58:03.770773 I | mvcc: finished scheduled compaction at 300473 (took 1.286565ms)
....
```

**13.** Exec into the `etcd-controller` pod and query the cluster endpoint status using `etcdctl`. Replace the IP addresses below with those of your actual nodes.

```bash
kubectl -n kube-system exec -it etcd-controller -- /bin/sh
```

Inside the etcd pod:

```bash
ETCDCTL_API=3 etcdctl -w table \
  --endpoints 192.168.2.12:2379,192.168.2.10:2379,192.168.2.11:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key \
  endpoint status
```

```
+------------------+------------------+---------+---------+-----------+-----------+
|     ENDPOINT     |        ID        | VERSION | DB SIZE | IS LEADER | RAFT TERM |
+------------------+------------------+---------+---------+-----------+-----------+
| 192.168.2.12:2379| 2331065cd4fb02ff | 3.5.7   |  24 MB  |   true    |    11     |
| 192.168.2.10:2379| d2620a7d27a9b449 | 3.5.7   |  24 MB  |   false   |    11     |
| 192.168.2.11:2379| ef44cc541c5f37c7 | 3.5.7   |  24 MB  |   false   |    11     |
+------------------+------------------+---------+---------+-----------+-----------+
```

Note which node shows `IS LEADER: true` — you will shut that one down next.

```bash
exit
```

---

### Test Failover

**1.** Stop `containerd` on the **etcd leader** node to simulate a node failure. If using cri-o, rebooting the node is easier.

```bash
sudo systemctl stop containerd.service
# Or if using cri-o:
# sudo reboot
```

**2.** In the terminal running `kubectl -n kube-system logs -f etcd-thirdcp`, observe the leader election messages.

```
2025-10-09 02:11:39.569827 I | raft: 2331065cd4fb02ff [term: 9] received a MsgVote message with higher term
2025-10-09 02:11:39.570130 I | raft: 2331065cd4fb02ff became follower at term 10
2025-10-09 02:11:39.572242 I | raft: raft.node: 2331065cd4fb02ff elected leader ef44cc541c5f37c7 at term 10
2025-10-09 02:11:39.682319 W | rafthttp: lost the TCP streaming connection with peer d2620a7d27a9b449
2025-10-09 02:11:39.706328 I | rafthttp: peer d2620a7d27a9b449 became inactive
....
```

**3.** Check the HAProxy stats page — the failed CP should show as down. The remaining two should continue handling traffic.

**4.** From one of the running CP nodes, check etcd status again. The failed endpoint returns an error; a new leader has been elected.

```bash
kubectl -n kube-system exec -it etcd-secondcp -- /bin/sh
```

```bash
ETCDCTL_API=3 etcdctl -w table \
  --endpoints 192.168.2.12:2379,192.168.2.10:2379,192.168.2.11:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key \
  endpoint status
```

```
Failed to get the status of endpoint 192.168.2.12:2379 (context deadline exceeded)
+------------------+------------------+---------+---------+-----------+-----------+
|     ENDPOINT     |        ID        | VERSION | DB SIZE | IS LEADER | RAFT TERM |
+------------------+------------------+---------+---------+-----------+-----------+
| 192.168.2.10:2379| d2620a7d27a9b449 | 3.5.7   |  24 MB  |   true    |    12     |
| 192.168.2.11:2379| ef44cc541c5f37c7 | 3.5.7   |  24 MB  |   false   |    12     |
+------------------+------------------+---------+---------+-----------+-----------+
```

**5.** Bring the failed node back. Observe it rejoin the etcd cluster in the logs.

```bash
sudo systemctl start containerd.service
```

```
2025-10-09 02:45:11.337669 I | rafthttp: peer d2620a7d27a9b449 became active
2025-10-09 02:45:11.337710 I | rafthttp: established a TCP streaming connection with peer d2620a7d27a9b449
....
```

**6.** Run `etcdctl endpoint status` once more and confirm all three nodes are back in the table with the correct leader for the new term.

---
