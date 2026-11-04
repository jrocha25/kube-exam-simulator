# CKA Practice Lab 012 — Selector Semantics & Pod Composition — Answers

This lab runs on a **kubeadm-bootstrapped cluster** (`clusterType: kind`) with three
worker nodes. From the jumphost you can `ssh controlplane`, `ssh node01`, `ssh node02`
and `ssh node03`, and you land as **root** — no `sudo` needed, though on the real exam
you will `ssh node01` and then `sudo -i`, so it is worth typing anyway.

Six questions — 2, 4, 6, 7, 11 and 12 — start from something that is already broken.
Each of those answers opens with the commands that find the fault before it shows the
fix; on the real exam nobody tells you what is wrong, and the diagnosis is most of the
work.

Three questions carry extra weight on purpose: **3** and **4** are ten marks each and
**5** is nine. They are the three the lab exists for.

Every question owns its own namespace, and the namespaces already exist.

---

## Question 1 — A static Pod where the kubelet is actually looking

A static Pod is run by one node's kubelet from a file on that node's disk. The API
server never creates it; it only learns about it, through a **mirror Pod** the kubelet
registers on its behalf.

The directory each kubelet watches is `staticPodPath` in its own configuration. On a
stock kubeadm node that is `/etc/kubernetes/manifests` — but it is a setting, not a
law, and on this cluster node02's has been moved. Read it:

```bash
ssh node02
grep staticPodPath /var/lib/kubelet/config.yaml
# staticPodPath: /etc/kubernetes/node-manifests
```

If the kubelet were started with flags rather than a config file, `ps aux | grep kubelet`
would show the path instead.

Then write the manifest into that directory:

```bash
cat > /etc/kubernetes/node-manifests/sensor-collector.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: sensor-collector
  namespace: node-sensor
  labels:
    duty: telemetry
spec:
  containers:
  - name: collector
    image: nginx:1.27.4
YAML
```

The kubelet rescans within a few seconds. Back on the jumphost:

```bash
kubectl get pods -n node-sensor -o wide
# NAME                               READY   STATUS    NODE
# sensor-collector-cluster-worker2   1/1     Running   cluster-worker2
```

Three things worth keeping:

- **The mirror Pod's name has the node name appended.** `sensor-collector-cluster-worker2`,
  not `sensor-collector`. That alone tells you whether a Pod came from a file or from the
  API server, and it is why `kubectl get pod sensor-collector -n node-sensor` finds
  nothing when the answer is right.
- **The namespace has to exist.** The kubelet runs the Pod regardless, but the mirror Pod
  is rejected while the namespace is missing — so the container would be running on the
  node and completely invisible to `kubectl`. This lab creates `node-sensor` for you;
  on the real exam, check.
- **Dropping the file into `/etc/kubernetes/manifests` on this node does nothing at all.**
  That directory is not what its kubelet reads. Nothing warns you.

---

## Question 2 — A Pod that will not stay deleted

**Investigate first.** Watch what actually happens:

```bash
kubectl get pods -n node-relay -o wide
kubectl delete pod relay-shim-cluster-worker -n node-relay
kubectl get pods -n node-relay           # gone
sleep 20
kubectl get pods -n node-relay           # back, same name
```

The name is the clue: it ends in a node name. Confirm it:

```bash
kubectl get pod -n node-relay -o yaml | grep -A3 ownerReferences
#   - apiVersion: v1
#     kind: Node
```

**The fault.** It is a static Pod. It is owned by the Node, not by any controller, and
it was created by a kubelet from a file on disk. Deleting it through the API server
removes the *mirror* — the kubelet notices the mirror is missing and registers a new
one, because the file is still there. Nothing in the cluster can stop that.

**The fix.** Remove the file from the node whose kubelet reads it:

```bash
ssh node01
grep staticPodPath /var/lib/kubelet/config.yaml     # /etc/kubernetes/manifests
ls /etc/kubernetes/manifests/
rm /etc/kubernetes/manifests/relay-shim.yaml
exit

kubectl get pods -n node-relay
# No resources found in node-relay namespace.
```

