# CKA Practice Lab 008 — Answers

Every solution below is written for the exam jumphost (`ckad9999`), where `kubectl` already points at the exam cluster.

This lab is entirely about NetworkPolicy. Twelve questions in ninety minutes, rising from a single default-deny to a whole namespace designed from a requirements matrix. The work per question is small; the difficulty is in reading a policy and knowing precisely what it does and does not select.

Three of the twelve questions (9, 10 and 11) start from a cluster that is already broken. Each of those answers opens with the commands that find the fault before it shows the fix — on the real exam nobody tells you what is broken, and the diagnosis is most of the work.

Two habits are worth building before you start:

```bash
# Read a policy as a whole. 'describe' renders the selectors in prose and is far
# quicker to scan than the YAML.
kubectl describe networkpolicy <name> -n <namespace>

# Test reachability from the Pods the question is actually about. busybox images
# have wget; the stock nginx image has neither wget nor curl, but it is Debian,
# so bash's /dev/tcp works.
kubectl exec <busybox-pod> -n <ns> -- wget -q -T 5 -t 1 -O- http://<ip>:<port>
kubectl exec <nginx-pod>   -n <ns> -- timeout 5 bash -c "echo > /dev/tcp/<host>/<port>"
```

Four traps that catch people all lab long:

- **A `from`/`to` entry with two selector keys means AND; two entries mean OR.** This one line of YAML is the difference between "Pods labelled `app=x` in namespaces labelled `y`" and "any Pod in those namespaces, or any Pod labelled `app=x` anywhere". Whether the second `-` is there decides which you wrote.
- **An empty selector is not an empty set.** `podSelector: {}` selects *every* Pod in the namespace, and `namespaceSelector: {}` selects *every* namespace. A policy that selects nothing is written by naming a label that does not exist — and it is admitted without complaint and enforces nothing.
- **`policyTypes` is what denies.** A Pod is isolated for a direction the moment any policy selecting it lists that direction in `policyTypes`. The rules only add exceptions back; there is no deny rule and no ordering.
- **Policies are additive.** Two policies selecting the same Pod produce the union of their allowances. You never edit someone else's policy to widen access — you add your own.

One environment note that will save you a confusing ten minutes. `/etc/resolv.conf` in a Pod sets `ndots:5`, and a name like `catalog.np-egress.svc.cluster.local` has only four dots — so both resolvers here treat it as *relative* and walk the `search` list before trying it as written. busybox's `wget` does this too, even though busybox's `nslookup` does not. If the cluster's nodes inherited a search domain that answers wildcards, a cluster name can come back as a public address:

```bash
kubectl exec web -n np-design -- getent hosts api.np-design.svc.cluster.local
# 2600:1f18:4ae:c605:...  api.np-design.svc.cluster.local.example.com     <-- not your Service

kubectl exec web -n np-design -- getent hosts api.np-design.svc.cluster.local.
# 10.43.71.27  api.np-design.svc.cluster.local                            <-- the trailing dot fixes it
```

A trailing dot makes the name absolute and skips the search list. Use it whenever a name-based test gives an answer that surprises you — and note that `nslookup` from a busybox Pod queries the name exactly as typed, which is why it disagrees with `wget` in the same container.

---

## Question 1: A default-deny for ingress

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: np-baseline
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
```

The whole policy is three meaningful lines, and two of them are about what is *absent*. `podSelector: {}` matches every Pod in the namespace. `policyTypes: [Ingress]` isolates those Pods for incoming traffic. And there is no `ingress:` key at all, so nothing is allowed back in.

Verify with:

```bash
WEB=$(kubectl get pod web -n np-baseline -o jsonpath='{.status.podIP}')
kubectl exec client -n np-baseline -- wget -q -T 5 -t 1 -O- http://$WEB:80; echo $?   # non-zero
```

**Common traps**

- Adding `ingress: []` is harmless and equivalent, but adding `ingress: [{}]` is the opposite of what you want: a rule with no `from` and no `ports` permits everything.
- Listing `Egress` in `policyTypes` as well would also cut off outbound traffic, including DNS, which is not what was asked.
- A default-deny only covers the namespace it is created in. There is no cluster-scoped NetworkPolicy.

---

## Question 2: Allowing one client on one port

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-frontend
  namespace: np-tiers
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 80
EOF
```

