# CKA Practice Lab 009 — Answers

Everything here is run from the exam jumphost, where `KUBECONFIG` is already
exported. There is no standalone `kustomize` binary — `kubectl kustomize` and
`kubectl apply -k` are the tools.

The lab has two halves. Questions 1–5 are Kustomize, ending in a broken overlay;
questions 6–11 are placement, ending in a workload that will not schedule;
question 12 joins them. Questions 5 and 11 start from something already broken,
so their answers open with the diagnosis rather than the fix.

**The node topology this lab reasons about** is applied by the shared setup
script, because k3d creates none of it:

```bash
kubectl get nodes -L node-class,decommission -L topology.kubernetes.io/zone
```

| node | zone | `node-class` | other |
| --- | --- | --- | --- |
| `k3d-cluster-server-0` | `edge-1` | `general` | |
| `k3d-cluster-agent-0` | `edge-1` | `compute` | |
| `k3d-cluster-agent-1` | `edge-2` | `memory` | `decommission=pending` |

Two facts follow from that table, and most of the scheduling half depends on
them. All three nodes are schedulable — k3s runs workloads on the server node —
so this is a three-node cluster for placement purposes. And the two zones are
**not** the same size, which is what stops a zone spread and a hostname spread
being the same answer.

**Two habits worth keeping:**

```bash
kubectl kustomize <dir>                 # always read the output before applying it
kubectl get pods -o wide                # placement questions are answered by this column
```

**Four traps this lab is built around:**

- A strategic merge patch keys container lists by `name`. Get the name wrong and
  you **add** a container rather than editing one — silently.
- `podAffinity` and `podAntiAffinity` look only in the Pod's **own** namespace
  unless you say otherwise.
- Separate `nodeSelectorTerms` are OR-ed; `matchExpressions` inside one term are
  AND-ed. The difference is the whole of question 6.
- A `labelSelector` that matches nothing is satisfied everywhere, so a spread or
  anti-affinity rule with a wrong selector spreads nothing at all.

---

## Question 1: a first overlay

```bash
mkdir -p /tmp/exam/q1/overlays/dev
cat > /tmp/exam/q1/overlays/dev/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-intro
nameSuffix: -dev
commonAnnotations:
  owner: platform-team
resources:
- ../../base
EOF

kubectl kustomize /tmp/exam/q1/overlays/dev
kubectl apply -k /tmp/exam/q1/overlays/dev
```

Three transformers and a `resources` list. `namespace` and `nameSuffix` rewrite
where the objects go and what they are called; `commonAnnotations` reaches
**every** resource the overlay builds, which is why the base ships a Service as
well as a Deployment. Annotating the Deployment by hand gets you one of the two.

Verify with:

```bash
kubectl get deploy,svc -n kustom-intro                                        # both named parcel-index-dev
kubectl get svc parcel-index-dev -n kustom-intro -o jsonpath='{.metadata.annotations.owner}'
```

**Common traps**

- `nameSuffix` appends to the name only. The Service's `selector` still matches
  the Pods, because Kustomize does not rename labels — and should not.
- `commonLabels` is the deprecated sibling of the `labels` transformer and
  rewrites `spec.selector`, which is immutable on an existing Deployment.
  `commonAnnotations` has no such problem: annotations are not selectors.

---

## Question 2: generators, and when the hash has to go

```bash
mkdir -p /tmp/exam/q2/overlays/prod
cat > /tmp/exam/q2/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-gen
resources:
- ../../base
configMapGenerator:
- name: app-settings
  literals:
  - DEPOT_REGION=north
  - MAX_PARCELS=5000
secretGenerator:
- name: depot-ca
  files:
  - ca.crt=depot-ca.pem
generatorOptions:
  disableNameSuffixHash: true
EOF

kubectl apply -k /tmp/exam/q2/overlays/prod
```

`generatorOptions` applies to every generator in the kustomization, so one block
covers both objects.

The reason to disable the hash is worth being precise about, because the obvious
explanation is wrong. Kustomize rewrites `configMapRef`/`secretRef` names to the
hashed name automatically, so a hash does **not** break a reference inside the
same kustomization. What it breaks is anything *outside* it — the reporting tool
in the question — which looks the object up by a name that changes on every
content edit.