Delete the file by name. On a **control plane** node the same directory holds
`etcd.yaml`, `kube-apiserver.yaml`, `kube-controller-manager.yaml` and
`kube-scheduler.yaml`, and a wildcard there would take the cluster down with it.

`systemctl stop kubelet` also stops the Pod coming back, and it is the wrong answer:
the node goes `NotReady`, and five minutes later the node controller starts evicting
everything on it. The question says every node must stay `Ready` for exactly that
reason.

---

## Question 3 — One policy, one AND rule and one OR rule ★

This is the rule that decides the question, and it is the one most often got wrong:

> Inside a single `from` **entry**, `namespaceSelector` and `podSelector` are **ANDed** —
> the source must match both. Across **separate** `from` entries they are **ORed** —
> matching any one entry is enough.

So the two YAML blocks below mean completely different things, and the difference is one
dash:

```yaml
# AND: Pods labelled station-role=gateway, in a namespace labelled seismo.io/tier=api
from:
- namespaceSelector:
    matchExpressions:
    - key: seismo.io/tier
      operator: In
      values: ["api"]
  podSelector:
    matchLabels:
      station-role: gateway
```

```yaml
# OR: any Pod in that namespace, PLUS any gateway Pod anywhere
from:
- namespaceSelector:
    matchExpressions:
    - key: seismo.io/tier
      operator: In
      values: ["api"]
- podSelector:
    matchLabels:
      station-role: gateway
```

The answer needs the first shape for 8443, and a second rule — a genuine OR — for 9100:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tremor-ingress
  namespace: net-tremor
spec:
  podSelector:
    matchLabels:
      app: tremor-ingest
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchExpressions:
        - key: seismo.io/tier
          operator: In
          values: ["api"]
      podSelector:
        matchLabels:
          station-role: gateway
    ports:
    - protocol: TCP
      port: 8443
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: net-tremor-wave
    ports:
    - protocol: TCP
      port: 9100
```

Check it the way the grader does — from the Pods that are already there, never from a
Pod you create, since a new Pod is not selected by the policy you just wrote:

```bash
IP=$(kubectl get pod tremor-ingest -n net-tremor -o jsonpath='{.status.podIP}')
probe() { kubectl exec -n "$1" "$2" -- timeout 4 bash -c "echo > /dev/tcp/$IP/$3" && echo OK || echo BLOCKED; }

probe net-tremor-api  gateway-allowed  8443   # OK
probe net-tremor-api  probe-plain      8443   # BLOCKED
probe net-tremor      gateway-outsider 8443   # BLOCKED
probe net-tremor-wave wave-any         9100   # OK
probe net-tremor-wave wave-any         8443   # BLOCKED
```

Notes:

- `kubernetes.io/metadata.name` is set automatically on every namespace and equals its
  name, which is the easy way to select one namespace. This question asks for a
  `matchExpressions` term on `seismo.io/tier` for the other rule so that both selector
  forms get used.
- Once any ingress rule exists for a Pod, everything not explicitly allowed is denied.
  There is no need for a separate deny-all — and writing one *instead* of the rules
  blocks the traffic that is supposed to flow.
- `nginx` is Debian-based, so it has the `bash` whose `/dev/tcp` these probes use. It
  ships no `curl` and no `wget`.

### The shape to avoid

A policy with no `ingress` rules at all denies everything, which passes all three
"cannot reach" probes and fails the one that matters. Blocking is not scoping.

---

## Question 4 — The two selectors were split ★

**Investigate first.** Confirm the audit's claim, then read the policy:

```bash
IP=$(kubectl get pod station-relay -n net-array -o jsonpath='{.status.podIP}')
probe() { kubectl exec -n "$1" "$2" -- timeout 4 bash -c "echo > /dev/tcp/$IP/8443" && echo OK || echo BLOCKED; }

probe net-array-edge edge-collector   # OK       -- approved
probe net-array-edge edge-visitor     # OK       -- should not be
probe net-array      local-collector  # OK       -- should not be

