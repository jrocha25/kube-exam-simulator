# CKA Practice Lab 007 — Answers

Every solution below is written for the exam jumphost (`ckad9999`), where `kubectl` already points at the exam cluster.

This lab is entirely about authorization. Ten questions in one hour, so the work per question is small — the difficulty is in knowing which knob RBAC actually exposes.

Three of the ten questions (8, 9 and 10) start from a cluster that is already wrong. Each of those answers opens with the commands that find the fault before it shows the fix — on the real exam nobody tells you what is broken, and the diagnosis is most of the work.

Two habits are worth building before you start:

```bash
# Ask the API server what an identity may do, instead of reading YAML and guessing.
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<name> -n <namespace>
kubectl auth can-i --list --as=system:serviceaccount:<namespace>:<name> -n <namespace>
```

Two traps that catch people all lab long:

- **A subresource is not a resource path.** `kubectl auth can-i get pods/log` is parsed as *the Pod named `log`* and answers `yes` whenever plain `get pods` is allowed. Ask about a subresource with `--subresource=log`. In a Role's `rules`, though, the slash form (`resources: ["pods/log"]`) is exactly right — the two syntaxes genuinely differ.
- **Everyone can already reach some non-resource URLs.** The built-in `system:public-info-viewer` and `system:discovery` bindings grant `/healthz`, `/livez`, `/version` and `/apis` to `system:authenticated`, which every impersonated identity joins. `/metrics` and any subpath such as `/healthz/etcd` are granted by nothing, so they are the only endpoints that prove a new grant works.

---

## Question 1: A grant restricted to two named objects

```bash
kubectl create serviceaccount report-reader -n rbac-report

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: config-reader
  namespace: rbac-report
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["app-settings", "feature-flags"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
EOF

kubectl create rolebinding report-reader-binding -n rbac-report \
  --role=config-reader --serviceaccount=rbac-report:report-reader
```

`resourceNames` narrows a rule to individual objects. The important property is the one the question turns on: **`resourceNames` cannot restrict `list` or `watch`.** Those verbs return a collection, and the authorizer has no object name to match before the request runs, so a rule that pairs `list` with `resourceNames` grants nothing at all. That is why "read these two ConfigMaps but do not list the namespace's ConfigMaps" is expressible in the first place — you grant `get` on the two names and simply never grant `list`.

Check it the way the grader does, with the positional `resource/name` form:

```bash
SA=system:serviceaccount:rbac-report:report-reader
kubectl auth can-i get configmaps/app-settings    --as=$SA -n rbac-report   # yes
kubectl auth can-i get configmaps/billing-secrets --as=$SA -n rbac-report   # no
kubectl auth can-i list configmaps                --as=$SA -n rbac-report   # no
```

A consequence worth internalising: `kubectl get configmap app-settings -n rbac-report --as=$SA` works, while `kubectl get configmaps -n rbac-report --as=$SA` is refused.

---

## Question 2: Granting to a group and a user

Nothing here is a ServiceAccount. RBAC subjects can be a `User`, a `Group` or a `ServiceAccount`, and Kubernetes never stores the first two — they arrive from whatever authenticates the request (a client certificate's `CN` and `O`, an OIDC token's claims), and RBAC simply matches on the string.

```bash
kubectl create clusterrole infra-auditor \
  --verb=get,list,watch \
  --resource=nodes,persistentvolumes,namespaces,storageclasses.storage.k8s.io

kubectl create clusterrolebinding infra-auditors \
  --clusterrole=infra-auditor \
  --group=platform-auditors \
  --user=dana
```

`storageclasses` needs its API group spelled out (`storageclasses.storage.k8s.io`) because `kubectl create clusterrole` writes the group into the rule from what you type; the other three live in the core group. The equivalent YAML:

```yaml
rules:
- apiGroups: [""]
  resources: ["nodes", "persistentvolumes", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
```

Verify a group grant by impersonating *any* username plus the group — for a `Group` subject the username is irrelevant:

