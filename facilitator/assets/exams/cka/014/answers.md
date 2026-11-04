# CKA Practice Lab 014 — Final Exam Rehearsal — Answers

This lab is a dress rehearsal for the real exam: sixteen tasks in two hours, with uneven
weights like the real thing, and a pass mark of 66%. The topics are the ones the current
CKA keeps asking about, set in scenarios of its own.

It runs on a **kubeadm-bootstrapped cluster** with three worker nodes, plus a second,
single-node **auxiliary cluster**. From the jumphost you can `ssh controlplane`,
`ssh node01`, `ssh node02`, `ssh node03` and `ssh aux`, and you land as **root**. On the
real exam you `ssh` to a different host for every question and then `sudo -i`; read the
first line of each task for where to work.

Three questions — 3, 9 and 16 — start from something that is already broken. Each of
those answers opens with the commands that find the fault, then the fix.

**Exam-day habits worth practising here:**

- Read the whole question before you start, and check which host or cluster it is on.
- Do the fast tasks first. Flag anything that is taking more than about 8 minutes and
  come back to it.
- Use `kubectl explain`, `--dry-run=client -o yaml` and the docs search instead of
  writing YAML from memory.
- Check the result yourself: `kubectl get`, `describe`, `rollout status`, a quick `curl`.

---

## Question 1 — Helm chart whose CRD already exists

Look at the archives and the values the chart takes:

```bash
ls /tmp/exam/q1/charts/
helm show values /tmp/exam/q1/charts/berthwatch-0.7.2.tgz
# replicaCount: 1
# crds:
#   install: true
```

`crds.install` defaults to `true`, and the CRD it would install already exists, owned by
somebody else. Leave the flag on and `helm install` fails:

```
Error: INSTALLATION FAILED: ... CustomResourceDefinition "berths.ops.harbor.io" ... exists and
cannot be imported into the current release: invalid ownership metadata
```

Render first, then install with the same values:

```bash
helm template berthwatch /tmp/exam/q1/charts/berthwatch-0.7.2.tgz \
  --set replicaCount=2 --set crds.install=false > /tmp/exam/q1/berthwatch.yaml

grep -c CustomResourceDefinition /tmp/exam/q1/berthwatch.yaml   # 0

helm install berthwatch /tmp/exam/q1/charts/berthwatch-0.7.2.tgz \
  -n helm-berth --create-namespace \
  --set replicaCount=2 --set crds.install=false

helm list -n helm-berth
kubectl get deploy berthwatch -n helm-berth
```

If an earlier attempt failed, `helm uninstall berthwatch -n helm-berth` before trying
again. A chart pulled from a repository works the same way: `helm repo add`,
`helm search repo <chart> --versions`, then `--version 0.7.2`.

> A chart that ships its CRDs in a `crds/` directory, rather than as templates behind a
> value, is handled with `--skip-crds` on `helm install`. `helm template` leaves `crds/`
> out unless you pass `--include-crds`.

---

## Question 2 — Migrate the Ingress to the Gateway API

Read what the Ingress does today:

```bash
kubectl get ingress quay-web -n quay-edge -o yaml
# tls: secretName quay-tls, host quay.harbor.local
# /healthz/berths  Exact   -> quay-status:8080
# /                Prefix  -> quay-web:80
```

Write the Gateway and both routes. The Ingress `Prefix` type becomes `PathPrefix`; `Exact`
stays `Exact`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: quay-gw
  namespace: quay-edge
spec:
  gatewayClassName: harbor-gwc
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: quay.harbor.local
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: quay-tls
  - name: http
    protocol: HTTP
    port: 80
    hostname: quay.harbor.local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: quay-web
  namespace: quay-edge
spec:
  parentRefs:
  - name: quay-gw
    sectionName: https          # attaches to that listener only
  hostnames:
  - quay.harbor.local
  rules:
  - matches:
    - path:
        type: Exact
        value: /healthz/berths
    backendRefs:
    - name: quay-status
      port: 8080
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: quay-web
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: quay-redirect
  namespace: quay-edge