kubectl get networkpolicy array-ingress -n net-array -o yaml
```

**The fault.** The rule's `from` list has **two entries**:

```yaml
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: net-array-edge
    - podSelector:
        matchLabels:
          station-role: collector
```

Two entries are an OR, so the policy grants *(any Pod in net-array-edge)* **or** *(any
Pod labelled `station-role=collector`)*. That is why `edge-visitor` gets in on its
namespace alone and `local-collector` gets in on its label alone.

A `from` entry carrying only a `podSelector` is evaluated against the **policy's own
namespace** — which is how a Pod in `net-array` itself ended up admitted by a rule that
was meant to describe the edge fleet.

**The fix.** Collapse the two entries into one, so both conditions have to hold:

```bash
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: array-ingress
  namespace: net-array
spec:
  podSelector:
    matchLabels:
      app: station-relay
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: net-array-edge
      podSelector:
        matchLabels:
          station-role: collector
    ports:
    - protocol: TCP
      port: 8443
YAML
```

Re-run all three probes: the approved one must still be `OK`, the other two `BLOCKED`.
That first probe is not a formality — deleting the policy, or replacing it with a
deny-all, also silences the two the audit flagged, and is not a fix.

---

## Question 5 — One CronJob, three spec levels ★

A CronJob nests three objects, and almost every field belongs to exactly one of them:

| level | path | fields |
|---|---|---|
| the **CronJob** | `.spec` | `schedule`, `timeZone`, `concurrencyPolicy`, `startingDeadlineSeconds`, `successfulJobsHistoryLimit`, `failedJobsHistoryLimit`, `suspend` |
| the **Job** it creates | `.spec.jobTemplate.spec` | `activeDeadlineSeconds`, `backoffLimit`, `ttlSecondsAfterFinished`, `completions`, `parallelism` |
| the **Pod** the Job creates | `.spec.jobTemplate.spec.template.spec` | `restartPolicy`, `containers`, `volumes`, `nodeSelector` |

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: trace-compactor
  namespace: wl-digest
spec:
  schedule: "*/20 * * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 30
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 2
  suspend: false
  jobTemplate:
    spec:
      activeDeadlineSeconds: 60
      backoffLimit: 2
      ttlSecondsAfterFinished: 120
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: compactor
            image: busybox:1.36
            command: ["sh", "-c", "echo compacting traces && sleep 5"]
```

Getting a level wrong fails in one of two ways, and the quiet one is the dangerous one.

**Loud.** `activeDeadlineSeconds` is not a field of a CronJob spec, so putting it there
is rejected outright:

```
error: error validating data: ValidationError(CronJob.spec):
  unknown field "activeDeadlineSeconds" in io.k8s.api.batch.v1.CronJobSpec
```

**Silent.** `activeDeadlineSeconds` *is* a field of a **PodSpec**, so putting it on the
Pod template is accepted with no complaint — and even appears to work, because the
kubelet will kill the Pod after that long. But it bounds the Pod, not the Job: the Job
keeps going and starts a replacement. Nothing tells you. This is the one a mock exam
marked wrong, and the only defence is knowing which object owns the field.

The same asymmetry applies to `backoffLimit` and `ttlSecondsAfterFinished` — Job fields,
with no equivalent on a Pod, so those two fail loudly wherever else you put them.

Two defaults worth knowing, because a field you never set can read back as the right
answer: `successfulJobsHistoryLimit` defaults to **3** and `failedJobsHistoryLimit` to
**1**.

Verify the levels rather than the whole object:

```bash
kubectl get cronjob trace-compactor -n wl-digest \
  -o jsonpath='{.spec.startingDeadlineSeconds}{"\n"}{.spec.jobTemplate.spec.activeDeadlineSeconds}{"\n"}{.spec.jobTemplate.spec.template.spec.restartPolicy}{"\n"}'
# 30
# 60
# OnFailure
```

---

## Question 6 — Runs that overlap and never finish

**Investigate first.**

```bash
kubectl get cronjob,jobs,pods -n wl-rotate
# several jobs, each 0/1 COMPLETIONS, each with a Running Pod
kubectl get cronjob digest-trim -n wl-rotate -o yaml | grep -E 'schedule|concurrencyPolicy|activeDeadline|sleep'
```

