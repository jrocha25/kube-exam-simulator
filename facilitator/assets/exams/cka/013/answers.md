# CKA Practice Lab 013 — Control Plane Repair & Cluster Operations — Answers

This lab is pitched at killer.sh difficulty: seventeen multi-part questions, more work
than fits comfortably in two hours, and several traps that only show up once the first
half of a fix is in.

It runs on a **kubeadm-bootstrapped cluster** (`clusterType: kind`) with three worker
nodes, plus a second, single-node **auxiliary cluster**. From the jumphost you can
`ssh controlplane`, `ssh node01`, `ssh node02`, `ssh node03` and `ssh aux`, and you land
as **root**. On the real exam you will `ssh` to a node and then `sudo -i`.

Five questions — 1, 8, 15, 16 and 17 — start from something that is already broken.
Each of those answers opens with the commands that find the fault before it shows the
fix.

Every question owns its own namespace, and the namespaces already exist.

---

## Question 1 — The auxiliary control plane is down

Everything happens on the auxiliary cluster's only node:

```bash
ssh aux
kubectl get nodes
# The connection to the server 10.97.... was refused
```

`kubectl` cannot help while the API server is down, so drop to the container runtime.
The control plane runs as static Pods, so look at their containers and logs:

```bash
crictl ps -a | grep -E 'kube-apiserver|kube-controller|etcd'
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -5
# ... dial tcp 127.0.0.1:2397: connect: connection refused
```

etcd listens on `2379`. Compare with the manifest:

```bash
grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
#     - --etcd-servers=https://127.0.0.1:2397
grep listen-client /etc/kubernetes/manifests/etcd.yaml
#     - --listen-client-urls=https://127.0.0.1:2379,...
sed -i 's#--etcd-servers=https://127.0.0.1:2397#--etcd-servers=https://127.0.0.1:2379#' \
    /etc/kubernetes/manifests/kube-apiserver.yaml
```

The kubelet notices the changed manifest within ~20s and recreates the Pod. Once
`kubectl get nodes` answers, the first half is done — but `relay-hub` still has no Pods:

```bash
kubectl get deploy,rs,pods -n cp-relay
# deployment.apps/relay-hub   0/2   0   0
# (no ReplicaSet at all)
```

A Deployment that never got a ReplicaSet means the **controller manager** is not doing
its job:

```bash
kubectl get pods -n kube-system
# kube-controller-manager-...   0/1   CrashLoopBackOff
kubectl logs -n kube-system kube-controller-manager-<node>
# ... invalid configuration: no configuration has been provided
```

It has a kubeconfig — but the file it was given is empty. Follow the path from the flag
to the volume:

```bash
grep -n 'kubeconfig' /etc/kubernetes/manifests/kube-controller-manager.yaml
#   - --kubeconfig=/etc/kubernetes/controller-manager.conf      (container path)
#   mountPath: /etc/kubernetes/controller-manager.conf
#   path: /etc/kubernetes/controller-manager.config             (host path — wrong)
ls -l /etc/kubernetes/controller-manager.con*
# controller-manager.conf     5.6K
# controller-manager.config      0   <- created empty by the kubelet
```

The volume is `type: FileOrCreate`, so the kubelet happily created an empty file at the
wrong path and mounted it. Point the hostPath back at the real file:

```bash
sed -i 's#path: /etc/kubernetes/controller-manager.config$#path: /etc/kubernetes/controller-manager.conf#' \
    /etc/kubernetes/manifests/kube-controller-manager.yaml
rm /etc/kubernetes/controller-manager.config
```

```bash
kubectl get pods -n kube-system
kubectl rollout status deployment/relay-hub -n cp-relay
```

**Take-aways:** `crictl ps -a` and `crictl logs` are how you read a control plane that
`kubectl` cannot reach. And `FileOrCreate` / `DirectoryOrCreate` volumes never fail on a
wrong path — the evidence is always in the container's own log.

---

## Question 2 — etcd backup, proven by a restore

Order matters: the backup must contain the marker, so create it first.

```bash
kubectl create configmap cutover-marker -n etcd-cutover --from-literal=wave=harbour-7
```

Read the endpoint and certificates out of the etcd manifest — never guess them:

```bash
ssh controlplane
grep -E 'listen-client-urls|cert-file|key-file|trusted-ca-file' /etc/kubernetes/manifests/etcd.yaml
```