```bash
kubectl auth can-i list nodes --as=anyone --as-group=platform-auditors   # yes
kubectl auth can-i list nodes --as=dana                                  # yes
kubectl auth can-i list nodes --as=someone-else                          # no
kubectl auth can-i delete nodes --as=dana                                # no
```

---

## Question 3: A ClusterRole assembled by the aggregation controller

```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-view
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.ck-x.io/aggregate-to-monitoring: "true"
rules: []
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-pods
  labels:
    rbac.ck-x.io/aggregate-to-monitoring: "true"
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-nodes
  labels:
    rbac.ck-x.io/aggregate-to-monitoring: "true"
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes/metrics"]
  verbs: ["get"]
EOF

kubectl create serviceaccount dashboard -n rbac-monitor
kubectl create clusterrolebinding dashboard-monitoring \
  --clusterrole=monitoring-view --serviceaccount=rbac-monitor:dashboard
```

When a ClusterRole carries an `aggregationRule`, its `rules` field stops being yours: the controller manager recomputes it as the union of every ClusterRole matching the selectors, and **overwrites whatever you wrote there**. Writing `rules: []` is the honest way to express that. It also means the reverse is true — labelling a *new* ClusterRole later silently widens `monitoring-view` with no edit to the object, which is the whole point of the pattern and the reason the built-in `view`, `edit` and `admin` roles are built this way.

Watch it happen:

```bash
kubectl get clusterrole monitoring-view -o yaml | head -30
```

The rules appear a moment after the contributors do. Then:

```bash
SA=system:serviceaccount:rbac-monitor:dashboard
kubectl auth can-i list pods --as=$SA -n kube-system              # yes
kubectl auth can-i get pods --subresource=log --as=$SA -n default # yes
kubectl auth can-i list nodes --as=$SA                            # yes
kubectl auth can-i get secrets --as=$SA -n kube-system            # no
```

---

## Question 4: The scale subresource

A Deployment's replica count can be changed two ways: by updating the Deployment, or by updating its `scale` subresource. RBAC treats them as separate resources, which is what makes "may resize, may not otherwise touch" expressible.

```bash
kubectl create serviceaccount release-bot -n rbac-deploy

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: scaler
  namespace: rbac-deploy
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments/scale"]
  verbs: ["get", "patch", "update"]
EOF

kubectl create rolebinding release-bot-scaler -n rbac-deploy \
  --role=scaler --serviceaccount=rbac-deploy:release-bot
```

Note the two syntaxes sitting side by side. In the Role, the subresource is a slash-joined **resource name** (`deployments/scale`). At the command line it is a **flag**:

```bash
SA=system:serviceaccount:rbac-deploy:release-bot
kubectl auth can-i patch deployments --subresource=scale --as=$SA -n rbac-deploy  # yes
kubectl auth can-i patch deployments/scale --as=$SA -n rbac-deploy                # no — asks about a Deployment named "scale"
kubectl auth can-i update deployments --as=$SA -n rbac-deploy                     # no
```

End to end:

```bash
kubectl scale deployment storefront -n rbac-deploy --replicas=2 --as=$SA
kubectl set image deployment/storefront web=nginx:1.28-alpine -n rbac-deploy --as=$SA   # forbidden
```

---

## Question 5: Tokens, and who gets one

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: job-runner
  namespace: rbac-token
automountServiceAccountToken: false
---
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: rbac-token
spec:
  serviceAccountName: job-runner
  automountServiceAccountToken: true
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

mkdir -p /tmp/exam/q5
kubectl create token job-runner -n rbac-token > /tmp/exam/q5/token.jwt
```

Two independent things are going on.

`automountServiceAccountToken` is settable on **both** the ServiceAccount and the Pod, and **the Pod wins**. Setting it `false` on the account makes "no token" the default for everything that uses it; the one Pod that genuinely needs API access opts back in explicitly. That is the safe direction — the opposite default means every Pod silently carries a credential it never asked for.

`kubectl create token` calls the **TokenRequest** API and returns a short-lived, audience- and time-bound token. It is not the old forever-token stored in a Secret; nothing persists in the cluster, and the default lifetime is an hour. Confirm what you saved really authenticates, rather than merely looking like a JWT:

```bash
kubectl create -o jsonpath='{.status.user.username}{"\n"}' -f - <<EOF
apiVersion: authentication.k8s.io/v1
kind: TokenReview
spec:
  token: "$(cat /tmp/exam/q5/token.jwt)"