**The fault.** Two of them, one at each of two levels. The schedule fires every minute
while the work takes 150 seconds, and `concurrencyPolicy` is `Allow` — the default — so
the CronJob happily starts a run on top of the last one. And no `activeDeadlineSeconds`
anywhere means no run is ever given up on, so they accumulate.

**The fix.** One field on the CronJob spec, one on the Job template spec:

```bash
kubectl patch cronjob digest-trim -n wl-rotate --type=merge -p \
  '{"spec":{"concurrencyPolicy":"Forbid","jobTemplate":{"spec":{"activeDeadlineSeconds":45}}}}'
```

Then clear what has already stacked up, because nothing does that for you — the new
settings only apply to runs created from now on:

```bash
kubectl delete job --all -n wl-rotate
kubectl get jobs -n wl-rotate -w
```

`concurrencyPolicy` has three values and only one of them is right here:

- `Allow` (default) — start the new run anyway. This is the fault.
- `Forbid` — skip the new run while one is active. This is the answer.
- `Replace` — kill the run in progress and start the new one. It also ends the overlap,
  but by abandoning work the question never said to abandon.

Shortening the `sleep` would also stop the pile-up, and it changes what the job does —
which the question rules out. Bound the run; do not redefine the work.

---

## Question 7 — A Service with no endpoints

**Investigate first.**

```bash
kubectl get pods -n svc-catalog --show-labels
kubectl get endpointslice -n svc-catalog -l kubernetes.io/service-name=station-catalog-svc
# no endpoints at all
kubectl get service station-catalog-svc -n svc-catalog -o yaml
kubectl describe service station-catalog-svc -n svc-catalog | grep -i endpoints
```

**The fault.** Two faults, and both read as plausible YAML.

```yaml
  selector:
    component: station-catalog      # these are the DEPLOYMENT's labels...
    managed-by: data-team           # ...not its Pods'
  ports:
  - port: 80
    targetPort: metrics             # no container declares a port called metrics
```

A Service selects **Pods**, by matching its selector against the Pods' own labels. The
labels on the Deployment object are metadata about the Deployment and are not copied to
the Pods — the Pods carry whatever `.spec.template.metadata.labels` says, here
`app=station-catalog,tier=api`. A selector naming the wrong set matches nothing, and
there is nothing in the Service's own YAML to suggest it.

The second fault survives fixing the first: a **named** `targetPort` has to match a
`name` under the container's `ports`. This container declares `web`, so `metrics`
resolves to nothing and the Service forwards nowhere.

**The fix.**

```bash
kubectl patch service station-catalog-svc -n svc-catalog --type=merge -p \
  '{"spec":{"selector":{"component":null,"managed-by":null,"app":"station-catalog","tier":"api"},"ports":[{"protocol":"TCP","port":80,"targetPort":80}]}}'
```

Note the two `null`s. A merge patch **merges** maps, so without them the selector would
end up with all four labels and still match nothing — a confusing thing to debug on top
of the original problem. `kubectl edit service station-catalog-svc -n svc-catalog` avoids
the trap entirely. `targetPort: web` is equally correct, since the container does declare
that name.

```bash
kubectl get endpointslice -n svc-catalog -l kubernetes.io/service-name=station-catalog-svc \
  -o jsonpath='{range .items[*]}{.endpoints[*].addresses[0]}{" "}{.ports[*].port}{"\n"}{end}'

IP=$(kubectl get svc station-catalog-svc -n svc-catalog -o jsonpath='{.spec.clusterIP}')
kubectl exec catalog-probe -n svc-catalog -- timeout 4 bash -c "echo > /dev/tcp/$IP/80" && echo OK
```

Relabelling the Deployment's Pods would also produce endpoints, and is the one thing the
question forbids: the workload belongs to another team. The repair is entirely on the
Service.

---

## Question 8 — The per-Pod record of a headless Service

A **headless** Service (`clusterIP: None`) publishes no address of its own. Instead
cluster DNS publishes one A record per ready Pod behind it, and — when the Service is
named as a StatefulSet's `serviceName` — one stable per-Pod name:

