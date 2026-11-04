# CKA Practice Lab 011 — Cluster Observability & Network Scoping — Answers

This lab runs on a **kubeadm-bootstrapped cluster** (`clusterType: kind`) with a control
plane and two workers, reachable from the jumphost as `ssh controlplane`, `ssh node01` and
`ssh node02`. Question 6 is set on a **second, single-node cluster**, reachable as `ssh aux`.

Three questions — 3, 4/5 and 6 — carry extra weight on purpose. They are the Metrics API,
the structure of a NetworkPolicy rule, and editing the CoreDNS Corefile.

---

## Question 1 — Add a context to a kubeconfig

A context is three things: a cluster, a user, and optionally a namespace. `kubectl config`
edits a kubeconfig file in place, so there is no need to open it in an editor:

```bash
kubectl --kubeconfig /tmp/exam/q1/ops.kubeconfig config set-context tower \
  --cluster=airops --user=tower-ops --namespace=ops-access

kubectl --kubeconfig /tmp/exam/q1/ops.kubeconfig config use-context tower
```

Check it the way the grader does — with no `-n`:

```bash
kubectl --kubeconfig /tmp/exam/q1/ops.kubeconfig config get-contexts
kubectl --kubeconfig /tmp/exam/q1/ops.kubeconfig get pods
```

The second command must list `windsock`. If it prompts you for a username instead, the
context is pointing at a user entry that does not exist — `set-context` happily writes a
name that no `users:` entry matches.

---

## Question 2 — Install and upgrade a Helm release

`helm install` takes a chart directory just as happily as a repository reference:

```bash
helm install beacon /tmp/exam/q2/beacon-chart -n ops-charts --set replicaCount=2
```

Then the upgrade. `--set` on an upgrade only carries the values you name, so `replicaCount`
has to be repeated or it falls back to the chart default of `1`:

```bash
helm upgrade beacon /tmp/exam/q2/beacon-chart -n ops-charts \
  --set replicaCount=2 --set message=active
```

`--reuse-values` is the alternative if you prefer not to restate them.

```bash
helm list -n ops-charts              # STATUS deployed, REVISION 2
helm history beacon -n ops-charts
kubectl -n ops-charts get pod -o jsonpath='{.items[0].spec.containers[0].env}'
```

A release ends up at revision 2 only if you installed once and upgraded once. If you
uninstalled and reinstalled to fix a mistake, you are back at revision 1 and need one more
upgrade.

---

## Question 3 — Make the Metrics API work ★

`kubectl top` is served by the `metrics.k8s.io` API, which the API server aggregates from a
metrics-server Deployment. There is none on this cluster, so start by applying the manifest:

```bash
kubectl apply -f /tmp/exam/q3/metrics-server.yaml
kubectl -n kube-system rollout status deployment/metrics-server
```

The Deployment comes up, and `kubectl top node` still fails. Look at why:

```bash
kubectl get apiservice v1beta1.metrics.k8s.io -o yaml | grep -A5 conditions
kubectl -n kube-system logs deployment/metrics-server | tail -20
```

The logs report `x509: cannot validate certificate for <ip> because it doesn't contain any
IP SANs`. metrics-server scrapes each kubelet over HTTPS and verifies its serving
certificate, and on a kubeadm cluster those certificates are self-signed by each node unless
`serverTLSBootstrap` is turned on. The question forbids changing kubelet configuration or
node certificates, so the fix belongs on the metrics-server side:

```bash
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl -n kube-system rollout status deployment/metrics-server
```

Give it about a scrape interval, then:

```bash
kubectl top node
kubectl top pod -n ops-metrics --containers
```

`--containers` is what produces a row per container rather than per Pod — that is the flag
the second half of this question is about.

If `kubectl top node` still reports only some nodes, one kubelet is unreachable; check
`kubectl -n kube-system logs deployment/metrics-server` again rather than waiting longer.

---

## Question 4 — Egress scoped per destination **and** per port ★