EOF
# system:serviceaccount:rbac-token:job-runner
```

Verify the Pod really received one:

```bash
kubectl exec probe -n rbac-token -- ls /var/run/secrets/kubernetes.io/serviceaccount
```

---

## Question 6: Splitting an over-broad binding

Start by reading the estate rather than guessing at it:

```bash
kubectl get rolebinding -n rbac-review \
  -o custom-columns=NAME:.metadata.name,ROLE:.roleRef.kind/.roleRef.name
kubectl describe rolebinding legacy-access -n rbac-review
kubectl get role legacy-writer -n rbac-review -o yaml
```

The picture that comes back is the whole problem:

```
NAME              ROLE
deploy-managers   ClusterRole/edit
legacy-access     Role/legacy-writer
ops-readonly      Role/ops-viewer
```

`legacy-access` binds **one** Role — `legacy-writer`, granting `get,list,create,update` on ConfigMaps — to **three** subjects: `ServiceAccount/legacy-svc`, `User/hallie` and `Group/legacy-operators`. A RoleBinding gives every one of its subjects the *same* rules, so as long as the three share a binding they cannot have three different answers. The work is a split, not an edit.

**1. Narrow the Role the ServiceAccount keeps.** `legacy-svc` should lose `create`; it never had `delete`, so nothing else changes:

```bash
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: legacy-writer
  namespace: rbac-review
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "update"]
EOF
```

**2. Reduce `legacy-access` to the one subject that still belongs on it.** `subjects` is not a patchable list by key, so re-apply it whole:

```bash
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: legacy-access
  namespace: rbac-review
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: legacy-writer
subjects:
- kind: ServiceAccount
  name: legacy-svc
  namespace: rbac-review
EOF
```

Dropping `hallie` here is the whole of her requirement: RBAC is purely additive and has no deny rule, so a user reachable by no binding has no access. There is nothing to create for her.

**3. Give the group its own, different grant:**

```bash
kubectl create role legacy-pod-reader -n rbac-review \
  --verb=get,list,watch --resource=pods

kubectl create rolebinding legacy-operators-pods -n rbac-review \
  --role=legacy-pod-reader --group=legacy-operators
```

**Verify each clause with impersonation** rather than by re-reading the YAML — `can-i` evaluates the same authorizer the API server uses, including bindings you forgot about:

```bash
SA=system:serviceaccount:rbac-review:legacy-svc
kubectl auth can-i update configmaps -n rbac-review --as=$SA          # yes
kubectl auth can-i create configmaps -n rbac-review --as=$SA          # no

kubectl auth can-i watch pods      -n rbac-review --as=probe --as-group=legacy-operators  # yes
kubectl auth can-i get   configmaps -n rbac-review --as=probe --as-group=legacy-operators # no

kubectl auth can-i get pods -n rbac-review --as=hallie                # no
```

Two things to keep in mind while doing this. `--as-group` replaces the impersonated user's groups entirely, so `--as=probe --as-group=legacy-operators` tests the group grant and nothing else — but the identity still joins `system:authenticated`, so only assert `no` on resources no default binding grants (pods, configmaps and secrets are all safe; `/healthz` and `/version` are not).

And leave `deploy-managers` alone even though it looks alarming. It is a **RoleBinding** whose `roleRef` is a **ClusterRole** — legal, common, and the single most useful shape in RBAC: it reuses a cluster-wide set of rules while confining their effect to one namespace. `edit` only becomes cluster-wide power when bound by a *ClusterRoleBinding*.

---

## Question 7: Non-resource URLs

The API server serves endpoints that are not resources — no group, no namespace, no name — and RBAC addresses them with `nonResourceURLs` instead of `resources`.

```bash
kubectl create serviceaccount probe-agent -n rbac-probe