```bash
etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup/cutover.db

etcdutl snapshot status /opt/etcd-backup/cutover.db -w table
```

etcdctl 3.6 speaks only the v3 API, so the old `ETCDCTL_API=3` prefix is no longer
needed (it now prints an "unrecognized environment variable" warning).

A restore is an offline operation — it reads the file and writes a brand-new data
directory. It does not need, or touch, the running etcd:

```bash
etcdutl snapshot restore /opt/etcd-backup/cutover.db --data-dir /opt/etcd-backup/cutover-verify
ls /opt/etcd-backup/cutover-verify/member
# snap  wal
```

**Why it is graded the way it is:** a ConfigMap's `resourceVersion` *is* the etcd
revision that wrote it, so a snapshot whose revision is lower than the marker's
`resourceVersion` provably does not contain it. Do not edit `etcd.yaml` to point at the
restored directory — that would be a restore of the live cluster, which nobody asked for.

---

## Question 3 — Roll back, then upgrade without losing values

Find out what happened first:

```bash
helm history tidewatch -n helm-tide
# 1  superseded  Install complete
# 2  deployed    Upgrade complete
helm get values tidewatch -n helm-tide --revision 1
# berth: north
# replicaCount: 2
helm get values tidewatch -n helm-tide --revision 2
# berth: north
# image: {tag: 1.27.4-ck-x-broken}
# replicaCount: 2
kubectl get pods -n helm-tide
# ... ImagePullBackOff
```

Roll back to the last revision that worked:

```bash
helm rollback tidewatch 1 -n helm-tide --wait
```

Now the trap. `helm upgrade` **without** `--reuse-values` starts again from the chart's
defaults and applies only what you pass on this command line, so `replicaCount: 2` and
`berth: north` silently revert to `1` and `south`. Reuse the values of the current
revision — the rollback, which carries revision 1's values and not the broken tag:

```bash
helm upgrade tidewatch /tmp/exam/q3/tidewatch -n helm-tide \
  --reuse-values \
  -f /tmp/exam/q3/values-season.yaml \
  --set tier=priority \
  --wait

helm history tidewatch -n helm-tide
# 3  superseded  Rollback to 1
# 4  deployed    Upgrade complete
helm get values tidewatch -n helm-tide
# berth: north
# replicaCount: 2
# season: winter
# tier: priority
```

Running `--reuse-values` *before* the rollback would have carried the broken image tag
forward too — another reason to roll back first.

---

## Question 4 — A Pod without a scheduler

The scheduler is a static Pod, so you stop it by moving its manifest out of the
directory the kubelet watches:

```bash
ssh controlplane
mv /etc/kubernetes/manifests/kube-scheduler.yaml /root/
exit
kubectl get pods -n kube-system | grep scheduler     # gone after a few seconds
```

Without a scheduler, a Pod is only placed if you set `spec.nodeName` yourself. That
bypasses the scheduler entirely — including taint checks. The control-plane node's
`NoSchedule` taint is enforced *by the scheduler*, not by the kubelet, which is why this
Pod needs no toleration:

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: berth-manual
  namespace: sched-berth
spec:
  nodeName: cluster-control-plane     # the real name of "controlplane"
  containers:
  - name: berth
    image: nginx:1.27.4
YAML
kubectl get pod berth-manual -n sched-berth -o wide
```

Find the real node name with `kubectl get nodes -l ck-x.io/alias=controlplane`.

Start the scheduler again and prove it works:

```bash
ssh controlplane mv /root/kube-scheduler.yaml /etc/kubernetes/manifests/
kubectl get pods -n kube-system | grep scheduler     # Running again

kubectl run berth-auto -n sched-berth --image=nginx:1.27.4 \
  --overrides='{"spec":{"nodeSelector":{"ck-x.io/alias":"node01"}},"apiVersion":"v1"}'
kubectl get pod berth-auto -n sched-berth -o wide
```

`kubectl run` names the container after the Pod; the question asks for `berth`, so write
the manifest instead if you want to be exact.

---

## Question 5 — Kubelet configuration, the kubeadm way

kubeadm keeps the cluster-wide kubelet configuration in a ConfigMap, and every
`kubeadm join` downloads it. Editing `/var/lib/kubelet/config.yaml` on one node changes
that node only and is overwritten by the next `kubeadm upgrade`.

```bash
kubectl edit configmap kubelet-config -n kube-system
```

Add two lines to the `kubelet:` document (anywhere at the top level of it):

```yaml
    containerLogMaxSize: 25Mi
    containerLogMaxFiles: 4