`files: - ca.crt=depot-ca.pem` sets the key on the left and reads the file on the
right. Without the `ca.crt=` prefix the key would be the filename, `depot-ca.pem`.

Verify with:

```bash
kubectl get cm,secret -n kustom-gen                                    # no -abc123 suffixes
kubectl get secret depot-ca -n kustom-gen -o jsonpath='{.data.ca\.crt}' | base64 -d
diff <(kubectl get secret depot-ca -n kustom-gen -o jsonpath='{.data.ca\.crt}' | base64 -d) \
     /tmp/exam/q2/overlays/prod/depot-ca.pem && echo identical
```

**Common traps**

- Losing the hash means losing the free rolling restart: with hashing on, editing
  the content renames the object and the Deployment rolls. With it off, you have
  to restart the workload yourself after a change.
- `literals` values are not quoted YAML — `MAX_PARCELS=5000` produces the string
  `"5000"`, which is what a ConfigMap always holds.

---

## Question 3: one patch, many targets

```bash
mkdir -p /tmp/exam/q3/overlays/prod

cat > /tmp/exam/q3/overlays/prod/shift-window-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: placeholder
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: SHIFT_WINDOW
          value: night
EOF

cat > /tmp/exam/q3/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-patch
resources:
- ../../base
patches:
- path: shift-window-patch.yaml
  target:
    kind: Deployment
    labelSelector: tier=backend
EOF

kubectl apply -k /tmp/exam/q3/overlays/prod
```

The `target` block is what makes one patch file apply to a *set* of resources.
Without it, Kustomize matches the patch by the group/kind/name in the patch's own
`metadata`, which is one resource at a time.

Because the target does the matching, `metadata.name` in the patch file is inert
— `placeholder` is a perfectly good value, and naming a real Deployment there
would only be misleading. The container is still matched by name, so `app` has to
be right.

Verify with:

```bash
for d in route-planner dispatch-worker driver-portal; do
  echo -n "$d: "
  kubectl get deploy $d -n kustom-patch -o jsonpath='{.spec.template.spec.containers[0].env}'; echo
done
```

The first two show `SHIFT_WINDOW`, the third shows nothing.

**Common traps**

- `labelSelector` reads the resource's **own** `metadata.labels`, not the Pod
  template's. The base sets `tier` in both places; only the outer one is matched.
- A `target` with no `kind` matches every kind, which here would try to patch a
  Deployment shape onto anything else the base produced.

---

## Question 4: composing two bases

```bash
mkdir -p /tmp/exam/q4/overlays/prod
cat > /tmp/exam/q4/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-compose
resources:
- ../../bases/app
- ../../bases/cache
labels:
- pairs:
    release: winter-2026
  includeSelectors: false
replicas:
- name: waybill-cache
  count: 2
EOF

kubectl apply -k /tmp/exam/q4/overlays/prod
```

`resources` takes directories as happily as files, and each one is built as its
own kustomization before the transformers run over the combined output. That is
what lets a single `labels` entry reach resources that came from two different
directories.

`includeSelectors: false` is the important half. The default `labels` behaviour
leaves `spec.selector` alone, and that is what you want: a Deployment's selector
is immutable after creation, so a transformer that rewrote it would make every
later apply fail. Use `labels` rather than the deprecated `commonLabels`, which
does rewrite selectors.

The `replicas` transformer names one resource, which is how the size change stays
scoped to the cache.

Verify with:

```bash
kubectl get deploy,svc -n kustom-compose --show-labels
kubectl get deploy -n kustom-compose -o custom-columns='NAME:.metadata.name,REPLICAS:.spec.replicas'
```

**Common traps**

- Relative paths are resolved from the kustomization file's own directory.
  `../../bases/app` from `overlays/prod` lands on `/tmp/exam/q4/bases/app`;
  `../bases/app` would look for `/tmp/exam/q4/overlays/bases/app`.
- If both bases produced a resource of the same kind and name, Kustomize would
  refuse to build rather than silently pick one.

---

## Question 5: a broken overlay

Start by reading the error, not the files:

```bash
kubectl kustomize /tmp/exam/q5/overlays/staging
```