The `default-deny` that was already in the namespace is doing the denying. This policy adds one exception on top of it: the two are unioned, so `frontend` gets through and everything else stays blocked. Note that `api-allow-frontend` would isolate `app=api` on its own even if `default-deny` were removed — the moment any policy selects a Pod for `Ingress`, that Pod accepts only what some policy explicitly allows.

Verify with:

```bash
API=$(kubectl get pod api -n np-tiers -o jsonpath='{.status.podIP}')
kubectl exec frontend -n np-tiers -- wget -q -T 5 -t 1 -O- http://$API:80; echo $?   # 0
kubectl exec scanner  -n np-tiers -- wget -q -T 5 -t 1 -O- http://$API:80; echo $?   # non-zero
```

**Common traps**

- `podSelector` at the top of `spec` chooses whom the policy *protects*; the one under `from` chooses whom it *admits*. Swapping them is the single most common NetworkPolicy mistake.
- Omitting `ports` allows `role=frontend` on every port, not just 80.

---

## Question 3: Admitting a whole namespace

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payments-ingress
  namespace: np-crossns
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
          purpose: monitoring
    ports:
    - protocol: TCP
      port: 80
EOF
```

A `podSelector` can only ever name Pods in the policy's own namespace, so a client next door is unreachable by that route. `namespaceSelector` matches on the labels of the *Namespace object*, which is why `np-crossns-monitor` had to be labelled `purpose=monitoring` for this to work and why `np-crossns-dev`, which carries no labels of its own, is left out.

Verify with:

```bash
kubectl get namespace --show-labels | grep np-crossns
PAY=$(kubectl get pod payments -n np-crossns -o jsonpath='{.status.podIP}')
kubectl exec probe -n np-crossns-monitor -- wget -q -T 5 -t 1 -O- http://$PAY:80; echo $?  # 0
kubectl exec probe -n np-crossns-dev     -- wget -q -T 5 -t 1 -O- http://$PAY:80; echo $?  # non-zero
```

**Common traps**

- `namespaceSelector: {}` matches every namespace in the cluster, which is the exact opposite of a restriction. To name one namespace with no label of your own, use the label the API server maintains on every namespace: `kubernetes.io/metadata.name: np-crossns-monitor`.
- Adding a `namespaceSelector` does *not* keep admitting Pods from the policy's own namespace. Once `payments` is isolated, local Pods need their own entry too — which is why nothing else in `np-crossns` can reach it either.

---

## Question 4: Namespace and Pod, in one peer

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ledger-ingress
  namespace: np-combined
spec:
  podSelector:
    matchLabels:
      app: ledger
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tier: platform
      podSelector:
        matchLabels:
          app: collector
    ports:
    - protocol: TCP
      port: 80
EOF
```

Everything hangs on the indentation. `namespaceSelector` and `podSelector` are two keys of **one** list entry — there is a single `-` — so a connection has to satisfy both: it must come from a Pod labelled `app=collector` *and* that Pod must live in a namespace labelled `tier=platform`.

Write it with a second `-`:

```yaml
    - namespaceSelector:
        matchLabels:
          tier: platform
    - podSelector:                 # <-- a second entry: this is now OR
        matchLabels:
          app: collector
```

and you have said "any Pod in a `tier=platform` namespace, **or** any Pod labelled `app=collector` in `np-combined` itself". The lab stages all three combinations deliberately, so this mistake shows up as `auditor` and the edge `collector` both getting through.

Verify with:

```bash
LED=$(kubectl get pod ledger -n np-combined -o jsonpath='{.status.podIP}')
kubectl exec collector -n np-combined-platform -- wget -q -T 5 -t 1 -O- http://$LED:80; echo $?  # 0
kubectl exec auditor   -n np-combined-platform -- wget -q -T 5 -t 1 -O- http://$LED:80; echo $?  # non-zero
kubectl exec collector -n np-combined-edge     -- wget -q -T 5 -t 1 -O- http://$LED:80; echo $?  # non-zero
```

**Common traps**