```
<pod-name>.<service>.<namespace>.svc.cluster.local
```

That is what makes `station-index-0` addressable individually, which is the whole point
of a StatefulSet.

```bash
mkdir -p /tmp/exam/q8
kubectl exec dns-tool -n dns-station -- \
  nslookup station-index-0.station-index.dns-station.svc.cluster.local. \
  > /tmp/exam/q8/lookup.txt

cat /tmp/exam/q8/lookup.txt
# Server:    10.96.0.10
# Address:   10.96.0.10:53
#
# Name:      station-index-0.station-index.dns-station.svc.cluster.local
# Address 1: 192.168.1.23 station-index-0.station-index.dns-station.svc.cluster.local
```

Four things in that one command:

- **The trailing dot makes the name absolute.** A Pod's `/etc/resolv.conf` carries
  `ndots: 5`, and this name has fewer dots than that, so a glibc resolver would walk the
  `search` list first. busybox's `nslookup` is the opposite — it ignores the search list
  entirely, which is why `nslookup kubernetes.default` answers `NXDOMAIN` from a busybox
  Pod even when DNS is perfectly healthy. Give DNS questions the FQDN, with the dot, and
  neither behaviour can bite you.
- **The redirect stays on the jumphost.** `kubectl exec ... > file` writes the file here;
  `kubectl exec ... -- sh -c "... > file"` writes it inside the container, where nothing
  will find it.
- **Keep the whole output.** The `Server:` line is what shows the lookup was answered by
  cluster DNS rather than by a resolver on the jumphost.
- **The address is a Pod IP, not a Service IP.** If you see one address for a name like
  this and it is the Service's cluster IP, the Service is not headless.

`kubectl exec dns-tool -n dns-station -- nslookup station-index.dns-station.svc.cluster.local.`
returns *both* Pod IPs — the Service's own record for a headless Service is the set of
its endpoints.

---

## Question 9 — An init container and two regular containers

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: waveform-writer
  namespace: wl-waveform
spec:
  initContainers:
  - name: seed-ledger
    image: busybox:1.36
    command: ["sh", "-c", "echo '=== waveform ledger opened ===' > /srv/waveforms/ledger.log"]
    volumeMounts:
    - name: ledger
      mountPath: /srv/waveforms
  containers:
  - name: waveform-app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date) waveform written\" >> /srv/waveforms/ledger.log; sleep 5; done"]
    volumeMounts:
    - name: ledger
      mountPath: /srv/waveforms
  - name: ledger-tail
    image: busybox:1.36
    command: ["sh", "-c", "tail -f /srv/waveforms/ledger.log"]
    volumeMounts:
    - name: ledger
      mountPath: /srv/waveforms
  volumes:
  - name: ledger
    emptyDir: {}
```

```bash
kubectl get pod waveform-writer -n wl-waveform
# NAME              READY   STATUS    RESTARTS   AGE
# waveform-writer   2/2     Running   0          20s
kubectl logs waveform-writer -c ledger-tail -n wl-waveform
# === waveform ledger opened ===
# Mon ... waveform written
```

The two things this question counts:

- **Three containers mount the volume, the init container included.** An init container
  gets its own filesystem like any other, so if `seed-ledger` does not mount `ledger`,
  the header goes into a layer that is thrown away the moment it exits — and
  `ledger-tail` then tails a file created by `waveform-app` instead, with no header. The
  Pod comes up perfectly and the evidence is only in the logs. The shared `emptyDir` is
  what outlives the init container: it is created with the Pod and deleted with it, which
  is exactly the lifetime wanted here.
- **`seed-ledger` has to finish.** Init containers run one at a time, in order, each to
  completion, before any regular container starts. Give one `restartPolicy: Always` and
  it becomes a native sidecar instead (question 10) — it never terminates, and it is no
  longer waited for in the same way.

```bash
kubectl get pod waveform-writer -n wl-waveform \
  -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}{"\n"}'