```

Then have kubeadm rewrite the node's file from the ConfigMap, and restart the kubelet —
it reads its configuration only at start:

```bash
ssh controlplane
kubeadm upgrade node phase kubelet-config
grep containerLogMax /var/lib/kubelet/config.yaml
systemctl restart kubelet
exit

kubectl get --raw /api/v1/nodes/cluster-control-plane/proxy/configz | jq '.kubeletconfig | {containerLogMaxSize, containerLogMaxFiles}'
```

`/configz` is the kubelet's *running* configuration, which is the only proof the change
took effect.

---

## Question 6 — Namespace guardrails

```bash
kubectl label namespace wl-harbor \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=v1.34

kubectl create quota harbor-quota -n wl-harbor \
  --hard=requests.cpu=1,requests.memory=1Gi,limits.cpu=2,limits.memory=2Gi,pods=6
```

There is no imperative command for a LimitRange:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: harbor-defaults
  namespace: wl-harbor
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 50m
      memory: 64Mi
    default:
      cpu: 200m
      memory: 128Mi
```

Nothing has happened to `manifest-api` yet: admission only runs when a Pod is created.
Restart it and watch the ReplicaSet refuse:

```bash
kubectl rollout restart deployment manifest-api -n wl-harbor
kubectl describe rs -n wl-harbor | grep -A3 Events
# violates PodSecurity "restricted:v1.34": allowPrivilegeEscalation != false,
# unrestricted capabilities, runAsNonRoot != true, seccompProfile ...
```

The message lists exactly what `restricted` needs. busybox runs as root by default, so
also give it a non-root UID:

```bash
kubectl patch deployment manifest-api -n wl-harbor -p '{"spec":{"template":{"spec":{
  "securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"api","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}}}'
kubectl rollout status deployment manifest-api -n wl-harbor
kubectl get pod -n wl-harbor -o jsonpath='{.items[0].spec.containers[0].resources}'
# {"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
```

The ResourceQuota is what *forces* the LimitRange to matter: once a quota tracks
`requests.cpu`, a Pod that declares no request is rejected outright — unless a
LimitRange fills it in at admission.

---

## Question 7 — An HPA with behavior, through the overlay

Create `overlays/prod/hpa.yaml`, naming the Deployment by its **base** name. The overlay's
`namePrefix` renames both the HPA and its `scaleTargetRef`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: tide-reader
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tide-reader
  minReplicas: 2
  maxReplicas: 8
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      selectPolicy: Min          # the policy allowing the SMALLER change wins
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
      - type: Percent
        value: 20
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 50
        periodSeconds: 30
