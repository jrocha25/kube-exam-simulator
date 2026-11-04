# CKA Practice Lab 006 — Answers

Every solution below is written for the exam jumphost (`ckad9999`), where `kubectl` already points at the exam cluster.

This lab runs on a **kubeadm** cluster, not k3s, which is what makes questions 1, 2, 4, 5 and 6 possible at all. Three nodes are reachable over SSH with no password:

```bash
ssh controlplane     # the control plane: /etc/kubernetes/manifests, crictl, etcd
ssh node01           # first worker
ssh node02           # second worker
ssh node03           # third worker
```

Question 8 is set on a **second, separate cluster**, reached the same way:

```bash
ssh aux              # the auxiliary cluster's only node; kubectl there is already configured
```

You land as `root`, so no `sudo` is needed — but on the real exam you will `ssh node01` then `sudo -i`, so it is worth typing anyway.

The three workers are not interchangeable in this lab. `node01` carries question 2's kubelet fault, so until you fix it the node accepts only Pods that request no resources. `node02` is question 5's drain target and question 17's reserved node. `node03` is question 18's arena. Nothing stops you from using them differently, but the questions are written around that split.

Six of the eighteen questions (1, 2, 7, 8, 10 and 14) start from a cluster that is already broken. Each of those answers opens with the commands that find the fault before it shows the fix — on the real exam nobody tells you what is wrong, and the diagnosis is most of the work.

**Question 8 takes DNS down for an entire cluster, so it is set on its own.** An outage that broad is not something a lab can contain: while it was staged on this cluster, every other question had to be written around a cluster that could not resolve a name — including question 7, whose acceptance criterion is a lookup that could not have succeeded until question 8 was solved. On its own cluster the damage stops at question 8, and the rest of the lab behaves normally. Nothing you do over there affects anything here, and vice versa.

---

## Question 1: A static Pod that never starts

```bash
kubectl get pods -n ops-probe
kubectl describe pod -n ops-probe -l app=node-probe | grep -A10 Events
kubectl logs -n ops-probe -l app=node-probe
```

The Pod is `CrashLoopBackOff` and the log says everything:

```
cat: can't open '/etc/probe/probe.cfg': No such file or directory
```

The events show nothing wrong — the volume mounted, the container started. It is the container's own output that names the problem, and there are **two** faults behind it. Go to the node and read the manifest:

```bash
ssh node01
cat /etc/kubernetes/manifests/node-probe.yaml
ls -la /opt/probe-data /opt/probe-datta
```

`/opt/probe-data` holds `probe.conf`. `/opt/probe-datta` exists too and is **empty** — the kubelet created it, because the volume declares `type: DirectoryOrCreate` and that is exactly what `DirectoryOrCreate` does when the path is wrong. This is the trap: a mistyped `hostPath` does not fail, it silently mounts an empty directory, so the container sees a perfectly good mount with nothing in it.

The second fault is the file name: the command reads `probe.cfg`, the file on disk is `probe.conf`.

Fix both:

```bash
sed -i 's#/opt/probe-datta#/opt/probe-data#' /etc/kubernetes/manifests/node-probe.yaml
sed -i 's#/etc/probe/probe.cfg#/etc/probe/probe.conf#' /etc/kubernetes/manifests/node-probe.yaml
rmdir /opt/probe-datta
exit
```

The kubelet watches `/etc/kubernetes/manifests` and restarts the Pod on its own. Because it was already in `CrashLoopBackOff`, the backoff timer means recovery takes up to a minute — that is normal, not a third fault:

```bash
kubectl get pods -n ops-probe -w
```

Fixing only one of the two leaves it crashing, which is why reading the container's output after each change matters more than fixing everything at once.

---

## Question 2: Pods that stay Pending on a Ready node

```bash
kubectl get pods -n sched-batch
kubectl describe pod -n sched-batch -l app=batch-runner | grep -A10 Events
```

```
0/3 nodes are available: 1 Insufficient memory, 2 node(s) didn't match Pod's node affinity/selector.
```

Two nodes are ruled out by the pin, which is expected. The interesting one is `Insufficient memory` for a Pod asking for `3Gi`. Compare what the node has against what it offers:

```bash
kubectl describe node cluster-worker | grep -A8 "Capacity:"
```