- `kubectl describe networkpolicy` renders the AND form as a single `From` bullet listing both selectors, and the OR form as two bullets. That is the fastest way to check which one you actually wrote.
- The `podSelector` inside a peer is evaluated against the namespaces the `namespaceSelector` chose — not against the policy's own namespace.

---

## Question 5: Restricting egress, without breaking DNS

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: orders-egress
  namespace: np-egress
spec:
  podSelector:
    matchLabels:
      app: orders
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: catalog
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

The second rule is the one people forget. The instant `orders` is isolated for egress, its DNS queries stop leaving the Pod, and every attempt to reach `catalog` **by name** fails during resolution — long before any policy about port 80 is consulted. Reaching it by IP would still work, which is the classic misleading symptom: "it works with an address but not with a name".

CoreDNS runs in `kube-system` with the Pod label `k8s-app=kube-dns`. Both selectors are again keys of one entry, so this permits exactly the DNS Pods and not the whole of `kube-system`. Both protocols are needed: UDP carries nearly every query, but resolvers fall back to TCP for responses that do not fit, so a UDP-only policy fails rarely and confusingly rather than outright.

Verify with:

```bash
kubectl exec orders -n np-egress -- nslookup catalog.np-egress.svc.cluster.local
kubectl exec orders -n np-egress -- wget -q -T 5 -t 1 -O- http://catalog.np-egress.svc.cluster.local:80; echo $?  # 0
REP=$(kubectl get pod reports -n np-egress -o jsonpath='{.status.podIP}')
kubectl exec orders -n np-egress -- wget -q -T 5 -t 1 -O- http://$REP:80; echo $?                                 # non-zero
```

**Common traps**

- Egress rules are evaluated against the *destination Pod*, so the port in the rule is the port on `catalog`, not a source port.
- `nslookup` in busybox ignores the `search` list in `/etc/resolv.conf` and queries the name exactly as typed, so `nslookup catalog` answers `NXDOMAIN` even when DNS is perfectly healthy. Always use the FQDN when testing from a busybox Pod.
- A rule with an empty `to` and empty `ports` — `egress: [{}]` — permits all outbound traffic and defeats the point.

---

## Question 6: ipBlock, and what `except` is for

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gateway-egress
  namespace: np-external
spec:
  podSelector:
    matchLabels:
      app: gateway
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.42.0.0/16
        - 169.254.169.254/32
    ports:
    - protocol: TCP
      port: 443
EOF
```

`ipBlock` is the only peer type that talks about addresses rather than about Kubernetes objects, and it is the only way to express "the internet, but not these bits of it". `except` is a property of the `cidr` it sits under — it carves holes in that one block, and it is only valid for addresses inside it.

Excluding `10.42.0.0/16` is what stops "allow the internet" from quietly meaning "allow every Pod in the cluster too": Pod IPs come out of that range, and `0.0.0.0/0` contains them. `169.254.169.254/32` is the cloud instance metadata endpoint, historically a rich source of credentials for anything that can reach it.

Verify with:

```bash
kubectl get networkpolicy gateway-egress -n np-external -o jsonpath='{.spec.egress[0].to[0].ipBlock}' | jq .
```

**Common traps**

- Putting the exclusions in a second rule does nothing. Rules are unioned, so an extra `to: [{ipBlock: {cidr: 0.0.0.0/0}}]` re-admits exactly the addresses the first rule excluded. The whole requirement has to live in one rule.
- `except` entries must be subnets of the `cidr` above them; the API server rejects anything else.
- `ipBlock` matches on addresses only. It cannot express "this Pod", and it does not follow a Pod when it is rescheduled and gets a new IP.
- `ipBlock` never combines with a selector in the same peer — an entry holds either an `ipBlock` or Pod/namespace selectors, never both.

---

## Question 7: Two policies on one Pod

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backup
  namespace: np-additive
spec:
  podSelector:
    matchLabels:
      app: reports
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: backup
    ports:
    - protocol: TCP
      port: 80
EOF
```

NetworkPolicies do not conflict and do not override one another. When several select the same Pod, that Pod accepts the **union** of everything they permit. So the way to widen access to `reports` is to add a policy, not to edit the one that is already there — which matters in the real world, where `allow-frontend` belongs to another team and is probably managed from their Git repository.