```

Add it to `overlays/prod/kustomization.yaml` under `resources:` and apply:

```bash
kubectl kustomize /tmp/exam/q7/tidereader/overlays/prod | grep -A4 HorizontalPodAutoscaler
kubectl apply -k /tmp/exam/q7/tidereader/overlays/prod
kubectl get hpa -n wl-tide-prod
```

`selectPolicy` defaults to `Max` — the policy allowing the *largest* change. "Smaller
change wins" is `Min`, and it is the one field most people get wrong.

---

## Question 8 — node03 is NotReady

```bash
kubectl get nodes
kubectl describe node <node03> | grep -A6 Conditions
# Kubelet stopped posting node status.
ssh node03
systemctl status kubelet
journalctl -u kubelet --no-pager | tail -20
# "command failed" err="failed to run Kubelet: validate service connection:
#  validate CRI v1 runtime API for endpoint \"unix:///var/run/cri-dockerd.sock\" ..."
```

This node runs containerd, not cri-dockerd. Find where the flag comes from — the
kubelet's flags are assembled from its systemd drop-in and the files it loads:

```bash
systemctl cat kubelet | grep -E 'EnvironmentFile|ExecStart'
grep -r cri-dockerd /etc/default/kubelet /var/lib/kubelet/kubeadm-flags.env
# /etc/default/kubelet:KUBELET_EXTRA_ARGS=... --container-runtime-endpoint=unix:///var/run/cri-dockerd.sock
sed -i 's# --container-runtime-endpoint=unix:///var/run/cri-dockerd.sock##' /etc/default/kubelet
systemctl restart kubelet
```

The kubelet now stays up — and the node is **still** NotReady. Look again:

```bash
journalctl -u kubelet --no-pager | tail -5
# ... dial tcp 172.x.x.x:6643: connect: connection refused
grep server /etc/kubernetes/kubelet.conf
#     server: https://172.x.x.x:6643
```

The API server listens on 6443 (`grep server /etc/kubernetes/admin.conf` on controlplane,
or `kubectl cluster-info`). Fix the port — and only the port: the file's credentials are
the node's own rotating client certificate, and swapping in another kubeconfig would
give the node a different identity.

```bash
sed -i 's#:6643$#:6443#' /etc/kubernetes/kubelet.conf
systemctl restart kubelet
exit
kubectl get nodes -w
kubectl get pods -n node-buoy -o wide
```

---

## Question 9 — One budget, then drain

```bash
kubectl get pdb -n wl-quorum
# quorum-legacy   2   N/A   ...
```

Create the budget. `unhealthyPodEvictionPolicy: AlwaysAllow` is what lets Pods that are
running but not ready be evicted regardless of the budget:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: quorum-budget
  namespace: wl-quorum
spec:
  maxUnavailable: 1
  unhealthyPodEvictionPolicy: AlwaysAllow
  selector:
    matchLabels:
      app: quorum
      ring: primary
```

Try the drain and see why "only budget" was in the question:

```bash
kubectl drain <node02> --ignore-daemonsets --delete-emptydir-data
# error when evicting pods/"quorum-..." (will retry after 5s):
# This pod has more than one PodDisruptionBudget, which the eviction subresource does not support.
```

The eviction API refuses outright when two budgets cover one Pod. Remove the legacy one
and drain again:

```bash
kubectl delete pdb quorum-legacy -n wl-quorum
kubectl drain <node02> --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n wl-quorum -o wide
```

`--ignore-daemonsets` is needed for `calico-node` and `kube-proxy`, and
`--delete-emptydir-data` because the quorum Pods use an `emptyDir`. Leave the node
cordoned — do not uncordon it.

---

## Question 10 — Egress on a named port, ingress from one namespace

Look at the ledger Pods first — they do not agree on a port number:

```bash
kubectl get pods -n net-tally-data -o custom-columns=NAME:.metadata.name,ROLE:.metadata.labels.role,PORTS:.spec.containers[0].ports
# ledger-...          ledger   [{pg-wire 5432} {pg-admin 5433}]
# ledger-replica-...  ledger   [{pg-wire 6432}]
# audit-...           audit    [{pg-wire 5432}]
```

A NetworkPolicy port may be a **name**; it is resolved per destination Pod, so one rule
covers both 5432 and 6432. A numeric `5432` would cut `ledger-replica` off.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tally-egress
  namespace: net-tally
spec:
  podSelector:
    matchLabels:
      app: tally-api
  policyTypes: ["Egress"]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
  - to:
    - namespaceSelector:          # one list item: namespace AND pod
        matchLabels:
          tier: data
      podSelector:
        matchLabels:
          role: ledger
    ports:
    - {protocol: TCP, port: pg-wire}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tally-ingress
  namespace: net-tally
spec:
  podSelector:
    matchLabels:
      app: tally-api
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: net-tally-front
      podSelector:
        matchLabels:
          role: teller
    ports:
    - {protocol: TCP, port: 80}
```

Two separate `- namespaceSelector` / `- podSelector` items would mean *OR* — every Pod in
`tier=data` namespaces, plus every `role=ledger` Pod anywhere, including the decoy in
`net-tally-sandbox`.

---

## Question 11 — A Service whose endpoints you write yourself

A Service with no selector gets no EndpointSlices from the control plane; you supply them.
The slice is tied to its Service by the `kubernetes.io/service-name` label, and its ports
are matched to the Service's ports **by name**.

```bash
kubectl get pods -n net-vault-backend -o wide      # note both Pod IPs
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: vault-proxy
  namespace: net-vault
