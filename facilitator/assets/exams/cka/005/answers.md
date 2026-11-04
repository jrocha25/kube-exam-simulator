# CKA Practice Lab 005 — Answers

Every solution below is written for the exam jumphost (`ckad9999`), where `kubectl` and `helm` already point at the exam cluster.

Seven of the eighteen questions (1, 6, 8, 11, 13, 15 and 18) start from a cluster that is already broken. Each of those answers opens with the commands that find the fault before it shows the fix — on the real exam nobody tells you what is wrong, and the diagnosis is most of the work.

Questions 16 to 18 use the Gateway API. The cluster's ingress controller registers a single GatewayClass named `traefik`, whose `spec.controllerName` is `traefik.io/gateway-controller`, so `kubectl get gateway,httproute -A` and `kubectl describe` on those objects are your feedback loop throughout.

---

## Question 1: A claim that can never be provisioned

```bash
kubectl get pods -n store-data
kubectl get pvc -n store-data
kubectl describe pvc ledger-data -n store-data | grep -A5 Events
```

The Pod is `Pending`, the claim is `Pending`, and the claim's events say it all:

```
storageclass.storage.k8s.io "fast-nvme" not found
```

The claim asks for a storage class that does not exist in this cluster, so no provisioner ever picks it up and no volume is ever created. `kubectl get storageclass` shows what the cluster really offers — a single class, `local-path`, marked `(default)`.

A claim's `storageClassName` is immutable, so the claim has to be replaced. It cannot be deleted while a Pod still references it — the `kubernetes.io/pvc-protection` finalizer holds it in `Terminating` — so scale the Deployment down first:

```bash
kubectl scale deployment ledger-api -n store-data --replicas=0
kubectl wait --for=delete pod -l app=ledger-api -n store-data --timeout=120s
kubectl delete pvc ledger-data -n store-data
```

Recreate it without naming a class at all, which is what "provisioned dynamically" means: the default class is used.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ledger-data
  namespace: store-data
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

kubectl scale deployment ledger-api -n store-data --replicas=1
kubectl rollout status deployment/ledger-api -n store-data
```

Naming `local-path` explicitly works just as well. What does not work is creating a StorageClass called `fast-nvme` with no working provisioner behind it: the claim would still never bind. The default class is `WaitForFirstConsumer`, so the claim stays `Pending` until the Pod is scheduled — that is expected, not a second fault.

---

## Question 2: A retained archive tier

```bash
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: slow-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive-claim
  namespace: store-tier
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: slow-retain
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: archive-writer
  namespace: store-tier
spec:
  containers:
  - name: writer
    image: nginx:1.27.4
    volumeMounts:
    - name: archive
      mountPath: /data
  volumes:
  - name: archive
    persistentVolumeClaim:
      claimName: archive-claim
EOF
```

`kubectl get pvc -n store-tier` right after the claim is created shows `Pending`, and `kubectl describe` says `waiting for first consumer to be created before binding`. That is `WaitForFirstConsumer` doing its job: binding is deferred until a Pod is scheduled, so the volume is provisioned on the node that will actually use it. Create the Pod and the claim binds within seconds.

`reclaimPolicy: Retain` applies to the *volume*, not the claim: when `archive-claim` is eventually deleted, the PersistentVolume behind it goes to `Released` with the data intact instead of being deleted.

---

## Question 3: Two reports on one namespace

`--sort-by` only sorts ascending, so the busiest Pod is the last line:

```bash
mkdir -p /tmp/exam/q3
kubectl get pods -n insight --sort-by=.status.containerStatuses[0].restartCount \
    -o custom-columns=NAME:.metadata.name --no-headers | tail -1 > /tmp/exam/q3/restarts.txt
```

`custom-columns` takes a JSONPath per column, and a filter expression picks the right address out of the list:

```bash
kubectl get nodes --no-headers \
    -o custom-columns='NAME:.metadata.name,IP:.status.addresses[?(@.type=="InternalIP")].address' \
    | sort > /tmp/exam/q3/nodes.txt
```

Two things are worth remembering. `custom-columns` pads its columns, so anything that has to be parsed downstream is safer as JSONPath. And `-o jsonpath` has no sorting of its own — that is what `--sort-by` and the shell are for.

---

## Question 4: A namespace policy for memory limits

A `LimitRange` does three separate jobs, and this question uses all three. `defaultRequest` and `default` fill in what a container does not declare; `max` refuses what it declares too much of.

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: audit-defaults
  namespace: registry-audit
spec:
  limits:
  - type: Container
    default:
      memory: 256Mi
    defaultRequest:
      memory: 128Mi
    max:
      memory: 512Mi
EOF
```