```
Error: merging from generator &{0xc000... }: id resid.ResId{...Name:"checker-settings"...}
does not exist; cannot merge or replace
```

**Fault one.** The `configMapGenerator` says `behavior: merge`, which means
"take the ConfigMap of this name that some base already declares, and merge these
values into it". No base declares one, so there is nothing to merge into. This
overlay is the only place the ConfigMap exists, so it should simply generate it —
drop the `behavior` line.

```bash
cat > /tmp/exam/q5/overlays/staging/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-repair
resources:
- ../../base
configMapGenerator:
- name: checker-settings
  literals:
  - MODE=strict
patches:
- path: container-patch.yaml
- path: replica-patch.yaml
EOF
```

It builds now — and the output is still wrong:

```bash
kubectl kustomize /tmp/exam/q5/overlays/staging | grep -A2 'containers:'
```

```
      containers:
      - image: nginx:1.27.4
        name: check
      - image: nginx:1.25
        name: checker
        ports:
        - containerPort: 80
```

**Fault two.** A strategic merge patch merges lists of containers using `name` as
the key. The base's container is `checker`; the patch says `check`. Rather than
failing, Kustomize concluded the patch describes a container that does not exist
yet and **added** it — first in the list, which makes it easy to skim past the
unchanged `checker` below it. The Deployment now has two containers, the original one
still on the old image — and once applied, both would try to bind port 80, so the
Pods would never become ready.

```bash
cat > /tmp/exam/q5/overlays/staging/container-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: customs-check
spec:
  template:
    spec:
      containers:
      - name: checker
        image: nginx:1.27.4
EOF

kubectl apply -k /tmp/exam/q5/overlays/staging
```

Verify with:

```bash
kubectl get deploy customs-check -n kustom-repair \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}={.image}{"\n"}{end}'
kubectl get deploy customs-check -n kustom-repair          # 4/4
kubectl get cm -n kustom-repair                            # checker-settings-<hash>
```

**Common traps**

- Deleting `container-patch.yaml` makes the build succeed and the image wrong. The
  question requires both files to stay in use for exactly that reason.
- `behavior: replace` would have failed the same way. `merge` and `replace` both
  need an existing object; only the default (create) does not.
- The ConfigMap gets a hash suffix here, and should: nothing outside this
  kustomization reads it, so the free rolling restart is worth having.

---

## Question 6: node affinity that needs two expressions

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sorting-engine
  namespace: sched-nodeaff
  labels:
    app: sorting-engine
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sorting-engine
  template:
    metadata:
      labels:
        app: sorting-engine
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-class
                operator: In
                values:
                - compute
                - memory
              - key: decommission
                operator: DoesNotExist
      containers:
      - name: engine
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF
```

The two expressions live in **one** term because entries of `matchExpressions`
are AND-ed, while entries of `nodeSelectorTerms` are OR-ed. Split them into two
terms and the rule reads "the right class, *or* not decommissioning", which
matches nearly every node in the cluster.

`DoesNotExist` takes no `values` — it tests for the presence of the key alone,
which is what "whatever that label's value" in the question asks for.
`NotIn: [pending]` would also pass the validation, though it is a narrower promise.

Only `k3d-cluster-agent-0` satisfies both halves: the server node is `general`,
and `agent-1` is `memory` but carries the decommission flag.

Verify with:

```bash
kubectl get pods -n sched-nodeaff -o wide        # both on k3d-cluster-agent-0
```

**Common traps**

- A `nodeSelector` cannot express this at all. It is a flat map of equality
  matches, with no operators and no negation.
- If the rule matched no node, the Pods would sit `Pending` with
  `didn't match Pod's node affinity/selector` in their events — the symptom that
  question 11 is built from.

---

## Question 7: preferences, not requirements

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tracking-api
  namespace: sched-prefer
  labels:
    app: tracking-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: tracking-api
  template:
    metadata:
      labels:
        app: tracking-api
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 70
            preference:
              matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                - edge-1
          - weight: 30
            preference:
              matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                - edge-2
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF
```

Each preferred entry is a `weight` (1–100) and a `preference`. Note the field
name changes: a required term holds `matchExpressions` directly, a preferred one
wraps them in `preference`. Weights are added to the score of every node that
matches, and the highest-scoring feasible node wins. They are not percentages and
do not need to total anything.