spec:
  ports:
  - name: api
    port: 80
    targetPort: 8080
  - name: metrics
    port: 9100
    targetPort: 9100
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: vault-proxy-1
  namespace: net-vault
  labels:
    kubernetes.io/service-name: vault-proxy
    endpointslice.kubernetes.io/managed-by: staff.ck-x.io
addressType: IPv4
ports:
- name: api            # must equal the Service port's name
  port: 8080           # the port on the backend
  protocol: TCP
- name: metrics
  port: 9100
  protocol: TCP
endpoints:
- addresses: ["<vault-a IP>"]
  conditions:
    ready: true
- addresses: ["<vault-b IP>"]
  conditions:
    ready: false
```

```bash
kubectl exec -n net-vault vault-client -- wget -qO- http://vault-proxy.net-vault.svc.cluster.local.
# vault-a     (every time — kube-proxy skips endpoints that are not ready)
```

---

## Question 12 — A second Service range

```yaml
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata:
  name: orbit-range
spec:
  cidrs: ["10.250.0.0/24"]
```

```bash
kubectl get servicecidr
kubectl create service clusterip orbit-gw -n net-orbit --tcp=80:80 --clusterip=10.250.0.40 \
  --dry-run=client -o yaml | sed 's/app: orbit-gw/app: orbit/' | kubectl apply -f -
```

`spec.clusterIP` is immutable, so moving `orbit-legacy` means delete and recreate. And a
plain recreate lands back in `10.96.0.0/16` — the allocator keeps using the default range
for as long as it has addresses — so pick an address in the new range explicitly:

```bash
kubectl get svc orbit-legacy -n net-orbit -o yaml > legacy.yaml
# edit legacy.yaml: set spec.clusterIP: 10.250.0.41, delete spec.clusterIPs,
# metadata.uid, metadata.resourceVersion and the last-applied annotation
kubectl delete svc orbit-legacy -n net-orbit
kubectl create -f legacy.yaml
kubectl exec -n net-orbit orbit-probe -- wget -qO- -T3 http://10.250.0.41:8080
```

---

## Question 13 — Grow a claim in place

```bash
kubectl patch pvc ledger-data -n stor-ledger -p '{"spec":{"resources":{"requests":{"storage":"1Gi"}}}}'
# Error ... only dynamically provisioned pvc can be resized and the storageclass
#           that provisions the pvc must support resize
```

`allowVolumeExpansion` is the one field of a StorageClass you may change after creating
it:

```bash
kubectl patch storageclass harbor-grow -p '{"allowVolumeExpansion":true}'
kubectl patch pvc ledger-data -n stor-ledger -p '{"spec":{"resources":{"requests":{"storage":"1Gi"}}}}'
kubectl describe pvc ledger-data -n stor-ledger | grep -A3 Events
# ExternalExpanding  waiting for an external controller to expand this PVC
```

A real CSI driver would now resize the volume and `status.capacity` would follow. The
local-path provisioner has no resizer, which is why the question grades the request.

---

## Question 14 — A local volume pinned by a label

A `local` volume is a real disk on one node, and the PV — not the Pod — says which node:
its `nodeAffinity` is required. The `WaitForFirstConsumer` binding mode is what lets the
scheduler place the Pod *and* bind the claim together.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vault-local
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vault-pv-01
spec:
  capacity:
    storage: 1Gi
  accessModes: ["ReadWriteOnce"]
  storageClassName: vault-local
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /srv/ck-x/tidevault
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: storage.ck-x.io/vault
          operator: In
          values: ["nvme"]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vault-claim
  namespace: stor-vault
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: vault-local
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: vault-reader
  namespace: stor-vault
spec:
  containers:
  - name: reader
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts:
    - name: vault
      mountPath: /vault
  volumes:
  - name: vault
    persistentVolumeClaim:
      claimName: vault-claim
```

```bash
kubectl get pod vault-reader -n stor-vault -o wide     # on node01, placed by the volume
kubectl exec -n stor-vault vault-reader -- cat /vault/token
```

---

## Question 15 — A rollout that will not land

```bash
kubectl rollout status deployment cargo-api -n ts-cargo
# Waiting for deployment "cargo-api" rollout to finish: 0 out of 2 new replicas have been updated...
kubectl get rs -n ts-cargo
# cargo-api-<new>   1   0   0
kubectl describe rs -n ts-cargo cargo-api-<new> | grep -A3 Events
# FailedCreate  ... exceeded quota: cargo-quota, requested: pods=1, used: pods=2, limited: pods=2
```