The important property is that **a LimitRange is applied at admission and is never retroactive.** Creating it changes nothing about the four Pods already running — `orders-api`, `billing-api` and `mail-api` keep the limits they were created with, and `search-api` keeps having none. The only way to bring an existing Pod under the policy is to have it admitted again:

```bash
kubectl delete pod search-api -n registry-audit
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: search-api
  namespace: registry-audit
spec:
  containers:
  - name: api
    image: nginx:1.27.4
EOF
```

Note that this has to be a manifest rather than `kubectl run`: `kubectl run search-api` would name the container `search-api`, and the question requires it to stay `api`. Confirm the defaults landed:

```bash
kubectl get pod search-api -n registry-audit \
    -o jsonpath='{.spec.containers[0].resources}{"\n"}'
# {"limits":{"memory":"256Mi"},"requests":{"memory":"128Mi"}}
```

Note the request. Had you set `limits.memory: 256Mi` by hand and left the request out, Kubernetes would have defaulted the request *to the limit* — `256Mi`, not `128Mi`. The asymmetric pair is the evidence that the LimitRange did the work.

Finally, `max` is enforced by the same admission plugin, so you can check it without creating anything:

```bash
kubectl create --dry-run=server -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: limit-probe
  namespace: registry-audit
spec:
  containers:
  - name: probe
    image: nginx:1.27.4
    resources:
      limits:
        memory: 1Gi
EOF
# Error from server (Forbidden): maximum memory usage per Container is 512Mi, but limit is 1Gi
```

`--dry-run=server` runs the full admission chain without persisting the object — the right way to test an admission policy on a cluster you are not allowed to litter.

---

## Question 5: An autoscaler with two metrics and a scale up policy

```bash
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: storefront-hpa
  namespace: scale-web
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: storefront
  minReplicas: 3
  maxReplicas: 12
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      selectPolicy: Max
      policies:
      - type: Pods
        value: 4
        periodSeconds: 60
      - type: Percent
        value: 100
        periodSeconds: 60
EOF
```

`kubectl autoscale` cannot express any of this — it only emits a single CPU target — so this one has to be written out. With several metrics the autoscaler computes a desired replica count for each and takes the **largest**, which is why adding a memory metric can only ever make a workload scale out sooner. `selectPolicy: Max` does the same thing one level down, among the scale up policies.

---

## Question 6: An autoscaler that never sees a metric

```bash
kubectl get hpa -n scale-batch
kubectl describe hpa render-worker-hpa -n scale-batch | grep -A5 Conditions
```

The `TARGETS` column reads `<unknown>/60%` and the conditions say:

```
ScalingActive   False   FailedGetResourceMetric
```

A `Utilization` target is a *percentage of the request*. The Deployment's container declares no resources at all, so there is no denominator, the autoscaler cannot compute a percentage, and it gives up:

```bash
kubectl get deployment render-worker -n scale-batch \
    -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'   # prints {}
```

Giving the container a request fixes it:

```bash
kubectl set resources deployment render-worker -n scale-batch --containers=worker \
    --requests=cpu=100m,memory=64Mi --limits=cpu=500m,memory=256Mi
kubectl rollout status deployment/render-worker -n scale-batch
```

Within a scrape cycle or two `kubectl get hpa -n scale-batch` shows a real percentage and `ScalingActive` flips to `True`.

Note what is *not* evidence of a fix: the Deployment sitting at `2` replicas. An autoscaler raises its target to `minReplicas` even while its metrics are unreadable, so the replica count was already right before anything was changed. The metric is the thing to check.

---

## Question 7: Ingress only from a trusted namespace

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payments-ingress
  namespace: net-tier
spec:
  podSelector:
    matchLabels:
      app: payments
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          team: trusted
    ports:
    - protocol: TCP
      port: 80
EOF
```

One policy is enough, and no separate default-deny is needed: the moment any policy selects the `app=payments` Pods with `policyTypes: [Ingress]`, everything not explicitly allowed is denied — including traffic from other Pods in `net-tier`, which is the part that catches people out. A NetworkPolicy is not scoped to its own namespace on the *source* side, only on the target side.

The trap in this question is writing

```yaml
    - namespaceSelector:
        matchLabels:
          team: trusted
    - podSelector: {}