spec:
  parentRefs:
  - name: quay-gw
    sectionName: http
  hostnames:
  - quay.harbor.local
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
```

```bash
kubectl apply -f q2.yaml
kubectl delete ingress quay-web -n quay-edge
```

A redirect rule has no `backendRefs`. There is no Gateway controller in this lab, so the
Gateway never reports `Programmed`; on the exam there usually is one, and
`kubectl get gateway` showing `PROGRAMMED True` is your check.

---

## Question 3 — The auxiliary API server cannot reach etcd

```bash
ssh aux
kubectl get nodes
# The connection to the server ... was refused
crictl ps -a | grep -E 'kube-apiserver|etcd'
# etcd is Running; kube-apiserver keeps exiting
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -5
# ... transport: authentication handshake failed / connection error ... :2380
```

Compare where etcd listens for **clients** with where the API server looks for it:

```bash
grep -E 'listen-client-urls|advertise-client-urls|listen-peer-urls' /etc/kubernetes/manifests/etcd.yaml
#   - --advertise-client-urls=https://172.x.x.x:2379
#   - --listen-client-urls=https://172.x.x.x:2379
#   - --listen-peer-urls=https://172.x.x.x:2380
grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
#   - --etcd-servers=https://172.x.x.x:2380
```

The address was updated to follow etcd, but with the **peer** port (`2380`, which etcd
members use to talk to each other) instead of the **client** port (`2379`). Reverting
etcd to `127.0.0.1` would also make it work, but the question says the etcd change stays.

```bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
#   - --etcd-servers=https://172.x.x.x:2379
```

The kubelet recreates the Pod within ~20s. Give it a minute, then:

```bash
kubectl get pods -n kube-system
kubectl get --raw /readyz?verbose | grep etcd
```

The controller manager and scheduler crash-loop while the API server is down and come
back on their own. If one stays in `CrashLoopBackOff`, `crictl logs` it as well.

---

## Question 4 — HPA with scale-down behaviour

`kubectl autoscale` creates the target, bounds and metric, but no `behavior`, so write
the whole object:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: crane-telemetry
  namespace: hpa-crane
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: crane-telemetry
  minReplicas: 2
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 45
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
```

`kubectl explain hpa.spec.behavior.scaleDown` lists the fields if you forget them. With
`metrics-server` running, `kubectl get hpa -n hpa-crane` shows the live utilization after
a minute or so.

---

## Question 5 — Reuse a Released PersistentVolume

```bash
kubectl get pv ledger-pv
# STATUS: Released   CLAIM: ledger/ledger-data   STORAGECLASS: ledger-manual
kubectl get pv ledger-pv -o jsonpath='{.spec.claimRef}'
# {... "name":"ledger-data", "uid":"<uid of the deleted claim>" ...}
```

A `Released` volume still points at the deleted claim's **uid**, so a new claim with the
same name does not bind to it. Clear the stale reference:

```bash
kubectl patch pv ledger-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
kubectl get pv ledger-pv        # Available
```

The claim has to name the PV's StorageClass. Leave `storageClassName` out and admission
fills in the cluster's default (`standard`), and the claim gets a new, empty volume
instead:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ledger-data
  namespace: ledger
spec:
  storageClassName: ledger-manual
  volumeName: ledger-pv           # optional, but pins it to this PV
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f pvc.yaml
kubectl get pvc -n ledger         # Bound   ledger-pv
kubectl apply -f /tmp/exam/q5/ledger-db.yaml
kubectl logs -n ledger deploy/ledger-db   # prints the ledger record
```

---

## Question 6 — Choose the least permissive NetworkPolicy

Read all four files before applying anything:

| file | from | ports | verdict |
|---|---|---|---|
| `api-ingress-1` | every Pod in `harbor-ui` | 8080 | works, but admits `berth-ui` too |
| `api-ingress-2` | `app=crane-ui` Pods **in** `harbor-ui` (one entry, both selectors) | 8080 | **the answer** |
| `api-ingress-3` | `app=crane-ui` Pods in **any** namespace | all | works, far too wide |
| `api-ingress-4` | `app=crane-ui` Pods in `harbor-ui` | 80 | does not work: the server listens on 8080 |

```bash
kubectl apply -f /tmp/exam/q6/api-ingress-2.yaml
```

Check it:

```bash
IP=$(kubectl get pod harbor-api -n harbor-api -o jsonpath='{.status.podIP}')
kubectl exec -n harbor-ui crane-ui -- wget -qO- -T 3 http://$IP:8080   # harbor-api
kubectl exec -n harbor-ui berth-ui -- wget -qO- -T 3 http://$IP:8080   # times out
```

`namespaceSelector` and `podSelector` in **one** `from` entry are ANDed; in two separate
entries (two `-` dashes) they are ORed. That one-character difference is exactly what the
exam likes to test.

---

## Question 7 — Prepare node01

```bash
ssh node01
dpkg -i /root/harbor-cri-shim_1.4.2_all.deb
systemctl enable --now harbor-cri-shim
systemctl status harbor-cri-shim --no-pager