`Capacity` shows the node's real memory; `Allocatable` is a tiny fraction of it. The gap between the two is what the kubelet has been told to reserve, so the answer is in the kubelet's own configuration:

```bash
ssh node01
grep -A3 systemReserved /var/lib/kubelet/config.yaml
```

```yaml
systemReserved:
  memory: "29963Mi"
  cpu: "100m"
```

`systemReserved` is subtracted from `Capacity` to produce `Allocatable`, and it is more than an accounting figure: the kubelet's default `enforceNodeAllocatable: ["pods"]` also caps the pods cgroup at `Allocatable`, so a reservation this aggressive starves everything already running on the node as well as blocking new work.

Almost the entire node held back for the system, leaving an Allocatable smaller than a single replica's request. Remove the reservation and restart the kubelet:

```bash
sed -i '/^systemReserved:/,+2d' /var/lib/kubelet/config.yaml
systemctl restart kubelet
exit
```

```bash
kubectl get node cluster-worker -o jsonpath='{.status.allocatable.memory}{"\n"}'
kubectl get pods -n sched-batch -w
```

The pending Pods schedule as soon as the node re-registers with its real `Allocatable`. Note what *not* to do: scaling the Deployment down, lowering its requests or removing the pin would all make the symptom go away without fixing anything, and the verification checks all three.

---

## Question 3: A user that authenticates with a certificate

Generate the key and the request. The common name becomes the username and the organization becomes a group, which is why the CSR's subject matters:

```bash
mkdir -p /tmp/exam/q3 && cd /tmp/exam/q3
openssl genrsa -out mira.key 2048
openssl req -new -key mira.key -out mira.csr -subj "/CN=mira/O=developers"
```