**Fault 1.** The rolling update surges a third Pod, and the quota allows two. The quota
is not yours to change and the replica count must stay, so change *how* the Deployment
rolls: never surge, replace one at a time.

```bash
kubectl patch deployment cargo-api -n ts-cargo -p \
  '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}}'
kubectl get pods -n ts-cargo
# cargo-api-<new>-...   0/1   CreateContainerConfigError
kubectl describe pod -n ts-cargo <that pod> | grep -A3 Events
# Error: couldn't find key API_TOKEN in Secret ts-cargo/relay-secrets
kubectl get secret relay-secrets -n ts-cargo -o jsonpath='{.data}'
# {"api-token":"..."}
```

**Fault 2.** The Secret's key is `api-token`. **Fault 3** appears once that is fixed: the
Pods start, never become ready, and restart:

```bash
kubectl describe pod -n ts-cargo <new pod> | grep -E 'Liveness|Readiness|Unhealthy'
# Readiness probe failed: Get "http://...:8080/": connect: connection refused
```

nginx serves on 80. Fix both in one edit (`kubectl edit deployment cargo-api -n ts-cargo`):
the `secretKeyRef.key` to `api-token`, and both probes' `port` to `80`.

```bash
kubectl rollout status deployment cargo-api -n ts-cargo
```

---

## Question 16 — A namespace stuck Terminating

```bash
kubectl get namespace ts-decom -o jsonpath='{.status.conditions}' | jq
# "Some content in the namespace has finalizers remaining: ops.ck-x.io/drain-hook in 2 resource instances"
kubectl get tidegauges -n ts-decom
# gauge-17, gauge-21 — both with a deletionTimestamp, both waiting on a finalizer
```

The finalizer belongs to a controller that no longer exists, so nothing will ever remove
it. Remove it yourself — from the resources **in this namespace only**:

```bash
for g in $(kubectl get tidegauges -n ts-decom -o name); do
  kubectl patch "$g" -n ts-decom --type=merge -p '{"metadata":{"finalizers":null}}'
done
kubectl get namespace ts-decom      # NotFound a few seconds later
```

**The tempting shortcut is wrong.** Clearing the *namespace's* finalizer through the
`/finalize` subresource makes the Namespace object disappear, but its resources stay in
etcd — `kubectl get tidegauges -n ts-decom` still lists them afterwards. They come back
to haunt the next team that creates a namespace with that name.

It is also a trap you cannot simply back out of: with the namespace gone, `kubectl patch`
on the orphans answers `namespaces "ts-decom" not found`. Recreate the namespace, remove
the finalizers, and delete it again:

```bash
kubectl create namespace ts-decom
for g in $(kubectl get tidegauges -n ts-decom -o name); do
  kubectl patch "$g" -n ts-decom --type=merge -p '{"metadata":{"finalizers":null}}'
done
kubectl delete namespace ts-decom
``` Deleting the CRD would
also free the namespace, by destroying every TideGauge in the cluster, including
`gauge-03` in `ts-decom-keep`.

---

## Question 17 — A secret in a shell-less container

```bash
kubectl exec -n ts-lighthouse beacon-core -- sh
# exec: "sh": executable file not found
```

An ephemeral container with `--target` joins the target container's process namespace,
so the target's process is visible in `/proc`:

```bash
kubectl debug -n ts-lighthouse beacon-core -it --image=busybox:1.36 --target=core -- sh
/ # cat /proc/1/environ
cat: can't open '/proc/1/environ': Permission denied
```

The target runs as uid 65535; reading another user's process environment needs
`CAP_SYS_PTRACE`, which the default debugging profile does not grant. The `general`
profile does:

```bash
kubectl debug -n ts-lighthouse beacon-core -it --image=busybox:1.36 --target=core \
  --profile=general -c recover -- sh
/ # tr '\0' '\n' < /proc/1/environ | grep LIGHT_TOKEN
LIGHT_TOKEN=lh-...
```

Write only the value:

```bash
echo 'lh-...' > /tmp/exam/q17/token.txt
```

An ephemeral container cannot be removed again, but adding one changes neither the Pod's
UID nor the `core` container, which is why it is the right tool here — `kubectl debug
--copy-to` would create a new Pod without the Secret and lose the value.