Because both zones are listed, every node scores something, and the workload can
always be placed — which is the point of the question. Adding a
`requiredDuringSchedulingIgnoredDuringExecution` block alongside would turn the
preference back into a restriction.

Verify with:

```bash
kubectl get pods -n sched-prefer -o wide
kubectl get deploy tracking-api -n sched-prefer \
  -o jsonpath='{.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution}'  # empty
```

Where the Pods actually landed is not graded, and should not be: a preference is
a hint the scheduler is free to overrule.

---

## Question 8: staying off someone else's node

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: label-printer
  namespace: sched-antiaff
  labels:
    app: label-printer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: label-printer
  template:
    metadata:
      labels:
        app: label-printer
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: scan-gateway
            topologyKey: kubernetes.io/hostname
      containers:
      - name: printer
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF
```

The selector names **`scan-gateway`**, not `label-printer`. This is the
distinction the question is built on: the usual textbook anti-affinity is a
workload spreading itself, and that is not what was asked. A self-selecting rule
would scatter the two printer replicas across different nodes and leave both free
to land on the gateway's node — satisfying the rule as written while breaking the
actual requirement.

Read it as: *this Pod may not be placed in any topology domain that already holds
a Pod matching this selector.* With `topologyKey: kubernetes.io/hostname`, a
domain is a node.

Verify with:

```bash
kubectl get pods -n sched-antiaff -o wide
```

`scan-gateway` is on `k3d-cluster-agent-1`; neither printer replica is.

**Common traps**

- With `preferred` instead of `required` the scheduler may place a replica on the
  gateway's node anyway when the others look busier.
- Pod anti-affinity is evaluated at scheduling time. A Pod already running is not
  evicted when a matching Pod appears next to it later — that is what
  `IgnoredDuringExecution` means.

---

## Question 9: co-location across a namespace boundary

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: depot-agent
  namespace: sched-podaff
  labels:
    app: depot-agent
spec:
  replicas: 2
  selector:
    matchLabels:
      app: depot-agent
  template:
    metadata:
      labels:
        app: depot-agent
    spec:
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: depot-telemetry
            namespaces:
            - sched-podaff-infra
            topologyKey: kubernetes.io/hostname
      containers:
      - name: agent
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF
```

`namespaces` is the load-bearing line. Pod affinity and anti-affinity are scoped
to the **Pod's own namespace** unless the term says otherwise, so the same rule
without it looks for `app=depot-telemetry` inside `sched-podaff`, finds nothing,
and can never be satisfied. The replicas sit `Pending` indefinitely — with no
error anywhere, because an unsatisfiable affinity is not a malformed one.

`namespaceSelector` is the other way to write it, matching namespaces by label
instead of naming them. `namespaceSelector: {}` means *all* namespaces, which
would work here but promises far more than intended.

If the Pods are stuck, this is the line that tells you why:

```bash
kubectl describe pod -n sched-podaff -l app=depot-agent | grep -A5 Events
```

Verify with:

```bash
kubectl get pods -n sched-podaff-infra -o wide      # depot-telemetry on k3d-cluster-agent-0
kubectl get pods -n sched-podaff -o wide            # both agents on the same node
```

---

## Question 10: two constraints, one hard and one soft

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: parcel-tracker
  namespace: sched-spread
  labels:
    app: parcel-tracker