cat > /etc/sysctl.d/99-harbor.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-harbor.conf     # or: sysctl --system
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
```

`enable --now` does both halves: `enable` makes it start at boot, `--now` starts it now.
On the real exam the same shape usually comes with `cri-dockerd` and the bridge
parameters (`net.bridge.bridge-nf-call-iptables`), which need the `br_netfilter` module
loaded. A kind node has no bridge parameters to set, so this lab uses the two forwarding
keys.

---

## Question 8 — Native sidecar ahead of an init container

A native sidecar is an **init container** with `restartPolicy: Always`. Init containers
start strictly in list order, and the kubelet moves on from a sidecar as soon as it has
*started* rather than waiting for it to finish. So a sidecar listed **before**
`schema-migrate` is already tailing when the migration runs. Listed after it, as most
examples do, it starts only once the migration has finished. With `tail -n 0` it then
never prints those lines.

```bash
kubectl edit deploy manifest-api -n manifest-ops
```

```yaml
    spec:
      volumes:
      - name: manifest-logs
        emptyDir: {}
      initContainers:
      - name: manifest-shipper              # first
        image: busybox:1.36
        restartPolicy: Always
        command: ["sh", "-c", "tail -n 0 -F /var/log/manifest/migrate.log /var/log/manifest/app.log"]
        volumeMounts:
        - name: manifest-logs
          mountPath: /var/log/manifest
      - name: schema-migrate
        # ... image and command unchanged ...
        volumeMounts:
        - name: manifest-logs
          mountPath: /var/log/manifest
      containers:
      - name: api
        # ... image and command unchanged ...
        volumeMounts:
        - name: manifest-logs
          mountPath: /var/log/manifest
```

```bash
kubectl rollout status deploy/manifest-api -n manifest-ops
kubectl logs -n manifest-ops deploy/manifest-api -c manifest-shipper
# ==> /var/log/manifest/migrate.log <==
# 10:41:02 migrate step 1 ...
# ==> /var/log/manifest/app.log <==
# 10:41:06 api heartbeat
```

---

## Question 9 — node03 is NotReady

```bash
kubectl describe node node03 | grep -A3 Conditions   # Kubelet stopped posting node status
ssh node03
systemctl status kubelet --no-pager
#   Loaded: loaded (...; disabled; ...)
#   Active: inactive (dead)
systemctl start kubelet
journalctl -u kubelet -n 20 --no-pager
#   kubelet.service: Failed at step EXEC spawning /usr/local/bin/kubelet: No such file or directory
```

Two faults: the unit is **disabled**, and its kubeadm drop-in starts a binary that does
not exist.

```bash
which kubelet                                  # /usr/bin/kubelet
systemctl cat kubelet | grep -n ExecStart      # shows which file sets it
vi /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
#   ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS ...
systemctl daemon-reload
systemctl enable --now kubelet
systemctl is-enabled kubelet; systemctl is-active kubelet
```

Back on the jumphost, `kubectl get node node03` reports `Ready` within ~30s. On the exam,
"must survive a reboot" always means `systemctl enable`.

---

## Question 10 — PriorityClass one below the highest

```bash
kubectl get priorityclass
# harbor-batch       1500
# harbor-critical    600000
# harbor-ops         750000     <- the highest user-defined one, not "critical"
# system-cluster-critical / system-node-critical are built in: ignore them
kubectl create priorityclass berth-urgent --value=749999 --description="pilot dispatch"
kubectl patch deploy pilot-dispatch -n pilot-ops \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"berth-urgent"}}}}'
kubectl rollout status deploy/pilot-dispatch -n pilot-ops
kubectl get pods -n pilot-ops -o custom-columns=NAME:.metadata.name,PRIO:.spec.priority
```

`kubectl get pc --sort-by=.value` puts the answer on the last line.

---

## Question 11 — Install a CNI on the auxiliary cluster

```bash
ssh aux
kubectl get nodes                       # NotReady
kubectl describe node | grep -i network # NetworkPluginNotReady ... cni plugin not initialized
ls /root/cni/                           # calico.yaml  kube-flannel.yml
```

Flannel does not enforce NetworkPolicy, so the answer is Calico. Find the Pod CIDR the
cluster was built with:

```bash
kubectl get cm kubeadm-config -n kube-system -o yaml | grep podSubnet
#   podSubnet: 192.169.0.0/16
# or: ps aux | grep -o 'cluster-cidr=[^ ]*'   (kube-controller-manager)
```

`calico.yaml` ships `CALICO_IPV4POOL_CIDR` **commented out** with Calico's own default,
`192.168.0.0/16`. Uncomment it and set the cluster's range:

```bash
vi /root/cni/calico.yaml
#             - name: CALICO_IPV4POOL_CIDR
#               value: "192.169.0.0/16"
kubectl apply -f /root/cni/calico.yaml
kubectl rollout status ds/calico-node -n kube-system
kubectl get nodes                        # Ready
kubectl get ippools -o custom-columns=NAME:.metadata.name,CIDR:.spec.cidr
kubectl run t --image=busybox:1.36 --restart=Never -- sleep 60; kubectl get pod t -o wide
```

On the exam the CNI question often uses the **Tigera operator** instead:
`kubectl create -f tigera-operator.yaml`, then edit `custom-resources.yaml` so that
`spec.calicoNetwork.ipPools[0].cidr` matches the Pod CIDR before you create it. The idea
is the same: the pool has to match what kubeadm was told.

---

## Question 12 — Named port and NodePort Service

```bash
kubectl edit deploy tally-board -n tally
#      containers:
#      - name: board
#        image: nginx:1.27.4
#        ports:
#        - name: http
#          containerPort: 80
#          protocol: TCP