This is the question that separates people who have read the NetworkPolicy schema from
people who have skimmed it. `spec.egress` is a **list of rules**. Within one rule, `to` and
`ports` are ANDed. Across rules, everything is ORed. So a rule listing two destinations and
two ports means *(either destination) AND (either port)* — all four combinations.

Here `beacon` and `archive` both listen on **both** ports, which makes the difference
visible. Two rules, each pairing one destination with one port:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: radar-egress
  namespace: net-radar
spec:
  podSelector:
    matchLabels:
      app: radar
  policyTypes:
  - Egress
  egress:
  - to:                          # first rule
    - podSelector:
        matchLabels:
          app: beacon
    ports:
    - protocol: TCP
      port: 5555
  - to:                          # second rule
    - podSelector:
        matchLabels:
          app: archive
    ports:
    - protocol: TCP
      port: 6666
```

```bash
kubectl apply -f radar-egress.yaml
```

Verify all four cells, not just the two that should work. The nginx image has no `curl` and
no `wget`, but it is Debian-based, so bash's `/dev/tcp` is available:

```bash
BEACON=$(kubectl -n net-radar get pod beacon -o jsonpath='{.status.podIP}')
ARCHIVE=$(kubectl -n net-radar get pod archive -o jsonpath='{.status.podIP}')

kubectl -n net-radar exec radar -- timeout 4 bash -c "echo > /dev/tcp/$BEACON/5555"   # allowed
kubectl -n net-radar exec radar -- timeout 4 bash -c "echo > /dev/tcp/$ARCHIVE/6666"  # allowed
kubectl -n net-radar exec radar -- timeout 4 bash -c "echo > /dev/tcp/$BEACON/6666"   # must fail
kubectl -n net-radar exec radar -- timeout 4 bash -c "echo > /dev/tcp/$ARCHIVE/5555"  # must fail
```

`kubectl describe networkpolicy radar-egress -n net-radar` prints how Kubernetes read your
policy, and is the fastest way to see a merged rule for what it is.

### The shape to avoid

```yaml
  egress:
  - to:                          # ONE rule -- wrong
    - podSelector:
        matchLabels:
          app: beacon
    - podSelector:
        matchLabels:
          app: archive
    ports:
    - protocol: TCP
      port: 5555
    - protocol: TCP
      port: 6666
```

This reads as *(beacon OR archive) AND (5555 OR 6666)*. It passes both "can reach" checks
and fails both "cannot reach" ones.

---

## Question 5 — Repair an over-permissive egress policy ★

**Investigate first.** Confirm the audit's claim and see what the policy actually says:

```bash
GATE=$(kubectl -n net-apron get pod gate -o jsonpath='{.status.podIP}')
FUEL=$(kubectl -n net-apron get pod fuel -o jsonpath='{.status.podIP}')

kubectl -n net-apron exec apron -- timeout 4 bash -c "echo > /dev/tcp/$FUEL/7001"   # succeeds, and should not
kubectl -n net-apron exec apron -- timeout 4 bash -c "echo > /dev/tcp/$GATE/7002"   # succeeds, and should not

kubectl -n net-apron get networkpolicy apron-egress -o yaml
kubectl -n net-apron describe networkpolicy apron-egress
```

**The fault.** `apron-egress` has a single egress rule carrying both destinations *and* both
ports. Kubernetes ANDs `to` with `ports` inside a rule and ORs the entries within each of
them, so the policy grants *(gate OR fuel) AND (7001 OR 7002)* — every combination, which is
exactly what the audit found. The policy is not missing anything; it is one rule where it
should be two.

**The fix.** Split it, pairing each destination with the port it is approved for. The policy
object is kept, as the question requires — only its `egress` list changes:

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: apron-egress
  namespace: net-apron
spec:
  podSelector:
    matchLabels:
      app: apron
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: gate
    ports:
    - protocol: TCP
      port: 7001
  - to:
    - podSelector:
        matchLabels:
          app: fuel
    ports:
    - protocol: TCP
      port: 7002
EOF
```