```

as two list items. Two items in `from` are OR'ed, so that would admit every Pod in the namespace as well. A single item carrying both selectors is an AND.

Check it from both sides:

```bash
PAYMENTS=$(kubectl get pod payments -n net-tier -o jsonpath='{.status.podIP}')
kubectl exec client-allowed -n net-tier-clients -- wget -q -T 5 -O- http://$PAYMENTS   # works
kubectl exec client-denied  -n net-tier-others  -- wget -q -T 5 -O- http://$PAYMENTS   # times out
kubectl exec neighbour      -n net-tier         -- wget -q -T 5 -O- http://$PAYMENTS   # times out
```

---

## Question 8: An egress policy that took DNS with it

```bash
kubectl exec frontend -n net-egress -- nslookup backend.net-egress.svc.cluster.local
```

```
nslookup: write to '10.43.0.10': Connection refused
;; connection timed out; no servers could be reached
```

The name lookup itself is failing, not the HTTP request. Every lookup is a packet to the cluster DNS service — which is egress traffic like any other:

```bash
kubectl get networkpolicy -n net-egress
kubectl get networkpolicy frontend-egress -n net-egress -o yaml
```

`frontend-egress` selects `app=frontend` with `policyTypes: [Egress]` and permits exactly one destination: TCP 80 to `app=backend`. Everything else is denied, and CoreDNS on UDP 53 is part of everything else. The policy is right about HTTP and silent about DNS, which is why the symptom looks like a name resolution problem rather than a firewall one.

Add a second egress rule for kube-dns and leave the first alone:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: net-egress
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - protocol: TCP
      port: 80
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
```

`kubernetes.io/metadata.name` is set automatically on every namespace, so it is always available as a selector without labelling anything. TCP 53 belongs there alongside UDP: DNS falls back to TCP for large responses.

```bash
kubectl exec frontend -n net-egress -- nslookup backend.net-egress.svc.cluster.local   # resolves
kubectl exec frontend -n net-egress -- wget -q -T 5 -O- http://backend                 # serves
OTHER=$(kubectl get pod other -n net-egress -o jsonpath='{.status.podIP}')
kubectl exec frontend -n net-egress -- wget -q -T 5 -O- http://$OTHER                  # still denied
```

Deleting the policy, or adding `egress: [{}]`, would also make the lookup work — and would throw away the restriction the question told you to keep.

---

## Question 9: Namespaced read only access

```bash
kubectl create serviceaccount report-runner -n rbac-app

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: report-reader
  namespace: rbac-app
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
EOF

kubectl create rolebinding report-runner-read -n rbac-app \
    --role=report-reader --serviceaccount=rbac-app:report-runner
```

`kubectl create role` can do this in one line too — `--verb=get,list,watch --resource=pods,pods/log,configmaps` — but that gives every verb to every resource, which is more than was asked for.

Verify it, and note the flag that matters:

```bash
kubectl auth can-i get pods --as=system:serviceaccount:rbac-app:report-runner -n rbac-app                     # yes
kubectl auth can-i get pods --subresource=log --as=system:serviceaccount:rbac-app:report-runner -n rbac-app   # yes
kubectl auth can-i create pods --as=system:serviceaccount:rbac-app:report-runner -n rbac-app                  # no
kubectl auth can-i get pods --as=system:serviceaccount:rbac-app:report-runner -n rbac-app-staging             # no
```

**`kubectl auth can-i get pods/log` does not test the subresource.** The positional form is `verb resource/resourceName`, so `pods/log` is read as "the Pod named `log`" and you get an answer to a question you did not ask — one that says `yes` here purely because `get pods` is allowed. Subresources need `--subresource=log`.

---

## Question 10: One ClusterRole, two different bindings

```bash
kubectl create serviceaccount oncall -n rbac-ops

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-debugger
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-viewer
rules:
- apiGroups: [""]
  resources: ["nodes", "persistentvolumes"]
  verbs: ["get", "list"]
EOF

kubectl create rolebinding oncall-debug -n rbac-ops \
    --clusterrole=pod-debugger --serviceaccount=rbac-ops:oncall
kubectl create clusterrolebinding oncall-node-view \
    --clusterrole=node-viewer --serviceaccount=rbac-ops:oncall
```