Submit it. `request` is the base64 of the PEM, and `-w 0` matters — a wrapped base64 string is rejected:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: mira-access
spec:
  request: $(base64 -w 0 mira.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF

kubectl certificate approve mira-access
kubectl get csr mira-access
```

`Approved,Issued` means the controller signed it. Pull the certificate out:

```bash
kubectl get csr mira-access -o jsonpath='{.status.certificate}' | base64 -d > /tmp/exam/q3/mira.crt
openssl x509 -in /tmp/exam/q3/mira.crt -noout -subject
```

A signed certificate grants nothing on its own — authentication and authorization are separate. Bind a Role to the user:

```bash
kubectl create role dev-reader -n dev-team \
  --verb=get,list,watch --resource=pods,pods/log
kubectl create rolebinding mira-reader -n dev-team \
  --role=dev-reader --user=mira
```

Check it, and note the subresource trap:

```bash
kubectl auth can-i list pods --as=mira -n dev-team                      # yes
kubectl auth can-i get pods --as=mira -n dev-team --subresource=log     # yes
kubectl auth can-i delete pods --as=mira -n dev-team                    # no
kubectl auth can-i list pods --as=mira -n default                       # no
```

`kubectl auth can-i get pods/log` is **not** the same question: the positional form reads `verb resource/resourceName`, so it asks about a Pod *named* `log` and answers `yes` whenever plain `get pods` is allowed. Subresources need `--subresource=log`.

To use the credential for real you would add it to a kubeconfig:

```bash
kubectl config set-credentials mira \
  --client-key=/tmp/exam/q3/mira.key --client-certificate=/tmp/exam/q3/mira.crt --embed-certs=true
kubectl config set-context mira --cluster=kind-cluster --user=mira --namespace=dev-team
kubectl --context=mira get pods
```

---

## Question 4: An etcd snapshot

etcd is a static Pod, and the flags in its manifest are where the certificate paths live:

```bash
ssh controlplane
grep -E 'listen-client-urls|cert-file|key-file|trusted-ca-file' \
  /etc/kubernetes/manifests/etcd.yaml
```

```
--cert-file=/etc/kubernetes/pki/etcd/server.crt
--key-file=/etc/kubernetes/pki/etcd/server.key
--trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
--listen-client-urls=https://127.0.0.1:2379,...
```

Take the snapshot. `ETCDCTL_API=3` is the default on etcd 3.4+ but costs nothing to state:

```bash
mkdir -p /opt/etcd-backup
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup/snapshot.db
```

Then the status report. On etcd 3.6 `snapshot status` moved to `etcdutl`; `etcdctl` still accepts it with a deprecation warning:

```bash
etcdutl snapshot status /opt/etcd-backup/snapshot.db --write-out=json \
  > /opt/etcd-backup/status.json
cat /opt/etcd-backup/status.json
```

```json
{"hash":2872155454,"revision":9241,"totalKey":1104,"totalSize":4763648}
```

Reading the snapshot back is the only thing that proves it is a backup rather than a file. `snapshot status` does not touch the live datastore, so it is safe to run against a running cluster.

Restoring — which this question deliberately does not ask for — would be `etcdutl snapshot restore --data-dir=/var/lib/etcd-restored`, followed by pointing the etcd manifest's `hostPath` at the new directory. You never restore over a running etcd's data directory.

---

## Question 5: Draining a node

Record what is there **before** you drain, because the Pod names disappear with the Pods:

```bash
mkdir -p /tmp/exam/q5
kubectl get pods -n node-maint -l app=shop-web \
  --field-selector spec.nodeName=cluster-worker2 \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' > /tmp/exam/q5/drained.txt
cat /tmp/exam/q5/drained.txt
```

Now drain. Both flags are needed and both are asked for in the question: a DaemonSet Pod cannot be rescheduled elsewhere so `drain` refuses to proceed without `--ignore-daemonsets`, and it will not silently discard `emptyDir` data without `--delete-emptydir-data`:

```bash
kubectl drain cluster-worker2 --ignore-daemonsets --delete-emptydir-data
```

`drain` cordons first, then evicts. Confirm:

```bash
kubectl get nodes
kubectl get pods -n node-maint -o wide
```

`cluster-worker2` shows `Ready,SchedulingDisabled`, the `shop-web` Pods have moved, and `log-shipper` is still there — a DaemonSet Pod is not evicted, it is ignored.

Put the node back:

```bash
kubectl uncordon cluster-worker2
kubectl rollout status deployment/shop-web -n node-maint
```

Uncordoning does not move anything back on its own; the replicas that were rescheduled stay where they are. That is fine — the requirement is that all four are `Running` and the node is schedulable again.

---

## Question 6: Hardening the API server

This is the one change in the lab that can take the cluster down, so make a copy you can restore from before touching anything:

```bash
ssh controlplane
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add both flags to the container's `command` list, alongside the other `--` entries:

```yaml
    - --tls-min-version=VersionTLS12
    - --tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
```

The 128-bit pair at the end is not padding. The API server serves HTTP/2, and the HTTP/2 specification makes one AES-128-GCM cipher mandatory, so a list of nothing but 256-bit suites is rejected outright:

```
error configuring http2: http2: TLSConfig.CipherSuites is missing an
HTTP/2-required AES_128_GCM_SHA256 cipher
```

That failure happens *after* the manifest parses, so the Pod is created and then exits — which is precisely the situation the next paragraph is about.

Save and leave the node. The kubelet notices the manifest changed and restarts the static Pod; the API server is unreachable for ten to thirty seconds while it does:

```bash
exit
kubectl get nodes
kubectl get pods -n kube-system -l component=kube-apiserver
kubectl get pods -n kube-system -l component=kube-apiserver \
  -o jsonpath='{.items[0].spec.containers[0].command}' | tr ',' '\n' | grep tls
```

**If `kubectl` stops answering and does not come back**, the manifest is bad and you cannot use `kubectl` to find out why. That is what `crictl` is for:

```bash
ssh controlplane
crictl ps -a | grep kube-apiserver
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1)
```

The two failure modes look different and are found in different places. A **YAML error** means no container was ever created, so `crictl ps -a` shows nothing and the parse error is in the kubelet's own journal (`journalctl -u kubelet | tail -20`). A **rejected flag** means the container was created and exited, so `crictl ps -a` lists it as `Exited` and `crictl logs` has the reason on its last line. Either way, restoring the copy gets you back:

```bash
cp /root/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
```

Note the cipher list is order-sensitive and is checked exactly — `--tls-cipher-suites` takes one comma-separated value with no spaces.

---

## Question 7: A Service with no endpoints

```bash
kubectl get pods -n svc-orders -o wide
kubectl get svc,endpointslice -n svc-orders
```

The Pods are `Running`. The Service has a ClusterIP and **no endpoints**, which narrows it to one thing: nothing matches the selector. Compare the two sides:

```bash
kubectl get svc checkout -n svc-orders -o jsonpath='{.spec.selector}{"\n"}'
kubectl get pods -n svc-orders --show-labels
```

```
{"app":"checkout"}
app=checkout-api,tier=backend
```

The Service selects `app=checkout`; the Pods carry `app=checkout-api`. No endpoints means zero Pods match — a Service with a ClusterIP that refuses connections is almost always this.

The Deployment and its labels were declared off limits, so the Service is what changes:

```bash
kubectl patch svc checkout -n svc-orders -p '{"spec":{"selector":{"app":"checkout-api"}}}'
kubectl get endpointslice -n svc-orders -l kubernetes.io/service-name=checkout
```

Verify from the Pod that is there for the purpose, exactly as the question words it:

```bash
kubectl exec -n svc-orders probe -- wget -qO- --timeout=5 http://checkout
```

That is a real end-to-end check: it only answers if the Service selects the Pods *and* the name resolves to it. If you want to separate the two — a useful habit when a Service looks right but a request still fails — take the name out of the picture and go straight to the address:

```bash
IP=$(kubectl get svc checkout -n svc-orders -o jsonpath='{.spec.clusterIP}')
kubectl exec -n svc-orders probe -- wget -qO- --timeout=5 "http://$IP"
```

---

## Question 8: Cluster-wide DNS failure

This one is on the auxiliary cluster. Get a shell on it first — `kubectl` there is already pointed at that cluster, so nothing needs exporting:

```bash
ssh aux
kubectl get nodes
```

Everything down to the fix runs on that node.

```bash
kubectl exec -n dns-check ticker -- nslookup kubernetes.default.svc.cluster.local
```

It times out. Work down the chain — the Pods first:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

CoreDNS is `Running`, no restarts, clean logs. So CoreDNS is fine and something in front of it is not:

```bash
kubectl get svc kube-dns -n kube-system
kubectl get endpointslice -n kube-system -l kubernetes.io/service-name=kube-dns
```

**No endpoints.** Same class of fault as question 7, on the object the whole cluster depends on. Compare the selector against the labels:

```bash
kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.selector}{"\n"}'
kubectl get pods -n kube-system -l k8s-app=kube-dns --show-labels
```

```
{"k8s-app":"core-dns"}
k8s-app=kube-dns,pod-template-hash=...
```

The Service selects `k8s-app=core-dns`; the Pods carry `k8s-app=kube-dns`. Every Pod on that cluster is sending queries to a ClusterIP with nothing behind it.

```bash
kubectl patch svc kube-dns -n kube-system -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'
kubectl get endpointslice -n kube-system -l kubernetes.io/service-name=kube-dns
kubectl exec -n dns-check ticker -- nslookup kubernetes.default.svc.cluster.local
```

Endpoints appear immediately; resolution follows within a few seconds, once kube-proxy reprograms.

Now the capture. The file has to land on the **jumphost**, not on the `aux` node, so log out and let the redirection happen on this side:

```bash
exit                                    # back on ckad9999
mkdir -p /tmp/exam/q8
ssh aux "kubectl exec -n dns-check ticker -- nslookup kubernetes.default.svc.cluster.local" \
  > /tmp/exam/q8/lookup.txt
cat /tmp/exam/q8/lookup.txt
```

The auxiliary cluster's kubeconfig is also on the jumphost, so this works just as well and saves the round trip:

```bash
kubectl --kubeconfig=/home/candidate/.kube/kubeconfig-aux \
  exec -n dns-check ticker -- nslookup kubernetes.default.svc.cluster.local \
  > /tmp/exam/q8/lookup.txt
```

Three details worth carrying away.

The redirection has to be **outside** `kubectl exec` — the shell that writes the file is the jumphost's, not the container's. The same is true of `ssh`: `ssh aux "cmd" > file` writes the file here, `ssh aux "cmd > file"` writes it there.

The name has to be **fully qualified**. `ticker` runs busybox, and busybox's `nslookup` queries exactly the name you hand it: it never walks the `search` list in `/etc/resolv.conf`. So `nslookup kubernetes.default` answers `NXDOMAIN` from that Pod even when DNS is perfectly healthy, while the FQDN answers with the `kubernetes` Service address. If you are debugging DNS from a busybox Pod and a short name fails, try the FQDN before concluding the cluster is broken:

```bash
kubectl exec -n dns-check ticker -- cat /etc/resolv.conf
kubectl exec -n dns-check ticker -- nslookup kubernetes.default          # NXDOMAIN
kubectl exec -n dns-check ticker -- nslookup kubernetes.default.svc.cluster.local
```

And the service named `kube-dns` is what every Pod's `/etc/resolv.conf` points at even though CoreDNS is the implementation behind it; the name is a holdover and is worth remembering, because it is the object you go and look at when nothing resolves.

---

## Question 9: A policy that controls both directions

The trap in this question is the second half. Adding `Egress` to `policyTypes` denies *everything* outbound that is not explicitly permitted — including DNS, which nothing in the question reminds you about and which breaks the Pod in a way that looks unrelated.

```bash
kubectl get pods -n net-orders --show-labels
kubectl get ns net-ledger --show-labels
```

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: orders-lockdown
  namespace: net-orders
spec:
  podSelector:
    matchLabels:
      app: orders
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: gateway
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          tier: ledger
      podSelector:
        matchLabels:
          app: ledger
    ports:
    - protocol: TCP
      port: 80
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
```

Three details decide whether this is right:

- In the ingress rule, `from` has a `podSelector` with **no** `namespaceSelector`, which means "Pods with this label in the policy's own namespace". That is what was asked for.
- In the first egress rule, `namespaceSelector` and `podSelector` are two keys of **one** list entry, so both must match. Written as two entries (each with its own `-`) it would mean "any Pod in the ledger namespace **or** any Pod labelled `app=ledger` anywhere", which is much wider.
- DNS needs **both** protocols. UDP 53 carries almost every query, but resolvers fall back to TCP for large responses, and a policy that only permits UDP fails intermittently and confusingly.

`kubernetes.io/metadata.name` is set automatically on every namespace, so it is the reliable way to select `kube-system` without labelling it yourself — and the question forbids adding namespace labels.

Test it:

```bash
IP=$(kubectl get pod orders -n net-orders -o jsonpath='{.status.podIP}')
kubectl exec -n net-orders gateway   -- wget -qO- --timeout=5 "http://$IP"   # works
kubectl exec -n net-orders reporting -- wget -qO- --timeout=5 "http://$IP"   # times out
kubectl exec -n net-orders orders -- getent hosts kubernetes.default          # resolves
```

---

## Question 10: An egress policy that is too tight

```bash
kubectl get networkpolicy -n net-billing
kubectl describe networkpolicy billing-egress -n net-billing
```

```
Allowing egress traffic:
  To Port: 80/TCP
  To:
    PodSelector: app=archive
```

The policy permits egress to `app=archive` — which is the one Pod `billing` is supposed to *never* reach — and to nothing else. Because `policyTypes` includes `Egress`, everything not listed is denied, so `invoice` is unreachable. The rule is not missing, it names the wrong peer.

```bash
kubectl get pods -n net-billing --show-labels
```

Repair the selector in place, keeping the policy's shape:

```bash
kubectl patch networkpolicy billing-egress -n net-billing --type=json \
  -p '[{"op":"replace","path":"/spec/egress/0/to/0/podSelector/matchLabels/app","value":"invoice"}]'
```

Confirm both halves — the access that must work and the access that must not:

```bash
IP=$(kubectl get svc invoice -n net-billing -o jsonpath='{.spec.clusterIP}')
kubectl exec -n net-billing billing -- wget -qO- --timeout=5 "http://$IP"

ARCHIVE=$(kubectl get pod archive -n net-billing -o jsonpath='{.status.podIP}')
kubectl exec -n net-billing billing -- wget -qO- --timeout=5 "http://$ARCHIVE"   # must time out
```

Deleting the policy, or adding `- to: []`, makes the first test pass and the second fail. Both are checked.

---

## Question 11: Three kinds of Service

The container declares a **named** port, which is what the first two Services have to target:

```bash
kubectl get deployment edge-web -n svc-edge \
  -o jsonpath='{.spec.template.spec.containers[0].ports}{"\n"}'
```

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: edge-internal
  namespace: svc-edge
spec:
  type: ClusterIP
  selector:
    app: edge-web
  ports:
  - port: 8080
    targetPort: http-web
---
apiVersion: v1
kind: Service
metadata:
  name: edge-public
  namespace: svc-edge
spec:
  type: NodePort
  selector:
    app: edge-web
  ports:
  - port: 80
    targetPort: http-web
    nodePort: 30880
---
apiVersion: v1
kind: Service
metadata:
  name: edge-vendor
  namespace: svc-edge
spec:
  type: ExternalName
  externalName: vendor.example.com
EOF
```

Targeting a port by name is what lets the Deployment renumber its container port without every Service having to follow. An `ExternalName` Service has no selector, no ports and no ClusterIP — it is purely a DNS `CNAME`, which also means it is one of the few Kubernetes objects that stops working when cluster DNS is broken.

```bash
kubectl get svc -n svc-edge
```

---

## Question 12: A base and an overlay from scratch

```bash
mkdir -p /tmp/exam/q12/base /tmp/exam/q12/overlays/production
cd /tmp/exam/q12/base

cat > deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trade-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: trade-app
  template:
    metadata:
      labels:
        app: trade-app
    spec:
      containers:
      - name: trade-app
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF

cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
EOF
```

The overlay carries every transformation. `replicas` and `images` are built-in fields — neither needs a patch file:

```bash
cd /tmp/exam/q12/overlays/production
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: kustom-prod
namePrefix: prod-
labels:
- pairs:
    env: production
  includeSelectors: false
replicas:
- name: trade-app
  count: 3
images:
- name: nginx
  newTag: 1.27.4
EOF
```

`commonLabels` is the older spelling and still works, but it is deprecated and it always writes into selectors as well, which changes the Deployment's immutable `spec.selector`. The `labels:` form with `includeSelectors: false` adds the label without touching the selector.

Render first, apply second — building before applying is how you catch a mistake without putting it in the cluster:

```bash
kubectl kustomize /tmp/exam/q12/overlays/production
kubectl apply -k /tmp/exam/q12/overlays/production
kubectl kustomize /tmp/exam/q12/overlays/production > /tmp/exam/q12/rendered.yaml
kubectl get deployment -n kustom-prod
```

`replicas` in the overlay names the resource by its **base** name (`trade-app`), not the prefixed one — the transformation happens before the prefix is applied.

---

## Question 13: Patches and a generated Secret

Two patch styles, each in its own file, plus a generator:

```bash
cd /tmp/exam/q13/overlays/staging

cat > log-level-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    spec:
      containers:
      - name: api
        env:
        - name: LOG_LEVEL
          value: debug
EOF

cat > replicas-patch.yaml <<'EOF'
- op: replace
  path: /spec/replicas
  value: 3
EOF

cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: kustom-stage
patches:
- path: log-level-patch.yaml
- path: replicas-patch.yaml
  target:
    kind: Deployment
    name: api
secretGenerator:
- name: api-credentials
  type: Opaque
  literals:
  - API_TOKEN=stage-7f3c
EOF

kubectl kustomize .
kubectl apply -k .
```

The difference between the two is worth internalising. A **strategic merge patch** is a partial copy of the object, and kustomize identifies its target from the `apiVersion`/`kind`/`name` inside the file — which is why the container is matched by name and its other fields survive. A **JSON 6902 patch** is a list of `op`/`path` operations against the document, has no identifying fields of its own, and therefore needs an explicit `target:`.

`secretGenerator` appends a content hash to the name (`api-credentials-9t2fbc4h6d`) so that changing the value produces a new object and forces a rollout. Anything referring to it by the bare name is rewritten automatically:

```bash
kubectl get secret -n kustom-stage
kubectl get deployment api -n kustom-stage \
  -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
```

---

## Question 14: An overlay that will not render

```bash
kubectl kustomize /tmp/exam/q14/overlays/staging
```

```
error: accumulating resources: ... '/tmp/exam/q14/overlays/base': no such file or directory
```

kustomize reports the *first* failure and stops, so fix one and run it again rather than assuming that is the whole story.

**Fault 1** — the resources path. The overlay is at `overlays/staging`, two levels below the base, but points one level up:

```bash
cd /tmp/exam/q14/overlays/staging
sed -i 's#- \.\./base#- ../../base#' kustomization.yaml
kubectl kustomize .
```

```
error: no resource matches strategic merge patch "StatefulSet.v1.apps/reports"
```

**Fault 2** — the patch names the wrong kind. The base builds a `Deployment`; the patch declares `StatefulSet`, so it matches nothing. A strategic merge patch is identified by what is inside it, so `kind` is not decoration:

```bash
sed -i 's/kind: StatefulSet/kind: Deployment/' replica-patch.yaml
kubectl kustomize .
```

It renders now, but the image is still the base's `nginx:1.25`. Nothing was broken there — the overlay simply never had an image transformation. That is the third edit rather than a third fault: the question asks for `1.27.4` as a requirement of its own, and the base is off limits, so the tag has to be set in the overlay:

```bash
cat >> kustomization.yaml <<'EOF'
images:
- name: nginx
  newTag: 1.27.4
EOF

kubectl kustomize . > /tmp/exam/q14/rendered.yaml
grep -E 'namespace:|replicas:|image:' /tmp/exam/q14/rendered.yaml
```

Do **not** apply this one — the question requires `kustom-fix` to stay empty, and that is checked.

---

## Question 15: Objects that cannot be edited

`kubectl create configmap` has no `--immutable` flag, so the field goes in by hand. Generate the object and add it:

```bash
kubectl create configmap audit-config -n compliance \
  --from-literal=MIN_TLS_VERSION=1.2 \
  --from-literal=AUDIT_MODE=enabled \
  --dry-run=client -o yaml > /tmp/exam/q15-cm.yaml
echo "immutable: true" >> /tmp/exam/q15-cm.yaml
kubectl apply -f /tmp/exam/q15-cm.yaml
```

`immutable` is a **top-level** field on ConfigMaps and Secrets, a sibling of `data` and `metadata` — not something under `spec`. ConfigMaps and Secrets have no `spec` at all, which is the mistake that costs this question most often.

Same shape for the Secret:

```bash
kubectl create secret generic audit-keys -n compliance \
  --from-literal=SIGNING_KEY=r7-audit-2026 \
  --dry-run=client -o yaml > /tmp/exam/q15-secret.yaml
echo "immutable: true" >> /tmp/exam/q15-secret.yaml
kubectl apply -f /tmp/exam/q15-secret.yaml
```

Prove the API server enforces it, rather than trusting the field:

```bash
kubectl patch configmap audit-config -n compliance -p '{"data":{"AUDIT_MODE":"disabled"}}'
```

```
The ConfigMap "audit-config" is invalid: data: Forbidden: field is immutable when `immutable` is set
```

Or write both in one go:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: audit-config
  namespace: compliance
immutable: true
data:
  MIN_TLS_VERSION: "1.2"
  AUDIT_MODE: "enabled"
```

Quote `1.2` — unquoted it parses as a float and the ConfigMap is rejected, because ConfigMap values must be strings.

---

## Question 16: Rotating an immutable ConfigMap

The instinct is to change the ConfigMap in place. Every route to that is closed:

```bash
kubectl edit configmap feature-flags -n config-rotate       # rejected
kubectl patch configmap feature-flags -n config-rotate \
  -p '{"data":{"RELEASE_CHANNEL":"stable"}}'                # rejected
kubectl apply -f new-flags.yaml                             # rejected
```

```
The ConfigMap "feature-flags" is invalid: data: Forbidden: field is immutable
```

The second instinct is to delete it and recreate it under the same name. **Do not do that**, and the reason is the whole point of the question.

Marking a ConfigMap immutable does more than reject writes: it tells every kubelet that the object can never change, so the kubelet **stops watching it** and caches it for the lifetime of the node. That is the documented performance benefit of `immutable: true`. It also means a kubelet that has already cached `feature-flags` never learns that you deleted and recreated it — so new Pods on that node keep receiving the *old* values, indefinitely, while Pods on a node that had no cache get the new ones. You end up with a Deployment whose replicas disagree with each other and no amount of restarting fixes the stale node:

```
feature-api-...-kw9rn   on cluster-worker3   RELEASE_CHANNEL=stable
feature-api-...-tkkgl   on cluster-worker    RELEASE_CHANNEL=beta
```

The supported way to roll an immutable ConfigMap is to create a **new object under a new name** and repoint its consumers:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags-v2
  namespace: config-rotate
immutable: true
data:
  RELEASE_CHANNEL: "stable"
  MAX_BATCH_SIZE: "200"
EOF
```

Then switch the Deployment's `envFrom` reference. Editing the Pod template is itself the rollout trigger, so no `rollout restart` is needed:

```bash
kubectl patch deployment feature-api -n config-rotate --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/envFrom/0/configMapRef/name","value":"feature-flags-v2"}]'
kubectl rollout status deployment/feature-api -n config-rotate
```

Confirm the environment where it actually matters — inside a running Pod, not in the ConfigMap:

```bash
kubectl exec -n config-rotate deploy/feature-api -- env | grep -E 'RELEASE_CHANNEL|MAX_BATCH'
```

```
MAX_BATCH_SIZE=200
RELEASE_CHANNEL=stable
```

`envFrom` is resolved when a **container starts**, so repointing the Deployment without letting the new Pods roll out would leave the old environment running. (A ConfigMap mounted as a *volume* is refreshed in place; one consumed as environment variables never is.) The verification reads the environment out of a running Pod for exactly that reason.

This is also why `configMapGenerator` in question 13 appends a content hash to the name: it makes every change produce a new object under a new name, which is the same pattern applied automatically.

## Question 17: Reserving a node

A taint and a label do different jobs, and this question needs both:

```bash
kubectl taint node cluster-worker2 workload=latency:NoSchedule
kubectl label node cluster-worker2 tier=realtime
```

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quote-engine
  namespace: sched-pin
spec:
  replicas: 2
  selector:
    matchLabels:
      app: quote-engine
  template:
    metadata:
      labels:
        app: quote-engine
    spec:
      tolerations:
      - key: workload
        operator: Equal
        value: latency
        effect: NoSchedule
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: tier
                operator: In
                values:
                - realtime
      containers:
      - name: engine
        image: nginx:1.27.4
EOF

kubectl get pods -n sched-pin -o wide
```

The distinction the question is testing: a **toleration** only grants permission to land on a tainted node, it does not attract anything — with the toleration alone the scheduler is free to place both replicas on `node01`. **Node affinity** is what requires them onto `node02`. Neither alone is enough: affinity without the toleration produces Pods that are `Pending` because the only matching node repels them.

`requiredDuringSchedulingIgnoredDuringExecution` is a hard constraint evaluated at scheduling time; `IgnoredDuringExecution` means a running Pod is not evicted if the node's labels later stop matching. `preferredDuring...` would be a soft preference and would not guarantee placement.

---

## Question 18: Priority and preemption

```bash
kubectl create priorityclass batch-low --value=10000
kubectl create priorityclass critical-high --value=100000
kubectl get priorityclass
```

Neither may be `globalDefault`, which is the default for `kubectl create priorityclass` — nothing extra to do, but worth checking, because a global default silently applies to every Pod in the cluster that does not name one.

Assign the low class to the batch job. A Pod's priority is immutable, so this triggers a rollout, which is expected:

```bash
kubectl patch deployment bulk-import -n sched-priority \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"batch-low"}}}}'
kubectl rollout status deployment/bulk-import -n sched-priority
```

Now the urgent workload:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: market-feed
  namespace: sched-priority
spec:
  replicas: 2
  selector:
    matchLabels:
      app: market-feed
  template:
    metadata:
      labels:
        app: market-feed
    spec:
      priorityClassName: critical-high
      nodeSelector:
        ck-x.io/alias: node03
      containers:
      - name: feed
        image: nginx:1.27.4
        resources:
          requests:
            memory: "512Mi"
EOF
```

Watch it happen:

```bash
kubectl get pods -n sched-priority -o wide -w
kubectl get events -n sched-priority --sort-by=.lastTimestamp | grep -i preempt
```

The `market-feed` Pods are briefly `Pending`, the scheduler evicts enough `bulk-import` Pods to make room, and `market-feed` schedules. The evicted replicas go back to `Pending` — their Deployment still wants three — and stay there, which is the correct end state: preemption made room for the higher-priority work and the lower-priority work waits.

Two things that quietly break this: setting `preemptionPolicy: Never` on `critical-high` makes it schedule *ahead* of lower-priority Pods in the queue but never evict anything, so it stays `Pending` forever; and scaling `bulk-import` down by hand makes room without exercising preemption at all, which is why the verification checks it still declares three replicas.
