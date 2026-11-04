# CKA Practice Lab 004 — Answers

Every solution below is written for the exam jumphost (`ckad9999`), where `kubectl` and `helm` already point at the exam cluster.

Questions 11 to 17 are about the Gateway API. The cluster's ingress controller registers a single GatewayClass named `traefik`, whose `spec.controllerName` is `traefik.io/gateway-controller`, and the verification scripts only require that the Gateway objects reach the status the controller reports — so `kubectl get gateway,httproute -A` and `kubectl describe` on those objects are your feedback loop throughout.

---

## Question 1: Reusing a PersistentVolume that was left Released

```bash
kubectl get pv archive-pv
kubectl get pv archive-pv -o yaml | grep -A5 claimRef
```

The volume is in the `Released` phase: its `spec.claimRef` still points at the deleted `archive/archive-old` claim, and Kubernetes will not bind a `Released` volume to anything else. Clearing the reference puts it back to `Available` without touching the data:

```bash
kubectl patch pv archive-pv --type=json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl get pv archive-pv     # now Available
```

Then create the new claim. It must ask for the same storage class, otherwise the default class would provision a brand new volume instead of binding to this one:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive-pvc
  namespace: archive
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: archive-manual
  resources:
    requests:
      storage: 500Mi
EOF

kubectl get pvc archive-pvc -n archive     # Bound to archive-pv
```

A `500Mi` request binds to a `1Gi` volume: the volume only has to be at least as large as the request.

Finally fill in the claim name and apply the prepared manifest:

```bash
sed -i 's/claimName: ""/claimName: archive-pvc/' /tmp/exam/q1/archive-deploy.yaml
kubectl apply -f /tmp/exam/q1/archive-deploy.yaml
kubectl rollout status deployment/archive-api -n archive
```

Deleting and recreating the PersistentVolume would also let a new claim bind, but on a real cluster that is how you lose the retained data — the whole point of `Retain` is that the volume outlives the claim.

---

## Question 2: Scaling and rolling out a new image with a change cause

```bash
kubectl annotate deployment media-api -n media \
  kubernetes.io/change-cause="image update to nginx 1.27.4" --overwrite

kubectl scale deployment media-api -n media --replicas=4
kubectl set image deployment/media-api api=nginx:1.27.4 -n media

kubectl rollout status deployment/media-api -n media
kubectl rollout history deployment/media-api -n media
```

The order matters if you want the change cause to show up in `rollout history`. The annotation is copied onto the ReplicaSet at the moment the ReplicaSet is created, so annotating *before* the image change means the new ReplicaSet inherits it. Annotating afterwards updates the Deployment but leaves the already created ReplicaSet — and therefore the history line — without a cause.

`kubectl set image` addresses the container by name, so it cannot accidentally rename it.

---

## Question 3: Pods that never get scheduled

```bash
kubectl get pods -n analytics
kubectl describe pod -n analytics -l app=report-builder | grep -A10 Events
kubectl describe nodes | grep -A5 "Allocatable"
```

The scheduler reports `0/3 nodes are available: 3 Insufficient cpu, 3 Insufficient memory`. The container asks for `6` CPUs and `24Gi` of memory, far more than any node in this cluster can offer, so no node ever fits and the Pods stay `Pending` forever.

Bring the requests and limits back to something the workload actually uses, keeping all four values in place:

```bash
kubectl patch deployment report-builder -n analytics --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "200m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "256Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "500m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"}
]'

kubectl rollout status deployment/report-builder -n analytics
```

Deleting the `resources` block entirely would also make the Pods schedule, but it is explicitly forbidden here — and on a shared cluster it turns the workload into a best effort Pod that the kubelet evicts first under pressure.

---

## Question 4: HorizontalPodAutoscaler with a scale down window

```bash
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: checkout-hpa
  namespace: checkout
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: checkout-api
  minReplicas: 2
  maxReplicas: 8
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 45
EOF