This is the whole point of the question. A **RoleBinding that references a ClusterRole** grants that ClusterRole's rules *only inside the binding's namespace* — the role is defined once, cluster wide, and handed out namespace by namespace. That is how `view`, `edit` and `admin` are meant to be used, and it is why `oncall-debug` gives no access whatsoever in `rbac-ops-secure`.

A ClusterRoleBinding is a different thing entirely, and it is what cluster-scoped resources require: `nodes` and `persistentvolumes` do not live in a namespace, so no RoleBinding could ever grant access to them.

```bash
kubectl auth can-i create pods --subresource=exec --as=system:serviceaccount:rbac-ops:oncall -n rbac-ops          # yes
kubectl auth can-i create pods --subresource=exec --as=system:serviceaccount:rbac-ops:oncall -n rbac-ops-secure   # no
kubectl auth can-i list nodes --as=system:serviceaccount:rbac-ops:oncall                                          # yes
```

`kubectl exec` needs `create` on `pods/exec`, not `get` — the API server opens the session with a POST.

---

## Question 11: A binding pointed at nobody

```bash
kubectl auth can-i update deployments.apps \
    --as=system:serviceaccount:rbac-broken:sync-agent -n rbac-broken     # no

kubectl get role,rolebinding -n rbac-broken
kubectl describe rolebinding sync-agent-binding -n rbac-broken
```

Both objects exist, and the Role's rules are exactly what the automation needs. The binding is the problem:

```
Role:  sync-agent-role
Subjects:
  Kind            Name         Namespace
  ServiceAccount  sync-agent   default
```

A ServiceAccount subject is identified by name **and** namespace. This binding grants the Role to `system:serviceaccount:default:sync-agent` — an account in a different namespace, which nothing in `rbac-broken` runs as. The grant is real, it just lands on the wrong identity. Nothing errors, because RBAC has no reason to check that a subject exists.

```bash
kubectl patch rolebinding sync-agent-binding -n rbac-broken --type=json \
    -p '[{"op": "replace", "path": "/subjects/0/namespace", "value": "rbac-broken"}]'
```

`roleRef` is immutable, so had the *role reference* been wrong the binding would have had to be deleted and recreated. `subjects` is not, so a patch is enough here.

```bash
kubectl auth can-i update deployments.apps --as=system:serviceaccount:rbac-broken:sync-agent -n rbac-broken           # yes
kubectl auth can-i update deployments.apps --as=system:serviceaccount:rbac-broken:sync-agent -n rbac-broken-staging   # no
```

Reaching for a ClusterRoleBinding here would also make the first command say `yes` — and would hand the account every namespace in the cluster, which is precisely what the question forbade.

---

## Question 12: Installing and upgrading from a public repository

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update podinfo

helm install podinfo podinfo/podinfo -n helm-pub \
    --set replicaCount=2 --set ui.message="helioscale edge" --wait

helm upgrade podinfo podinfo/podinfo -n helm-pub \
    --reuse-values --set replicaCount=4 --wait
```

`--reuse-values` is the whole question. A plain `helm upgrade --set replicaCount=4` starts from the chart's defaults and applies only the flags given on that command line, so `ui.message` would silently revert to its default and the upgrade would look successful while quietly undoing half the install. `--reuse-values` layers the new `--set` on top of what the release already had. Repeating both `--set` flags works just as well and is easier to reason about; a values file checked into git is what you would actually do in production.

```bash
helm list -n helm-pub                 # REVISION 2, STATUS deployed
helm get values podinfo -n helm-pub   # replicaCount: 4 and ui.message intact
helm history podinfo -n helm-pub
kubectl get deployment -n helm-pub
```

`helm rollback podinfo 1 -n helm-pub` would put the release back at two replicas, as revision 3.

---

## Question 13: A chart that renders valid YAML and an invalid object

```bash
helm install orderbook /tmp/exam/q13/orderbook -n helm-broken
```

```
Error: INSTALLATION FAILED: ... .spec.replicas: expected numeric (int or float), got string
```

The exact wording depends on the Helm version — older releases quote the API server's own `cannot unmarshal string into ... of type int32` — but every variant says the same thing: something that should be a number arrived as a string. Helm rendered the templates without complaint; the failure came later, when the result met the Deployment schema. Render it yourself to see what was actually sent:

```bash
helm template orderbook /tmp/exam/q13/orderbook | grep -n replicas
```

```
24:  replicas: "3"
```

`replicas` is an `int32`. The template pipes the value through `quote`:

```yaml
  replicas: {{ .Values.replicaCount | quote }}