kubectl create service nodeport tally-board-np -n tally --tcp=80:80 --node-port=30814 \
  --dry-run=client -o yaml > svc.yaml
# then edit: targetPort: http, and selector: app: tally-board
kubectl apply -f svc.yaml
```

Or `kubectl expose deploy tally-board -n tally --name=tally-board-np --type=NodePort
--port=80 --target-port=http`, followed by `kubectl edit` to set `nodePort: 30814`.

```bash
kubectl get endpointslices -n tally
ssh node01 'curl -s http://$(hostname -i):30814 | head -4'
```

---

## Question 13 — Split node02 between three Pods

```bash
kubectl describe node node02 | grep -A6 Allocatable
#   cpu:     16
#   memory:  32000000Ki
kubectl describe node node02 | grep -A10 'Allocated resources'
```

Divide by three and keep headroom for the DaemonSet Pods: about 28–30% each. For 16 CPU
and ~30.5Gi that is roughly `4500m` and `8800Mi`. The init container gets the **same**
requests. A Pod's effective request is the larger of its biggest init container and the
sum of its regular containers, so equal values do not double-count.

```bash
kubectl edit deploy crane-sim -n crane-sim
#      initContainers:
#      - name: load-terrain
#        resources:
#          requests: {cpu: 4500m, memory: 8800Mi}
#      containers:
#      - name: simulator
#        resources:
#          requests: {cpu: 4500m, memory: 8800Mi}
kubectl scale deploy crane-sim -n crane-sim --replicas=3
kubectl get pods -n crane-sim -o wide
```

If a Pod stays `Pending` with `Insufficient cpu`, you went too high; lower the requests
and the Deployment rolls out new Pods.

---

## Question 14 — CRDs and kubectl explain

```bash
kubectl get crd | grep tides.harbor.io > /tmp/exam/q14/tide-crds.txt
kubectl explain tideforecasts.spec.retention > /tmp/exam/q14/retention-doc.txt
cat /tmp/exam/q14/*.txt
```

`kubectl explain` works on custom resources as soon as the CRD has a structural schema.
Use the plural (or kind) plus the field path.

---

## Question 15 — Only one default StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: harbor-fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
allowVolumeExpansion: true
```

```bash
kubectl apply -f sc.yaml
kubectl annotate sc standard storageclass.kubernetes.io/is-default-class=false --overwrite
kubectl get sc       # only harbor-fast shows (default)
```

Two defaults is not an error. Kubernetes picks the newest one, which is exactly why the
exam asks you to clear the old annotation.

---

## Question 16 — Pod Security admission blocks the ReplicaSet

```bash
kubectl get deploy,rs,pods -n customs
# deployment 0/3, a ReplicaSet with DESIRED 3 CURRENT 0, no Pods
kubectl describe rs -n customs | grep -A5 Events
# Error creating: pods "customs-gate-..." is forbidden: violates PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile ...
kubectl get ns customs --show-labels   # pod-security.kubernetes.io/enforce=restricted
```

When a Deployment has no Pods at all, the reason is on the **ReplicaSet**, not the
Deployment. Fix the Pod template, not the namespace:

```bash
kubectl edit deploy customs-gate -n customs
```

```yaml
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: gate
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

```bash
kubectl rollout status deploy/customs-gate -n customs
```

The busybox `httpd` listens on 8080, which an unprivileged user may bind, so nothing else
needs to change.