kubectl get hpa checkout-hpa -n checkout
```

`kubectl autoscale` can create the object in one line, but it cannot express `behavior`, so the manifest is the practical route here. `type: Utilization` is a percentage of the container's CPU *request*, which is why the target Deployment has to declare one — with no request the autoscaler reports `<unknown>` and never scales.

---

## Question 5: Finding the busiest Pod

```bash
kubectl top pods -A --sort-by=cpu | head
```

The top line is the answer. Take the namespace and the name from the first two columns:

```bash
mkdir -p /tmp/exam/q5
echo "loadgen/$(kubectl get pods -n loadgen -l app=cpu-hog -o jsonpath='{.items[0].metadata.name}')" \
  > /tmp/exam/q5/top-pod.txt

kubectl get pods -n loadgen -l app=cpu-hog -o jsonpath='{.items[0].spec.nodeName}' \
  > /tmp/exam/q5/top-node.txt

cat /tmp/exam/q5/top-pod.txt /tmp/exam/q5/top-node.txt
```

`kubectl top` reports live usage from metrics-server, which is what the question asks for — `kubectl describe node` would show *requests*, a completely different number. The node a Pod runs on is in `kubectl get pod -o wide`, or in `.spec.nodeName` as above.

---

## Question 6: Choosing the least permissive NetworkPolicy

```bash
head -50 /tmp/exam/q6/policies/policy-a.yaml
head -50 /tmp/exam/q6/policies/policy-b.yaml
head -50 /tmp/exam/q6/policies/policy-c.yaml
```

All three select `app=ledger` and declare `policyTypes: [Ingress]`, but they differ in what they let in:

| File | Ingress rule | Verdict |
|---|---|---|
| `policy-a.yaml` | one empty rule `- {}` | allows every source on every port — no restriction at all |
| `policy-b.yaml` | `namespaceSelector` matching `kubernetes.io/metadata.name: ledger-clients`, port `80/TCP` | exactly the requirement |
| `policy-c.yaml` | `namespaceSelector: {}`, port `80/TCP` | limits the port but allows every namespace |

`policy-b.yaml` is the least permissive one that still satisfies the requirement:

```bash
kubectl apply -f /tmp/exam/q6/policies/policy-b.yaml
kubectl describe networkpolicy ledger-ingress -n ledger
```

Two details worth remembering: an empty `namespaceSelector: {}` means *all namespaces*, not *no namespaces*; and `kubernetes.io/metadata.name` is a label the API server maintains on every namespace, so it is the reliable way to select one namespace by name without labelling it yourself.

---

## Question 7: Namespace scoped RBAC for an automation account

```bash
kubectl create serviceaccount pipeline-bot -n delivery
```

`kubectl create clusterrole` only produces a single rule per invocation, and this ClusterRole needs two — different verbs on different resources — so write it out:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: deploy-manager
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
EOF

kubectl create rolebinding pipeline-binding \
  --clusterrole=deploy-manager \
  --serviceaccount=delivery:pipeline-bot \
  -n delivery
```

Binding a ClusterRole with a **RoleBinding** is the idiomatic way to reuse one permission set while keeping the grant confined to a single namespace. The same ClusterRole bound with a ClusterRoleBinding would have granted it everywhere.

```bash
kubectl auth can-i create deployments --as=system:serviceaccount:delivery:pipeline-bot -n delivery           # yes
kubectl auth can-i create deployments --as=system:serviceaccount:delivery:pipeline-bot -n delivery-staging   # no
```

---

## Question 8: Adding a native sidecar

```bash
kubectl patch deployment shipment-tracker -n logistics --patch-file=/dev/stdin <<'EOF'
spec:
  template:
    spec:
      initContainers:
      - name: log-shipper
        image: busybox:1.36
        restartPolicy: Always
        command: ["/bin/sh"]
        args: ["-c", "tail -F /var/log/app/tracker.log"]
        volumeMounts:
        - name: app-logs
          mountPath: /var/log/app
      containers:
      - name: tracker
        volumeMounts:
        - name: app-logs
          mountPath: /var/log/app
      volumes:
      - name: app-logs
        emptyDir: {}
EOF

kubectl rollout status deployment/shipment-tracker -n logistics
kubectl get pods -n logistics
```

A **native sidecar** is an entry in `initContainers` that sets `restartPolicy: Always`. The kubelet starts it before the application containers, keeps it running for the whole life of the Pod, and shuts it down after the application containers — which is exactly what a log shipper needs and what a plain `containers` entry cannot guarantee at startup.