spec:
  replicas: 4
  selector:
    matchLabels:
      app: parcel-tracker
  template:
    metadata:
      labels:
        app: parcel-tracker
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: parcel-tracker
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: parcel-tracker
      containers:
      - name: tracker
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF
```

`topologySpreadConstraints` sits directly on the Pod spec, not under `affinity`.
Both constraints must be satisfied, and each is evaluated independently.

The zone constraint is the hard one. `maxSkew: 1` caps the difference between the
most and least populated zone, so with 4 replicas across two zones the only
admissible split is 2/2 — a 3/1 split has a skew of 2 and `DoNotSchedule` refuses
it. That the zones hold 2 nodes and 1 node respectively does not matter: a
constraint counts Pods per *domain*, so two replicas sharing the single node in
`edge-2` is a perfectly good answer.

The hostname constraint is the soft one. `ScheduleAnyway` makes it a scoring
preference, so the scheduler evens things out across the three nodes where it can
and never blocks a Pod for it.

`labelSelector` decides which Pods are counted when measuring the skew. Left out,
it selects nothing, the measured skew is always zero, and the constraint quietly
does nothing at all.

Verify with:

```bash
kubectl get nodes -L topology.kubernetes.io/zone      # which node is in which zone
kubectl get pods -n sched-spread -o wide              # then count: 2 in edge-1, 2 in edge-2
```

**Common traps**

- `maxSkew` must be at least 1; `0` is rejected by the API server.
- With `DoNotSchedule` and too few domains, surplus replicas stay `Pending`
  forever rather than being placed unevenly.

---

## Question 11: pods that will not schedule

Diagnose before changing anything:

```bash
kubectl get pods -n ts-sched
kubectl describe pod -n ts-sched -l app=customs-broker | grep -A5 Events
```

```
Warning  FailedScheduling  0/3 nodes are available: 3 node(s) didn't match
Pod's node affinity/selector.
```

Every node was rejected by the Pod's own placement rule, so read that rule:

```bash
kubectl get deploy customs-broker -n ts-sched \
  -o jsonpath='{.spec.template.spec.affinity.nodeAffinity}' | jq
kubectl get nodes -L node-class
```

**The fault:** the Deployment requires `node-class=archive`, and no node in the
cluster carries that class. The classes actually present are `general`, `compute`
and `memory`, and the two approved for this application are `compute` and
`memory`.

```bash
kubectl -n ts-sched patch deployment customs-broker --type='json' -p='[
  {"op": "replace",
   "path": "/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/0/values",
   "value": ["compute", "memory"]}
]'
```

`kubectl edit deploy customs-broker -n ts-sched` does the same job by hand.

Verify with:

```bash
kubectl get pods -n ts-sched -o wide      # 3 Running
```

**Common traps**

- Labelling a node `node-class=archive` also makes the symptom go away, and is
  what the question forbids: the node inventory belongs to another team and would
  then describe hardware that does not exist. A verification step checks the node
  labels are untouched.
- Deleting the affinity block entirely, or swapping it for a `nodeSelector`, also
  gets the Pods running. Both are checked against, because neither preserves the
  constraint the workload actually has.

---

## Question 12: placement policy delivered by Kustomize

```bash
mkdir -p /tmp/exam/q12/overlays/prod

cat > /tmp/exam/q12/overlays/prod/placement-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: freight-api
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: freight-api
            topologyKey: kubernetes.io/hostname
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: freight-api
EOF

cat > /tmp/exam/q12/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-sched
resources:
- ../../base
replicas:
- name: freight-api
  count: 3
patches:
- path: placement-patch.yaml
EOF

kubectl kustomize /tmp/exam/q12/overlays/prod
kubectl apply -k /tmp/exam/q12/overlays/prod
```

This is the shape most real repositories end up with: the application team owns a
base that says nothing about placement, and the platform team adds the scheduling
policy in an overlay. The base here is immutable and checked, so the rules can
only arrive by patch.

The anti-affinity is self-selecting this time — `app=freight-api` matching the
workload's own Pods — which is the ordinary "one replica per node" rule, and the
only place in this lab it appears. With three replicas and three schedulable
nodes it resolves to exactly one Pod each.

The spread constraint is deliberately `ScheduleAnyway`. Two hard placement rules
on a three-node cluster leave no slack at all: the anti-affinity already pins the
layout, and a second hard constraint could only ever refuse it.

`replicas` and `patches` could both have been one patch. Keeping the count in the
transformer is easier to read and easier to change.

Verify with:

```bash
kubectl get pods -n kustom-sched -o wide          # 3 Pods, 3 different nodes
kubectl get deploy freight-api -n kustom-sched -o jsonpath='{.spec.replicas}'
( cd /tmp/exam/q12 && sha256sum -c base.sha256 )  # base untouched
```

**Common traps**

- A strategic merge patch adding `affinity` merges into the Pod spec, so the
  container list is left alone — you do not need to restate it.
- Applying a hand-written Deployment straight from the shell satisfies the live
  cluster but not the question: the rules have to be in the overlay, and that is
  checked.