# Completed
```

---

## Question 10 — A native sidecar

Since Kubernetes 1.29 (GA in 1.33) an `initContainers` entry may carry
`restartPolicy: Always`. That one field changes everything about it: it starts in init
order, the Pod does **not** wait for it to finish, it keeps running alongside the
application, and it is restarted if it dies. That is a **native sidecar**.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: trace-shipper
  namespace: wl-shipper
spec:
  initContainers:
  - name: prepare-spool
    image: busybox:1.36
    command: ["sh", "-c", "touch /var/spool/traces/trace.log"]
    volumeMounts:
    - name: spool
      mountPath: /var/spool/traces
  - name: log-forwarder
    image: busybox:1.36
    restartPolicy: Always            # <- this is the whole difference
    command: ["sh", "-c", "tail -f /var/spool/traces/trace.log"]
    volumeMounts:
    - name: spool
      mountPath: /var/spool/traces
  containers:
  - name: trace-app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date) trace emitted\" >> /var/spool/traces/trace.log; sleep 5; done"]
    volumeMounts:
    - name: spool
      mountPath: /var/spool/traces
  volumes:
  - name: spool
    emptyDir: {}
```

The ordering is the reason `prepare-spool` is a plain init container and
`log-forwarder` is not: `tail -f` on a file that does not exist yet would fail, so the
spool is created by something that finishes first, and only then does the sidecar start.
A native sidecar still respects init ordering — which a second regular container could
not.

```bash
kubectl get pod trace-shipper -n wl-shipper
# NAME            READY   STATUS    RESTARTS   AGE
# trace-shipper   2/2     Running   0          15s
```

**`2/2`, and that is the trap.** The `READY` column counts restartable init containers
along with the regular ones, so this Pod — one application container plus one sidecar —
reads exactly the same as question 9's Pod, which has two regular containers and no
sidecar. The column cannot tell the two shapes apart. Nor can readiness: a plain init
container that exited successfully also reports `ready: true`.

What does tell them apart is where the containers are declared, and what state they are
in:

```bash
kubectl get pod trace-shipper -n wl-shipper \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}{" "}{end}{"\n"}'
# trace-app                                   <- one regular container

kubectl get pod trace-shipper -n wl-shipper -o json \
  | jq -r '.status.initContainerStatuses[] | "\(.name) \(.state | keys[0])"'
# prepare-spool terminated                    <- ran once and finished
# log-forwarder running                        <- still up, alongside the app

kubectl logs trace-shipper -c log-forwarder -n wl-shipper
```

This is the distinction a mock exam marked wrong: asked for "two regular containers", a
Pod built with the collector as a native sidecar has **one**. Count `spec.containers`,
not processes — and not the `READY` column, which counts both kinds.

---

## Question 11 — Pending, and no node carries the label

**Investigate first.**

```bash
kubectl describe pod epicenter-plot -n sched-epicenter | grep -A6 Events
# Warning  FailedScheduling  ...  0/4 nodes are available:
#   4 node(s) didn't match Pod's node affinity/selector.
kubectl get pod epicenter-plot -n sched-epicenter -o jsonpath='{.spec.nodeSelector}{"\n"}'
# {"seismo.io/duty":"plotting"}
kubectl get nodes -L seismo.io/duty
# no node carries it
```

**The fault.** The Pod requires a node label that no node has. `nodeSelector` is a hard
requirement — there is no scoring and no fallback, so the Pod waits indefinitely.

**The fix.** The Pod must not be touched, so the label goes on the node:

```bash
NODE02=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}')
kubectl label node "$NODE02" seismo.io/duty=plotting

kubectl get pod epicenter-plot -n sched-epicenter -o wide    # Running on node02
```

Resolve node names through the `ck-x.io/alias` label rather than typing
`cluster-worker2`: kind names its nodes `cluster-control-plane`, `cluster-worker`,
`cluster-worker2`, `cluster-worker3`, and this lab labels each with the name the
questions use.

Two habits this question is drilling:

- **The scheduler keeps trying.** A `Pending` Pod is not stuck forever — it is re-queued
  whenever the cluster changes, so labelling the node is enough and there is nothing to
  restart.