Because the sidecar starts *first*, `tail -f` would fail immediately: `/var/log/app/tracker.log` does not exist yet on the fresh `emptyDir`. `tail -F` keeps retrying until the file appears, which is why the task specifies it.

The patch is a strategic merge, so the `containers` and `initContainers` lists are merged by container name: `tracker` only gains the new `volumeMounts` entry and keeps its image and command.

```bash
POD=$(kubectl get pods -n logistics -l app=shipment-tracker -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD -n logistics -c log-shipper
```

---

## Question 9: A PriorityClass just below the highest existing one

```bash
kubectl get priorityclass
```

Ignoring `system-cluster-critical` and `system-node-critical`, the user defined classes are `helioscale-bulk` (`12000`) and `helioscale-standard` (`45000`). The highest is `45000`, so the new class takes `44999`:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: edge-critical
value: 44999
globalDefault: false
description: "Edge proxy, just below the standard tier"
EOF

kubectl patch deployment edge-proxy -n priority \
  -p '{"spec": {"template": {"spec": {"priorityClassName": "edge-critical"}}}}'

kubectl rollout status deployment/edge-proxy -n priority
kubectl get pods -n priority -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority
```

`globalDefault: true` would attach this priority to every Pod created without an explicit class anywhere in the cluster, which is why the task rules it out. The `value` is what the scheduler compares and what preemption is based on; the resolved number is stamped onto each Pod in `.spec.priority`.

---

## Question 10: Install, upgrade and roll back a local chart

```bash
helm install web-edge /tmp/exam/q10/helioscale-web \
  -n edge-helm --set replicaCount=3

helm upgrade web-edge /tmp/exam/q10/helioscale-web \
  -n edge-helm --set replicaCount=5 --set image.tag=1.28.0

helm rollback web-edge 1 -n edge-helm

helm history web-edge -n edge-helm
helm list -n edge-helm
```

The chart path is a local directory, so no `helm repo add` is involved — Helm installs straight from the unpacked chart.

Note that `--set` on an upgrade does not inherit the values of the previous revision: the upgrade has to repeat `replicaCount` (or use `--reuse-values`) or it would fall back to the chart default of `1`. The rollback creates a *new* revision, number `3`, whose content is a copy of revision `1` — Helm never rewinds the revision counter.

```bash
helm get values web-edge -n edge-helm          # replicaCount: 3
kubectl get deployment web-edge -n edge-helm -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## Question 11: First Gateway and HTTPRoute

```bash
kubectl get gatewayclass
kubectl describe gatewayclass traefik
```

The class `traefik` is the one the controller has accepted (`Accepted=True`). Write its controller name out:

```bash
mkdir -p /tmp/exam/q11
kubectl get gatewayclass traefik -o jsonpath='{.spec.controllerName}' > /tmp/exam/q11/gatewayclass.txt
cat /tmp/exam/q11/gatewayclass.txt     # traefik.io/gateway-controller
```

Then the Gateway and the route:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge-gw
  namespace: edge-basic
spec:
  gatewayClassName: traefik
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: search.helioscale.io
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: search-route
  namespace: edge-basic
spec:
  parentRefs:
  - name: edge-gw
  hostnames:
  - search.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: search-svc
      port: 80
EOF

kubectl get gateway edge-gw -n edge-basic
kubectl get httproute search-route -n edge-basic -o yaml | grep -A15 status
```

The three objects map onto each other like this: the **GatewayClass** is cluster scoped and names the controller that implements it, roughly the Gateway API's `IngressClass`; the **Gateway** is the listener the controller actually programs; and the **HTTPRoute** is the routing table, owned by the application team, that attaches to a Gateway through `parentRefs`.

`Programmed=True` on the Gateway means the controller has provisioned the underlying listener. If it stays `False`, the usual suspects are a `gatewayClassName` no controller claims, or a port the data plane does not serve.

---

## Question 12: Migrating an Ingress to an HTTPRoute

```bash
kubectl get ingress legacy-web -n edge-migrate -o yaml
```

The Ingress serves `www.helioscale.io` and routes the prefix `/catalog` to `catalog-svc:80` and `/profile` to `profile-svc:80`. The same thing as an HTTPRoute, with the header filter added:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: edge-migrate
spec:
  parentRefs:
  - name: web-gw
  hostnames:
  - www.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /catalog
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
        - name: X-Helioscale-Edge
          value: gateway
    backendRefs:
    - name: catalog-svc
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /profile
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
        - name: X-Helioscale-Edge
          value: gateway
    backendRefs:
    - name: profile-svc
      port: 80
EOF

kubectl get httproute web-route -n edge-migrate -o yaml | grep -A15 status
kubectl delete ingress legacy-web -n edge-migrate
```