```

so a perfectly good integer in `values.yaml` reaches the API server as a string. Drop the pipe:

```bash
sed -i 's/{{ .Values.replicaCount | quote }}/{{ .Values.replicaCount }}/' \
    /tmp/exam/q13/orderbook/templates/deployment.yaml
helm template orderbook /tmp/exam/q13/orderbook | grep -n replicas    # replicas: 3
```

A failed install still leaves the release behind, in `failed` state, and Helm will not reuse the name:

```bash
helm list -n helm-broken --all          # orderbook   failed
helm uninstall orderbook -n helm-broken
helm install orderbook /tmp/exam/q13/orderbook -n helm-broken --wait
```

`helm upgrade --install` would have gone straight through instead. `helm template` and `helm install --dry-run` are the two commands worth reaching for the moment an install fails: the first shows what a chart produces without touching the cluster, the second shows what the cluster makes of it.

Note that `quote` is right far more often than it is wrong — on image tags, on anything that could be read as a boolean or a version number. It is only wrong on the numeric fields.

---

## Question 14: A production overlay over a generated ConfigMap

```bash
mkdir -p /tmp/exam/q14/overlays/prod
cat > /tmp/exam/q14/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: kustom-app
namePrefix: prod-

labels:
- pairs:
    tier: frontend
  includeSelectors: false

resources:
- ../../base

images:
- name: nginx
  newTag: 1.27.4

replicas:
- name: web
  count: 4

configMapGenerator:
- name: web-content
  behavior: replace
  literals:
  - index.html=production
EOF

kubectl kustomize /tmp/exam/q14/overlays/prod    # always read this before applying
kubectl apply -k /tmp/exam/q14/overlays/prod
```

Three details decide whether this works.

`behavior: replace` on a `configMapGenerator` that reuses the base's generator name overrides the base's data instead of generating a second ConfigMap. `merge` would keep the base keys and add to them; leaving `behavior` out entirely is an error, because two generators would then claim the same name.

The generated ConfigMap gets a content hash appended — `prod-web-content-h57m4454k9` — and changing the content changes the hash, which is what forces a rollout when configuration changes. You never write that name down: kustomize rewrites every reference to it, including the Deployment's `volumes[].configMap.name`, because the base referred to the generator by its plain name.

`replicas` and `patches` both match resources by their name **in the base**, before `namePrefix` runs, which is why the entry says `web` and not `prod-web`.

`includeSelectors: false` keeps `tier: frontend` out of the Deployment's `matchLabels`. Adding a label to an existing Deployment's selector is rejected by the API server, since `spec.selector` is immutable — harmless on a first apply, a failed apply on the second.

---

## Question 15: An overlay whose patches match nothing

```bash
kubectl kustomize /tmp/exam/q15/overlays/staging
```

```
error: no resource matches strategic merge patch "Deployment.v1.apps/api-server.[noNs]":
no matches for Id Deployment.v1.apps/api-server.[noNs]; failed to find unique target for patch
```

The error names the target it could not find: a Deployment called `api-server`. The base holds a different name:

```bash
grep -r "name:" /tmp/exam/q15/base/deployment.yaml     # name: api
grep -rn "api-server" /tmp/exam/q15/overlays/staging/
```

Both patches are aimed at `api-server` — the strategic merge patch through its own `metadata.name`, and the JSON 6902 patch through the `target` block in `kustomization.yaml`. Kustomize refuses to build at all rather than apply a patch it cannot place, which is why nothing at all is rendered.

```bash
sed -i 's/name: api-server/name: api/' \
    /tmp/exam/q15/overlays/staging/replicas-patch.yaml \
    /tmp/exam/q15/overlays/staging/kustomization.yaml

kubectl kustomize /tmp/exam/q15/overlays/staging > /tmp/exam/q15/rendered.yaml
grep -E "namespace|replicas|image" /tmp/exam/q15/rendered.yaml
```

A strategic merge patch is matched on the group, kind, name and namespace in its own metadata; a JSON 6902 patch is matched on the explicit `target` block. Both had to be corrected — fixing only one leaves the same error pointing at the other.

Renaming the Deployment in the base would also make it build, and would break every other overlay that consumes that base. That is why the question fenced it off.

---

## Question 16: A Gateway with a rewrite and a header filter

```bash
kubectl get gatewayclass     # traefik   traefik.io/gateway-controller   True

cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shop-gw
  namespace: edge-shop
spec:
  gatewayClassName: traefik
  listeners:
  - name: web
    port: 80
    protocol: HTTP
    hostname: shop.helioscale.io
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop-route
  namespace: edge-shop
spec:
  parentRefs:
  - name: shop-gw
  hostnames:
  - shop.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /
    backendRefs:
    - name: shop-api
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-Edge
          value: helioscale
    backendRefs:
    - name: shop-web
      port: 80
EOF

kubectl get gateway,httproute -n edge-shop
kubectl describe httproute shop-route -n edge-shop
```

Rule order in the manifest does not decide which rule wins. The Gateway API specifies precedence by *specificity*: the longest matching path prefix is chosen, so `/api` beats `/` regardless of where each sits in the list. Writing the catch-all first is safe here, unlike in an Ingress.

`ReplacePrefixMatch` replaces only the part of the path that the rule matched, so `/api/orders` reaches `shop-api` as `/orders`. `ReplaceFullPath` would have thrown the rest of the path away.

Filters are per rule, not per route — the header is added only on the traffic going to `shop-web`. `backendRefs` has no `namespace` field in use here, and that is deliberate: a backend in another namespace additionally requires a ReferenceGrant.

---

## Question 17: A route attaching to a Gateway in another namespace

```bash
kubectl patch gateway platform-gw -n edge-platform --type=json -p '[
  {"op": "replace", "path": "/spec/listeners/0/allowedRoutes/namespaces", "value":
    {"from": "Selector", "selector": {"matchLabels": {"gateway-access": "allowed"}}}}
]'

kubectl label namespace edge-team gateway-access=allowed

cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: team-route
  namespace: edge-team
spec:
  parentRefs:
  - name: platform-gw
    namespace: edge-platform
    sectionName: web
  hostnames:
  - team.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: team-api
      port: 80
EOF

kubectl describe httproute team-route -n edge-team | grep -A10 Status
```

Attachment is negotiated from both ends, and both ends have to agree. The route asks for a parent with `parentRefs.namespace`; the Gateway decides who may ask, with `allowedRoutes`. Neither side alone is enough — this is what keeps one team from hijacking another team's entry point.

`from: Selector` matches on **namespace labels**, not route labels, which is why `edge-team` had to be labelled. `from: All` would have opened the listener to the whole cluster.

`sectionName: web` pins the route to one named listener. Without it the route attaches to every listener on the Gateway whose hostname and protocol are compatible — usually not what you want on a shared Gateway.

`team.helioscale.io` falls under the listener's `*.helioscale.io`, so the two hostnames intersect and the route is programmed for the narrower of the two. A hostname outside that wildcard would attach and then serve nothing.

---

## Question 18: A route that names a listener that does not exist

```bash
kubectl describe httproute catalog-route -n edge-stuck | grep -A12 Status
```

```
Conditions:
  Type          Status   Reason
  Accepted      False    NoMatchingParent
  ResolvedRefs  True     ResolvedRefs
```

`ResolvedRefs: True` says the backend is fine — the Service exists and the port is right. `Accepted: False` with `NoMatchingParent` says the route never attached to the Gateway at all, so no proxy configuration was ever generated. Compare the two objects:

```bash
kubectl get gateway edge-gw -n edge-stuck -o yaml | grep -A8 listeners
kubectl get httproute catalog-route -n edge-stuck -o yaml | grep -A6 -E "parentRefs|hostnames"
```

The Gateway publishes one listener, named `public`, serving `catalog.helioscale.io`. The route asks for `sectionName: http` — a listener that does not exist — and declares the hostname `shop.helioscale.io`, which does not intersect what the listener serves. Either fault alone would be enough to leave the route unattached.

```bash
kubectl patch httproute catalog-route -n edge-stuck --type=json -p '[
  {"op": "replace", "path": "/spec/parentRefs/0/sectionName", "value": "public"},
  {"op": "replace", "path": "/spec/hostnames/0", "value": "catalog.helioscale.io"}
]'

kubectl describe httproute catalog-route -n edge-stuck | grep -A12 Status
```

Both conditions now report `True`.

Dropping `sectionName` entirely also works, since the Gateway has only one listener — but naming it is what you want on a Gateway that will grow a second one. What does not work is editing the Gateway to match the route: its listener and hostname belong to the platform team, and an HTTPRoute that disagrees with its parent is always the route's problem to fix.