Then re-run all four probes. The two approved paths must still work; the two the audit
flagged must now time out.

---

## Question 6 — A second cluster DNS domain ★

This one is on the auxiliary cluster. Everything below runs after `ssh aux`, except the
backup, whose redirection has to stay on the jumphost.

**Back up first.** The file has to live on the jumphost, so run `kubectl` over SSH and
redirect on this side of the connection:

```bash
mkdir -p /tmp/exam/q6
ssh aux "kubectl -n kube-system get configmap coredns -o yaml" > /tmp/exam/q6/coredns-backup.yaml
```

Writing `ssh aux "kubectl ... > /tmp/exam/q6/..."` would put the file on the *aux node*,
where nothing looks for it.

**Then the Corefile.** CoreDNS reads its configuration from the `coredns` ConfigMap in
`kube-system`. The `kubernetes` plugin line lists the zones it is authoritative for, and it
accepts more than one:

```bash
ssh aux
kubectl -n kube-system edit configmap coredns
```

```
        kubernetes cluster.local airops.internal in-addr.arpa ip6.arpa {
```

`airops.internal` goes on the **same line**, next to `cluster.local` — adding a whole second
server block would also work but is far more to get right under time pressure.

CoreDNS has the `reload` plugin enabled and picks the change up within a couple of minutes,
but do not wait for it:

```bash
kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns
```

Both Pods coming back `Running` is itself the syntax check: a Corefile that does not parse
leaves them crash-looping.

**Verify both domains:**

```bash
kubectl -n dns-tower exec probe -- nslookup tower.dns-tower.svc.airops.internal.
kubectl -n dns-tower exec probe -- nslookup tower.dns-tower.svc.cluster.local.
kubectl -n dns-tower get svc tower        # both must answer with this cluster IP
```

The trailing dot matters. Without it a resolver may walk the Pod's `search` list and answer
from a domain you did not intend to test.

**If you break it**, that is what the backup is for:

```bash
ssh aux "kubectl delete -f -" < /tmp/exam/q6/coredns-backup.yaml
ssh aux "kubectl apply -f -"  < /tmp/exam/q6/coredns-backup.yaml
ssh aux "kubectl -n kube-system rollout restart deployment/coredns"
```

---

## Question 7 — Pod-level DNS configuration

A Pod's resolver is configured by `spec.dnsConfig`, which *adds to* what `dnsPolicy`
generates rather than replacing it:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: briefing
  namespace: dns-apron
spec:
  dnsPolicy: ClusterFirst
  dnsConfig:
    searches:
    - dns-apron-wx.svc.cluster.local
    options:
    - name: ndots
      value: "1"
  containers:
  - name: briefing
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
```

```bash
kubectl apply -f briefing.yaml
kubectl -n dns-apron exec briefing -- cat /etc/resolv.conf
kubectl -n dns-apron exec briefing -- nslookup wx-feed
kubectl -n dns-apron-wx get svc wx-feed
```

`/etc/resolv.conf` inside the Pod should show your search domain appended after the three
that `ClusterFirst` generates. Note that `nslookup` here is queried **without** a trailing
dot — the whole point is that the search list completes it.

---

## Question 8 — Bind a claim to one of two identical volumes

Both volumes offer 5Gi `ReadWriteOnce`, so capacity and access mode cannot choose between
them. Labels can, through the claim's `selector`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cargo-claim
  namespace: stor-cargo
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ""
  resources:
    requests:
      storage: 2Gi
  selector:
    matchLabels:
      tier: fast
```

`storageClassName: ""` is load-bearing and is the part most people miss. This cluster has a
**default StorageClass**, and admission writes it into any claim that leaves the field out —
at which point the claim is dynamically provisioned a brand-new volume and never looks at
`cargo-fast` or `cargo-slow` at all. The empty string means "no class", which is what these
two statically-provisioned volumes declare.