Filters are declared per rule, not per route, which is why the block appears twice. `set` replaces the header if the client already sent one; `add` would append a second value instead.

The Ingress `pathType: Prefix` becomes `path.type: PathPrefix` — the spelling changes between the two APIs. Delete the Ingress only after the route reports `Accepted=True`, so the hostname is never left unserved.

---

## Question 13: Canary release with weights and a header override

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: pay-route
  namespace: edge-canary
spec:
  parentRefs:
  - name: canary-gw
  hostnames:
  - pay.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
      headers:
      - name: x-canary
        value: always
    backendRefs:
    - name: pay-canary
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: pay-stable
      port: 80
      weight: 90
    - name: pay-canary
      port: 80
      weight: 10
EOF

kubectl get httproute pay-route -n edge-canary -o yaml | grep -A15 status
```

Two mechanisms are at work here.

**Weights** turn several `backendRefs` in one rule into a traffic split. They are relative, not percentages: `90` and `10` happen to add up to `100`, but `9` and `1` would behave identically. A backend with `weight: 0` receives nothing.

**Rule precedence** is defined by the specification, not by the order in the manifest: among matching rules the one with the most specific match wins, and a rule that matches on a header outranks one that only matches a path. So the header rule takes priority for requests carrying `x-canary: always`, and everything else falls through to the weighted split. Listing it first is good style, but it is the specificity that decides.

---

## Question 14: A second listener with restricted allowed routes

```bash
kubectl get gateway shared-gw -n edge-shared -o yaml
kubectl get namespace team-orders --show-labels
```

Add the listener without disturbing the existing one — a JSON patch that appends to the list is the safest way:

```bash
kubectl patch gateway shared-gw -n edge-shared --type=json -p '[
  {"op": "add", "path": "/spec/listeners/-", "value": {
     "name": "partners",
     "port": 80,
     "protocol": "HTTP",
     "hostname": "partners.helioscale.io",
     "allowedRoutes": {
       "namespaces": {
         "from": "Selector",
         "selector": {"matchLabels": {"gateway-access": "allowed"}}
       }
     }
  }}
]'
```

Then the route, in the other namespace:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: orders-route
  namespace: team-orders
spec:
  parentRefs:
  - name: shared-gw
    namespace: edge-shared
    sectionName: partners
  hostnames:
  - partners.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: orders-svc
      port: 80
EOF

kubectl get gateway shared-gw -n edge-shared -o jsonpath='{range .status.listeners[*]}{.name}{"\t"}{.attachedRoutes}{"\n"}{end}'
kubectl describe httproute orders-route -n team-orders
```

Three things have to line up for a cross namespace attachment to work, and each one produces a different failure:

- `parentRefs.namespace` — without it the route looks for a Gateway called `shared-gw` in its *own* namespace and reports `NoMatchingParent`.
- The listener's `allowedRoutes` — the default is `from: Same`, which rejects routes from other namespaces with `NotAllowedByListeners`. `from: Selector` delegates the decision to a namespace label, so the Gateway owner controls who may attach without naming every team.
- The hostname — a route whose hostnames do not intersect the listener's hostname is refused with `NoMatchingListenerHostname`.

`sectionName` pins the route to one specific listener; without it the route would attach to every compatible listener on the Gateway.

Note that this is the reverse of the direction guarded by a ReferenceGrant (question 16): `allowedRoutes` is the Gateway owner allowing routes *in*, while a ReferenceGrant is the backend owner allowing references *to* its Services.

---

## Question 15: Terminating TLS on the Gateway

```bash
kubectl get secret helioscale-tls -n edge-tls
```

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tls-gw
  namespace: edge-tls
spec:
  gatewayClassName: traefik
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    hostname: secure.helioscale.io
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: helioscale-tls
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: secure-route
  namespace: edge-tls
spec:
  parentRefs:
  - name: tls-gw
    sectionName: https
  hostnames:
  - secure.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: secure-svc
      port: 80