Notice what this question is *not*: there is no ordering, no priority field, and no way to write a deny. If you ever need to subtract access, you change the policy that grants it.

Verify with:

```bash
kubectl get networkpolicy -n np-additive
REP=$(kubectl get pod reports -n np-additive -o jsonpath='{.status.podIP}')
kubectl exec backup   -n np-additive -- wget -q -T 5 -t 1 -O- http://$REP:80; echo $?   # 0
kubectl exec frontend -n np-additive -- wget -q -T 5 -t 1 -O- http://$REP:80; echo $?   # 0
```

**Common traps**

- Editing `allow-frontend` to add a second `from` peer also works technically, and is exactly what the question forbids — it is graded.
- The new policy must select `app=reports` too. Selecting `role=backup` instead would isolate the *client*, which is a different statement entirely and grants nothing.

---

## Question 8: Two ports, two audiences

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payments-ingress
  namespace: np-ports
spec:
  podSelector:
    matchLabels:
      app: payments
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchExpressions:
        - key: role
          operator: In
          values:
          - frontend
          - monitoring
    ports:
    - protocol: TCP
      port: 80
  - from:
    - podSelector:
        matchLabels:
          role: monitoring
    ports:
    - protocol: TCP
      port: 9090
EOF
```

Two separate ingress rules, because the two audiences are different. Within one rule the `from` list and the `ports` list are combined with AND — every listed peer may use every listed port — so putting 80 and 9090 in the same rule would hand `frontend` the metrics endpoint as well.

`matchExpressions` is the set-based form of a selector and is available anywhere `matchLabels` is. `In` with two values replaces two peers; the others are `NotIn`, `Exists` (the key is present, whatever its value) and `DoesNotExist`. `matchLabels` and `matchExpressions` in the same selector are ANDed together.

Verify with:

```bash
PAY=$(kubectl get pod payments -n np-ports -o jsonpath='{.status.podIP}')
kubectl exec frontend   -n np-ports -- wget -q -T 5 -t 1 -O- http://$PAY:80;   echo $?   # 0
kubectl exec frontend   -n np-ports -- wget -q -T 5 -t 1 -O- http://$PAY:9090; echo $?   # non-zero
kubectl exec prometheus -n np-ports -- wget -q -T 5 -t 1 -O- http://$PAY:9090; echo $?   # 0
kubectl exec batch      -n np-ports -- wget -q -T 5 -t 1 -O- http://$PAY:80;   echo $?   # non-zero
```

**Common traps**

- `values` is a list even for `In` with a single entry, and must be omitted entirely for `Exists` and `DoesNotExist`.
- `ports.port` also accepts the *name* of a container port (`http`, `metrics`) rather than a number, and `endPort` turns a rule into a range. Both are part of the API, but support varies between CNI plugins — prefer numbers when you need to be certain, and know the syntax exists when you read someone else's policy.
- A rule with `ports` but no `from` allows that port from *everywhere*.

---

## Question 9: checkout cannot reach inventory

Start by reading what the policy actually says, rather than what it was meant to say:

```bash
kubectl describe networkpolicy inventory-ingress -n np-ts-selector
kubectl get namespace np-ts-selector-clients --show-labels
kubectl get pod -n np-ts-selector-clients --show-labels
```

`describe` prints the `From` section as **two** bullets, which is the first thing to notice — the peer was written as two list entries, so it means OR, not AND. Reading them one at a time: the first admits namespaces labelled `access=inventory-clients`, and `kubectl get namespace --show-labels` shows the clients namespace is labelled `access=inventory`, so that entry matches no namespace at all. The second admits Pods labelled `app=checkout` — but a bare `podSelector` only ever refers to the policy's *own* namespace, and there are no such Pods in `np-ts-selector`. Both entries match nothing, so nothing reaches `inventory`.

The fix is one rule with one peer holding both selectors, and the label value corrected:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: inventory-ingress
  namespace: np-ts-selector
spec:
  podSelector:
    matchLabels:
      app: inventory
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          access: inventory
      podSelector:
        matchLabels:
          app: checkout
    ports:
    - protocol: TCP
      port: 80
EOF
```