- **Do not delete and recreate.** It is the reflex, and here it would be a wrong answer:
  this Pod has no controller, so a delete is permanent if you then get the manifest
  wrong, and the question grades the Pod's identity (`metadata.uid`). The same is true on
  the real exam of anything you did not create yourself.

---

## Question 12 — Pending, and the node refuses it

**Investigate first.**

```bash
kubectl describe pod borehole-sampler -n sched-borehole | grep -A6 Events
# Warning  FailedScheduling  ...  1 node(s) had untolerated taint
#   {seismo.io/borehole: restricted}, 3 node(s) didn't match Pod's node affinity/selector.
NODE03=$(kubectl get nodes -l ck-x.io/alias=node03 -o jsonpath='{.items[0].metadata.name}')
kubectl describe node "$NODE03" | grep -i taints
# Taints:  seismo.io/borehole=restricted:NoSchedule
```

**The fault.** The Pod is pinned to node03, and node03 carries a `NoSchedule` taint it
does not tolerate. A taint is the node saying "not unless you say you can take it".

**The fix.** The node belongs to someone else, so the Pod has to tolerate the taint —
and a toleration can be **added to a Pod that already exists**:

```bash
kubectl patch pod borehole-sampler -n sched-borehole --type=json -p \
  '[{"op":"add","path":"/spec/tolerations/-","value":{"key":"seismo.io/borehole","operator":"Equal","value":"restricted","effect":"NoSchedule"}}]'

kubectl get pod borehole-sampler -n sched-borehole -o wide    # Running on node03
```

`kubectl edit pod borehole-sampler -n sched-borehole` works just as well. Almost nothing
in a running Pod's spec can be changed, but `tolerations` is one of the exceptions —
**additions** are allowed (alongside container images,
`activeDeadlineSeconds` and `terminationGracePeriodSeconds`). Removing or editing one is
still rejected, which is why the patch above is a JSON patch appending to the list: a
`--type=merge` patch would **replace** the whole array, dropping the two `NoExecute`
tolerations that every Pod is given automatically, and the API server would refuse it.

Those two automatic tolerations are worth recognising:

```bash
kubectl get pod borehole-sampler -n sched-borehole -o jsonpath='{range .spec.tolerations[*]}{.key}{" "}{.effect}{"\n"}{end}'
# node.kubernetes.io/not-ready    NoExecute
# node.kubernetes.io/unreachable  NoExecute
# seismo.io/borehole              NoSchedule
```

The first two are added by the `DefaultTolerationSeconds` admission plugin and tolerate
nothing relevant here — so "the Pod has tolerations" is true even of the broken Pod.

Two wrong answers:

- **Removing the taint** (`kubectl taint node ... seismo.io/borehole-`) does get the Pod
  running, and undoes a decision the platform team made for every workload on that node.
- **`operator: Exists` with no key** tolerates *every* taint in the cluster, including
  ones that exist to keep workloads off unhealthy nodes. Match the key and the value.

---

## Question 13 — Two files from the cluster

```bash
mkdir -p /tmp/exam/q13

kubectl get nodes \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
  | awk -F'\t' '$2=="True" {print $1}' > /tmp/exam/q13/ready-nodes.txt

kubectl get namespaces --no-headers | wc -l > /tmp/exam/q13/ns-count.txt
```

The filter expression `?(@.type=="Ready")` is the piece worth practising: `.status.conditions`
is a list, and that selects the one entry you want out of it rather than guessing an
index, since the order is not guaranteed.

`kubectl get nodes --no-headers | awk '$2=="Ready" {print $1}'` is just as acceptable —
only the contents of the file are graded. Two traps either way:

- **`--no-headers`.** Without it the first line of the file is `NAME`, and `wc -l` counts
  one namespace too many. That extra line is the single most common way one of these
  files comes back wrong.
- **A node can be `Ready,SchedulingDisabled`**, which is still `Ready` — the `Ready`
  condition and the `unschedulable` flag are different things.

Write the count file last and leave the namespaces alone afterwards: the file is a
statement about the cluster, and it is checked against the cluster as it stands at the
end.