EOF

kubectl describe gateway tls-gw -n edge-tls
```

TLS is configured on the **listener**, not on the route — this is one of the clearer improvements over Ingress, where the certificate lived in a `spec.tls` block detached from the rule that used it.

`mode: Terminate` means the Gateway decrypts and forwards plain HTTP to the backend, which is why the `backendRefs` port is still `80`. The alternative, `mode: Passthrough`, hands the encrypted stream straight to the backend and cannot be used with an HTTPRoute at all, since there is nothing to inspect.

The listener's own status is where certificate problems surface: `kubectl get gateway tls-gw -n edge-tls -o yaml` shows a per listener `ResolvedRefs` condition, which goes `False` with reason `InvalidCertificateRef` if the Secret is missing, is not of type `kubernetes.io/tls`, or lives in another namespace without a ReferenceGrant.

---

## Question 16: A backend in another namespace

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: inventory-route
  namespace: edge-front
spec:
  parentRefs:
  - name: front-gw
  hostnames:
  - inventory.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: inventory-svc
      namespace: backend-store
      port: 80
EOF

kubectl describe httproute inventory-route -n edge-front
```

At this point the route is `Accepted` but `ResolvedRefs` is `False` with reason `RefNotPermitted`: a `backendRef` that names another namespace is refused until that namespace opts in. The grant is created on the *receiving* side, by the team that owns the Service:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-edge-front
  namespace: backend-store
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: edge-front
  to:
  - group: ""
    kind: Service
    name: inventory-svc
EOF

kubectl get httproute inventory-route -n edge-front -o yaml | grep -A20 status
```

Points worth remembering:

- The grant lives in the **target** namespace, never in the namespace making the reference. That is the whole security model: nobody can grant themselves access to somebody else's Service.
- `group: ""` is the core API group, which is how a `Service` is spelled here.
- `name` in the `to` block is optional; omitting it grants access to every Service in the namespace. Naming it, as above, is the least privilege version.
- ReferenceGrant is still served as `v1beta1` in the standard channel, unlike Gateway and HTTPRoute which are `v1`.
- The same object governs cross namespace `certificateRefs` from a Gateway listener.

---

## Question 17: Repairing a broken Gateway API configuration

```bash
kubectl get gateway,httproute -n edge-broken
kubectl describe gateway shop-gw -n edge-broken
kubectl describe httproute shop-route -n edge-broken
kubectl get gatewayclass
kubectl get svc shop-svc -n edge-broken
```

Three separate faults, each visible in a status condition:

1. The Gateway names `gatewayClassName: helioscale-edge`, and no such GatewayClass exists — `kubectl get gatewayclass` lists only `traefik`. No controller claims the Gateway, so it sits at `Accepted=False`, reason `InvalidParameters` / `Pending`, and is never programmed.
2. The listener serves `shop.helioscale.io` while the route declares `store.helioscale.io`. The hostnames do not intersect, so the route is refused with `NoMatchingListenerHostname`.
3. The route's `backendRef` targets `shop-svc` on port `8080`, but the Service exposes port `80`. That leaves `ResolvedRefs=False`.

Fix all three without touching the Deployment or the Service:

```bash
kubectl patch gateway shop-gw -n edge-broken --type=json -p '[
  {"op": "replace", "path": "/spec/gatewayClassName", "value": "traefik"}
]'

kubectl patch httproute shop-route -n edge-broken --type=json -p '[
  {"op": "replace", "path": "/spec/hostnames/0", "value": "shop.helioscale.io"},
  {"op": "replace", "path": "/spec/rules/0/backendRefs/0/port", "value": 80}
]'

kubectl get gateway shop-gw -n edge-broken
kubectl get httproute shop-route -n edge-broken -o yaml | grep -A20 status
```

`spec.gatewayClassName` is immutable in some implementations; if the patch is rejected, delete and recreate the Gateway with the same name and listener rather than editing the workload.

The general lesson is that the Gateway API pushes almost every failure into status conditions rather than into the logs: `Accepted` answers "did a controller take this object", `Programmed` answers "is the data plane actually serving it", and `ResolvedRefs` answers "do the things it points at exist and am I allowed to use them". Reading those three on both the Gateway and the route localises nearly every problem before you look anywhere else.