Simply deleting the broken `podSelector` entry and fixing the namespace label would also make `checkout` work — and it is wrong. It admits the whole clients namespace, `scanner` included, and `scanner` is precisely the Pod the question says must never get in. It is the repair that looks finished and quietly widens the blast radius; both halves are graded.

Verify with:

```bash
INV=$(kubectl get pod inventory -n np-ts-selector -o jsonpath='{.status.podIP}')
CO=$(kubectl get pod -n np-ts-selector-clients -l app=checkout -o jsonpath='{.items[0].metadata.name}')
kubectl exec $CO      -n np-ts-selector-clients -- wget -q -T 5 -t 1 -O- http://$INV:80; echo $?  # 0
kubectl exec scanner  -n np-ts-selector-clients -- wget -q -T 5 -t 1 -O- http://$INV:80; echo $?  # non-zero
```

---

## Question 10: A policy that enforces nothing

The symptom is the inverse of the usual one — traffic that should be blocked is flowing — so the question is not "what does this rule allow" but "does this policy apply to anything at all":

```bash
kubectl get networkpolicy vault-isolation -n np-ts-inert -o yaml
kubectl get pod -n np-ts-inert --show-labels
```

```
spec:
  podSelector:
    matchLabels:
      app: vault-server
```
```
NAME       READY   STATUS    LABELS
vault      1/1     Running   app=vault
auditor    1/1     Running   role=auditor
intruder   1/1     Running   role=intruder
```

The policy's `podSelector` names `app=vault-server`; the Pod is labelled `app=vault`. The policy selects zero Pods, so it isolates zero Pods. Nothing rejected it — a NetworkPolicy that matches nothing is perfectly valid YAML and a perfectly valid object, and `kubectl get` shows it sitting there looking authoritative. `kubectl describe` is more honest about it, printing `Allowing ingress traffic ... to Pods with labels app=vault-server` next to a namespace containing none.

The fix is to make the selector match:

```bash
kubectl patch networkpolicy vault-isolation -n np-ts-inert \
  --type merge -p '{"spec":{"podSelector":{"matchLabels":{"app":"vault"}}}}'
```

Relabelling the Pod to `app=vault-server` would also silence the symptom, and would break the `vault` Service at the same time — its selector still says `app=vault`, so it would lose its only endpoint and the Pod would become unreachable by name. When a selector and a label disagree, change whichever one has no other dependents; here that is the policy.

Verify with:

```bash
kubectl describe networkpolicy vault-isolation -n np-ts-inert
kubectl get endpoints vault -n np-ts-inert
VAULT=$(kubectl get pod vault -n np-ts-inert -o jsonpath='{.status.podIP}')
kubectl exec auditor  -n np-ts-inert -- wget -q -T 5 -t 1 -O- http://$VAULT:80; echo $?   # 0
kubectl exec intruder -n np-ts-inert -- wget -q -T 5 -t 1 -O- http://$VAULT:80; echo $?   # non-zero
```

---

## Question 11: The other end of the connection

The obvious suspect is the policy in front of `archive`, so rule it out first:

```bash
kubectl describe networkpolicy archive-ingress -n np-ts-egress-store
kubectl get networkpolicy -A
```

`archive-ingress` admits the whole `np-ts-egress` namespace on TCP 80 — it is correct, and nothing in the store namespace explains the failure. The second command is the one that finds the fault: there is a `default-deny-egress` in `np-ts-egress` itself, selecting every Pod with `policyTypes: [Egress]` and no rules. `sync-agent` is not being refused at the far end; its packets are never leaving.

A connection has to be permitted by **both** ends: the client's egress rules and the server's ingress rules. Either one being silent is enough to break it, and only one of them is mentioned in the symptom.

Add the client-side allowances — DNS, because the target is addressed by name, and the archive namespace on port 80:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: sync-agent-egress
  namespace: np-ts-egress
spec:
  podSelector:
    matchLabels:
      app: sync-agent
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          role: store
      podSelector:
        matchLabels:
          app: archive
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

A second policy is enough — egress allowances union with the existing default-deny, exactly as in question 7 — so `default-deny-egress` can be left alone. Editing it to add the same two rules works equally well.