```bash
kubectl get pv --show-labels
kubectl -n stor-cargo get pvc cargo-claim      # STATUS Bound, VOLUME cargo-fast
```

Then the Deployment:

```bash
kubectl -n stor-cargo create deployment cargo-hold --image=nginx:1.27.4 \
  --dry-run=client -o yaml > cargo-hold.yaml
```

Edit it so the container is named `hold` and the claim is mounted:

```yaml
    spec:
      volumes:
      - name: cargo
        persistentVolumeClaim:
          claimName: cargo-claim
      containers:
      - name: hold
        image: nginx:1.27.4
        volumeMounts:
        - name: cargo
          mountPath: /var/cargo
```

---

## Question 9 — StatefulSet claims across a scale-in

By default a StatefulSet keeps every per-Pod claim forever — deleting the StatefulSet and
scaling it in both leave the storage behind. `persistentVolumeClaimRetentionPolicy` splits
those two cases:

```bash
kubectl -n wl-baggage patch statefulset belt --type=merge -p \
  '{"spec":{"persistentVolumeClaimRetentionPolicy":{"whenScaled":"Delete","whenDeleted":"Retain"}}}'

kubectl -n wl-baggage scale statefulset belt --replicas=1
```

Order matters: set the policy **before** scaling. The controller reclaims a claim as the
replica goes away, so scaling first and setting the policy afterwards leaves `data-belt-1`
and `data-belt-2` sitting there, and you would have to delete them by hand.

```bash
kubectl -n wl-baggage get statefulset belt -o jsonpath='{.spec.persistentVolumeClaimRetentionPolicy}'
kubectl -n wl-baggage get pvc
```

Only `data-belt-0` should remain.

---

## Question 10 — A create-only Role

```bash
kubectl -n rbac-tower create serviceaccount flightplan-writer

kubectl -n rbac-tower create role flightplan-writer \
  --verb=create --resource=configmaps --resource=secrets

kubectl -n rbac-tower create rolebinding flightplan-writer \
  --role=flightplan-writer --serviceaccount=rbac-tower:flightplan-writer
```

`--verb=create` and nothing else is the whole answer. It is tempting to add `get`, because
almost every Role you have ever seen has it, but "only create" means only create.

Prove it both ways — a grant is only narrow if you check what it refuses:

```bash
kubectl auth can-i create configmaps -n rbac-tower --as=system:serviceaccount:rbac-tower:flightplan-writer  # yes
kubectl auth can-i create secrets    -n rbac-tower --as=system:serviceaccount:rbac-tower:flightplan-writer  # yes
kubectl auth can-i list   configmaps -n rbac-tower --as=system:serviceaccount:rbac-tower:flightplan-writer  # no
kubectl auth can-i delete secrets    -n rbac-tower --as=system:serviceaccount:rbac-tower:flightplan-writer  # no
kubectl auth can-i create pods       -n rbac-tower --as=system:serviceaccount:rbac-tower:flightplan-writer  # no
```

---

## Question 11 — Query the API server from inside a Pod

Every Pod gets its ServiceAccount token and the cluster CA projected into
`/var/run/secrets/kubernetes.io/serviceaccount/`. That is all `curl` needs:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: beacon-probe
  namespace: api-beacon
spec:
  serviceAccountName: beacon-reader
  containers:
  - name: probe
    image: curlimages/curl:8.11.1
    command: ["sh", "-c", "sleep 86400"]
```

```bash
kubectl apply -f beacon-probe.yaml
kubectl -n api-beacon exec beacon-probe -- sh -c '
  SA=/var/run/secrets/kubernetes.io/serviceaccount
  curl -s --cacert $SA/ca.crt \
       -H "Authorization: Bearer $(cat $SA/token)" \
       https://kubernetes.default.svc/api/v1/namespaces/api-beacon/configmaps