kubectl create clusterrole endpoint-prober --verb=get \
  --non-resource-url=/healthz \
  --non-resource-url='/healthz/*' \
  --non-resource-url=/livez \
  --non-resource-url=/version \
  --non-resource-url=/metrics

kubectl create clusterrolebinding probe-agent-endpoints \
  --clusterrole=endpoint-prober --serviceaccount=rbac-probe:probe-agent
```

Quote `'/healthz/*'` or the shell expands it against your working directory. Two structural rules: a single rule may not mix `nonResourceURLs` with `resources`, and non-resource rules only make sense in a **ClusterRole** — URLs are not namespaced, so a Role cannot express them.

The trailing `*` is a suffix wildcard, not a glob: `/healthz/*` covers `/healthz/etcd` and `/healthz/ping`, and `/healthz` on its own does not.

```bash
SA=system:serviceaccount:rbac-probe:probe-agent
kubectl auth can-i get /metrics      --as=$SA   # yes
kubectl auth can-i get /healthz/etcd --as=$SA   # yes
kubectl auth can-i list pods         --as=$SA   # no
```

Only those first two prove anything. `/healthz`, `/livez` and `/version` answer `yes` for *every* authenticated identity, granted by the built-in `system:public-info-viewer` binding — so if you had done nothing at all, three of the five endpoints would still have passed a naive check.

---

## Question 8: A grant nothing is using

```bash
kubectl logs deployment/inventory-sync -n rbac-identity --tail=4
```

```
[sync] reconciling configmaps in rbac-identity
[sync] ERROR: HTTP 403 from the API server
{ "kind": "Status", ... "message": "configmaps is forbidden: User
\"system:serviceaccount:rbac-identity:default\" cannot list resource \"configmaps\"
in API group \"\" in the namespace \"rbac-identity\"", "reason": "Forbidden", ... }
```

The API server names the identity it refused, and it is not the account this application
was given. Confirm that the grant itself is fine:

```bash
kubectl get rolebinding inventory-sync-binding -n rbac-identity -o yaml
kubectl auth can-i list configmaps \
  --as=system:serviceaccount:rbac-identity:inventory-sync -n rbac-identity
# yes
```

The RBAC is entirely correct — for `inventory-sync`. The refused request came from
`default`, so ask what the Pods actually run as:

```bash
kubectl get pods -n rbac-identity -o custom-columns=NAME:.metadata.name,SA:.spec.serviceAccountName
```

```
NAME                              SA
inventory-sync-6b8f4d9c7c-2xk4n   default
inventory-sync-6b8f4d9c7c-9wtzq   default
```

**The pod template never names the ServiceAccount**, so every replica runs as `default` and the Role applies to an identity nothing is using. A RoleBinding grants permissions to a *name*; it has no way to attach itself to a workload.

```bash
kubectl set serviceaccount deployment/inventory-sync inventory-sync -n rbac-identity
kubectl rollout status deployment/inventory-sync -n rbac-identity
```

Confirm the fix reached the Pods, not just the template:

```bash
kubectl get pods -n rbac-identity -o custom-columns=NAME:.metadata.name,SA:.spec.serviceAccountName
kubectl logs deployment/inventory-sync -n rbac-identity --tail=2
# [sync] ok: inventory-state read
```

Granting the `default` account instead would have silenced the log too — and handed the same access to every other Pod in the namespace that never set a ServiceAccount. That is why the question forbids it.

---

## Question 9: Rules pointing at the wrong API group

```bash
kubectl auth can-i list cronjobs --as=system:serviceaccount:rbac-jobs:scheduler-bot -n rbac-jobs   # no
kubectl auth can-i list pods     --as=system:serviceaccount:rbac-jobs:scheduler-bot -n rbac-jobs   # yes
```

Pods work, CronJobs do not, through the same binding — so the binding and the subject are fine and the problem is inside the rules:

```bash
kubectl get role job-manager -n rbac-jobs -o yaml
```

```yaml
rules:
- apiGroups: [""]
  resources: ["cronjobs"]
  verbs: ["get", "list", "create"]
- apiGroups: [""]
  resources: ["ingresses"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

Every rule claims the core group. Ask the cluster where those resources really live:

```bash
kubectl api-resources | grep -E '^(cronjobs|ingresses|pods) '
```

```
pods       po   v1                       true   Pod
cronjobs   cj   batch/v1                 true   CronJob
ingresses  ing  networking.k8s.io/v1     true   Ingress
```

Only `pods` is in the core group — which is exactly why it was the one thing that worked. `apiGroups: [""]` paired with `cronjobs` matches no request the API server will ever serve, so the rule is inert. RBAC never validates this: a rule naming a resource that does not exist in that group is accepted happily and simply grants nothing.

```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: job-manager
  namespace: rbac-jobs
rules:
- apiGroups: ["batch"]
  resources: ["cronjobs"]
  verbs: ["get", "list", "create"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
EOF
```

```bash
SA=system:serviceaccount:rbac-jobs:scheduler-bot
kubectl auth can-i create cronjobs.batch --as=$SA -n rbac-jobs           # yes
kubectl auth can-i list ingresses --as=$SA -n rbac-jobs                  # yes
kubectl auth can-i list ingresses --as=$SA -n rbac-jobs-staging          # no
```

Editing the Role in place (`kubectl edit role job-manager -n rbac-jobs`) is equally fine. Do not reach for `apiGroups: ["*"]` — it passes the two checks that matter here and fails the ones that assert the grant stayed narrow.

---

## Question 10: Walking back an over-broad grant

Start from what the account can do, not from what exists:

```bash
kubectl auth can-i --list --as=system:serviceaccount:rbac-excess:backup-agent | head
```

```
Resources   Non-Resource URLs   Resource Names   Verbs
*.*         []                  []               [*]
```

`*.*` with verb `*` is total access. Find where it comes from — the subject is a ServiceAccount, so only a ClusterRoleBinding or a RoleBinding can carry it:

```bash
kubectl get clusterrolebindings -o json | jq -r '
  .items[] | select(.subjects[]?.name == "backup-agent")
  | .metadata.name + "  ->  " + .roleRef.kind + "/" + .roleRef.name'
```

```
backup-agent-admin  ->  ClusterRole/cluster-admin
```

A `cluster-admin` ClusterRoleBinding, presumably granted "temporarily". Remove it and replace it with the two grants the job actually needs — namespaced reads on Pods and claims, cluster-wide reads on PersistentVolumes:

```bash
kubectl delete clusterrolebinding backup-agent-admin

kubectl create role backup-reader -n rbac-excess \
  --verb=get,list --resource=pods,persistentvolumeclaims
kubectl create rolebinding backup-agent-reader -n rbac-excess \
  --role=backup-reader --serviceaccount=rbac-excess:backup-agent

kubectl create clusterrole backup-pv-reader \
  --verb=get,list --resource=persistentvolumes
kubectl create clusterrolebinding backup-agent-pv-reader \
  --clusterrole=backup-pv-reader --serviceaccount=rbac-excess:backup-agent
```

The object names are yours to choose — the grader checks effective permissions, not names. What it does check is the split: PersistentVolumes are **cluster-scoped**, so no Role can ever grant them and the second pair has to be a ClusterRole bound with a ClusterRoleBinding. Pods and PVCs are namespaced, so binding *their* ClusterRole cluster-wide would hand over every namespace — bind narrowly instead.

```bash
SA=system:serviceaccount:rbac-excess:backup-agent
kubectl auth can-i --list --as=$SA -n rbac-excess
kubectl auth can-i list pods               --as=$SA -n rbac-excess    # yes
kubectl auth can-i list persistentvolumes  --as=$SA                   # yes
kubectl auth can-i list pods               --as=$SA -n kube-system    # no
kubectl auth can-i delete pods             --as=$SA -n rbac-excess    # no
kubectl auth can-i get secrets             --as=$SA -n kube-system    # no
```

Deleting the ServiceAccount would also have removed the excess access, and would have broken the backup job — which is why the question keeps it.