What does not work is reaching for the blunt instrument. `egress: [{}]`, or a rule naming `0.0.0.0/0`, makes `archive` reachable and makes `np-ts-egress-decoy` reachable with it, which the question rules out and the grading checks.

Verify with:

```bash
kubectl exec sync-agent -n np-ts-egress -- wget -q -T 5 -t 1 -O- \
  http://archive.np-ts-egress-store.svc.cluster.local:80; echo $?    # 0
DEC=$(kubectl get pod secrets-api -n np-ts-egress-decoy -o jsonpath='{.status.podIP}')
kubectl exec sync-agent -n np-ts-egress -- wget -q -T 5 -t 1 -O- http://$DEC:80; echo $?  # non-zero
```

---

## Question 12: Designing the whole namespace

Four policies: one that shuts the namespace down in both directions, and one per tier granting exactly what the matrix allows.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: np-design
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-tier
  namespace: np-design
spec:
  podSelector:
    matchLabels:
      tier: web
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          role: edge
      podSelector:
        matchLabels:
          role: gateway
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - protocol: TCP
      port: 8080
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
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-tier
  namespace: np-design
spec:
  podSelector:
    matchLabels:
      tier: api
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: web
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: db
    ports:
    - protocol: TCP
      port: 5432
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
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-tier
  namespace: np-design
spec:
  podSelector:
    matchLabels:
      tier: db
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - protocol: TCP
      port: 5432
  egress:
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

Read the matrix twice, once per direction, and the shape falls out. For each ordered pair that must work, *two* things have to be true: the source tier needs an egress rule to the destination, and the destination tier needs an ingress rule from the source. `web → api` therefore appears in both `web-tier.egress` and `api-tier.ingress`, and a design that writes only one half fails.

The denials are then free. `web → db` is refused because `db-tier` admits only `tier=api`, and separately because `web-tier` has no egress rule pointing at the db tier — belt and braces, and either alone would do it. `ingress-gw → api` is refused because `api-tier` admits only `tier=web`. `rogue` is refused because `web-tier`'s ingress peer names the Pod label `role=gateway`, not just the namespace: `rogue` shares that namespace, so a namespace-only rule would let it straight in.

DNS has to be granted to all three tiers, because the whole namespace is isolated for egress and the tiers address each other by Service name. The `default-deny` at the top is not strictly required once each tier has its own policy — every Pod in the namespace is already selected by one — but it is worth keeping: it is what makes a fourth Pod added tomorrow start out closed rather than open.

Verify with:

```bash
kubectl exec ingress-gw -n np-design-clients -- wget -q -T 5 -t 1 -O- http://web.np-design.svc.cluster.local:80; echo $?
kubectl exec web -n np-design -- timeout 5 bash -c "echo > /dev/tcp/api.np-design.svc.cluster.local/8080"; echo $?
kubectl exec api -n np-design -- timeout 5 bash -c "echo > /dev/tcp/db.np-design.svc.cluster.local/5432";  echo $?

DB=$(kubectl get pod db  -n np-design -o jsonpath='{.status.podIP}')
API=$(kubectl get pod api -n np-design -o jsonpath='{.status.podIP}')
WEB=$(kubectl get pod web -n np-design -o jsonpath='{.status.podIP}')
kubectl exec web        -n np-design         -- timeout 5 bash -c "echo > /dev/tcp/$DB/5432"; echo $?   # non-zero
kubectl exec ingress-gw -n np-design-clients -- wget -q -T 5 -t 1 -O- http://$API:8080; echo $?         # non-zero
kubectl exec rogue      -n np-design-clients -- wget -q -T 5 -t 1 -O- http://$WEB:80;   echo $?         # non-zero
```

**Common traps**

- Granting only the ingress half. It is the more familiar direction and the one most examples show, and on an egress-isolated namespace it achieves nothing on its own.
- Forgetting DNS on the `db` tier because it never initiates a connection to another tier. It still resolves names, and an isolated Pod with no DNS rule has a broken resolver whether or not it uses it.
- Admitting `np-design-clients` by namespace rather than by the `role=gateway` Pod label, which hands `rogue` the same access as the gateway.
- Reaching for `ipBlock` to describe another Pod. Pod IPs are not stable and are not the right abstraction — and here it is explicitly disallowed.