' > /tmp/exam/q11/configmaps.json
```

Two things that commonly go wrong:

- **`--cacert`, not `-k`.** The question forbids disabling verification, and the CA that
  signs the API server is mounted right there next to the token.
- **Namespace-scoped path.** `beacon-reader` may read ConfigMaps in `api-beacon` only;
  `/api/v1/configmaps` asks for every namespace and comes back `403`. A `Status` object in
  the file instead of a `ConfigMapList` means the request was refused — read its `message`,
  it names the identity that was rejected.

`curlimages/curl` is specified rather than `busybox` for a reason: busybox's `ssl_client`
cannot complete the TLS handshake with the API server and fails before authorization is ever
reached, which makes a perfectly good answer look broken.

```bash
jq '.kind, (.items | length)' /tmp/exam/q11/configmaps.json
```

---

## Question 12 — A DaemonSet on every node

A DaemonSet already targets every node; what stops it reaching the control plane is that
node's `NoSchedule` taint. Tolerate it:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: deice
  namespace: ds-deice
spec:
  selector:
    matchLabels:
      app: deice
  template:
    metadata:
      labels:
        app: deice
        zone: apron
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
      containers:
      - name: deice
        image: nginx:1.27.4
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
```

```bash
kubectl apply -f deice.yaml
kubectl -n ds-deice get daemonset deice          # DESIRED and READY both 3
kubectl -n ds-deice get pods -o wide             # one per node
```

`kubectl describe node <controlplane>` under `Taints:` tells you the key and effect to
tolerate — worth checking rather than remembering, since the key changed in 1.24.

---

## Question 13 — Find a Pod's container with crictl

```bash
kubectl -n node-crictl get pod tug -o wide       # which node
```

`crictl` talks to the container runtime on one node, so you have to be on the node that runs
the Pod:

```bash
ssh node01
sudo crictl ps --name tug
sudo crictl inspect <container-id> | jq -r '.info.runtimeType'
```

Then write the two files **on the jumphost**. The neatest way is to keep the redirection on
this side rather than copying files back:

```bash
ID=$(ssh node01 "crictl ps -q --name '^tug$' --state Running")
RT=$(ssh node01 "crictl inspect $ID" | jq -r '.info.runtimeType')

mkdir -p /tmp/exam/q13
echo "$ID $RT" > /tmp/exam/q13/container.txt
ssh node01 "crictl logs $ID" > /tmp/exam/q13/container.log 2>&1
```

The ID that `crictl ps` prints in its table is truncated; either form is accepted, as long
as it really is the ID of the running container.

---

## Question 14 — Read one certificate, renew one other

```bash
ssh controlplane
openssl x509 -noout -enddate -in /etc/kubernetes/pki/etcd/server.crt
```

Cross-check with kubeadm, which reports the same dates in its own format:

```bash
kubeadm certs check-expiration
```

Write the file on the jumphost, keeping the redirection on this side:

```bash
mkdir -p /tmp/exam/q14
ssh controlplane "openssl x509 -noout -enddate -in /etc/kubernetes/pki/etcd/server.crt" \
  | cut -d= -f2- > /tmp/exam/q14/etcd-expiry.txt
```

Then renew **one** certificate. `kubeadm certs renew` takes the name of a single certificate,
and `kubeadm certs renew --help` lists them:

```bash
ssh controlplane "kubeadm certs renew apiserver-kubelet-client"
```

Do **not** reach for `kubeadm certs renew all`. It satisfies the renewal check and then fails
the constraint check, because it rewrites every other certificate too.

```bash
ssh controlplane "openssl x509 -noout -startdate -in /etc/kubernetes/pki/apiserver-kubelet-client.crt"
ssh controlplane "openssl x509 -noout -startdate -in /etc/kubernetes/pki/apiserver.crt"
```

The first should be today; the second should not have moved. A renewed certificate is only
picked up by the API server when it restarts, which this question does not ask for.

---

## Question 15 — An autoscaler through Kustomize

Work in `/tmp/exam/q15/flightboard`.

**Remove the ConfigMap from all three places.** Deleting it from `base/flightboard.yaml`
alone breaks both overlays, because each one patches it:

```
error: no resource matches strategic merge patch "ConfigMap.v1.[noGrp]/refresh-config.[noNs]"
```

So delete that document from `base/flightboard.yaml`, `staging/flightboard.yaml` **and**
`prod/flightboard.yaml`.

**Add the HPA to the base**, at the end of `base/flightboard.yaml`:

```yaml
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: flightboard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: flightboard
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

No `namespace:` — each overlay's `namespace:` field sets it.

**Override it in prod only**, by appending to `prod/flightboard.yaml`:

```yaml
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: flightboard
spec:
  maxReplicas: 6
```

Check what you built before applying it:

```bash
kubectl kustomize /tmp/exam/q15/flightboard/staging | grep -A5 maxReplicas
kubectl kustomize /tmp/exam/q15/flightboard/prod    | grep -A5 maxReplicas
```

**Apply both:**

```bash
kubectl kustomize /tmp/exam/q15/flightboard/staging | kubectl apply -f -
kubectl kustomize /tmp/exam/q15/flightboard/prod    | kubectl apply -f -
```

**Then delete the ConfigMaps by hand.** This is the part the apply does not do for you:

```bash
kubectl -n kustom-flight-staging delete configmap refresh-config
kubectl -n kustom-flight-prod    delete configmap refresh-config
```

Kustomize keeps no state. It has no idea which objects in the cluster it put there, so
removing a resource from the configuration simply stops generating it — the copy already in
the cluster stays until something deletes it. Helm can do this because it records a release;
Kustomize deliberately does not.

---

## Question 16 — Raise a workload to Guaranteed

A Pod is `Guaranteed` only when **every** container sets both CPU and memory limits, and
requests equal to them. Setting only limits also works, because admission copies them into
the requests — but being explicit is clearer:

```bash
kubectl -n qos-hangar patch deployment hangar-ops -p '
spec:
  template:
    spec:
      containers:
      - name: ops
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 50m
            memory: 64Mi
'
```

```bash
kubectl -n qos-hangar get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
```

Both Pods must read `Guaranteed`. If they read `Burstable`, a request and its limit differ
somewhere; if they read `BestEffort`, the rollout has not replaced the old Pods yet.

`kubectl patch` defaults to a **strategic** merge patch, which merges container lists on
the `name` key. Do not reach for `--type=merge` here: that is a JSON merge patch, it replaces
the whole `containers` array with what you wrote, and the API server rejects it with
`spec.template.spec.containers[0].image: Required value`.

Note that patching a container by name merges into the existing list — get the name wrong and
you *add a second container* rather than editing the one you meant, and nothing warns you.

---

## Question 17 — What kube-proxy does with a Service

```bash
kubectl -n svc-iptables expose pod apronctl --name=apronctl --port=8080 --target-port=80
kubectl -n svc-iptables get svc apronctl
kubectl -n svc-iptables get endpointslices
```

kube-proxy watches the API server and programmes every node's packet filter the moment the
Service exists. Its rules carry the Service's `namespace/name` as a comment, which is the
easiest thing to search for:

```bash
CIP=$(kubectl -n svc-iptables get svc apronctl -o jsonpath='{.spec.clusterIP}')

mkdir -p /tmp/exam/q17
ssh controlplane "iptables-save | grep svc-iptables/apronctl" > /tmp/exam/q17/rules.txt
cat /tmp/exam/q17/rules.txt
```

You should see a `KUBE-SERVICES` rule matching the cluster IP on port 8080 and a `KUBE-SEP-…`
rule DNAT-ing to the Pod's IP on port 80 — the Service's ClusterIP is a packet-filter rule,
not an address anything actually listens on.

If `iptables-save` comes back empty but the Service exists, the node may be using the nftables
backend; `nft list ruleset | grep apronctl` finds the same rules there.

To see the other half of the lesson for yourself, delete the Service and grep again — the
rules disappear within a second, because kube-proxy reconciles on every change.
