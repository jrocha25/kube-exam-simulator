#!/bin/bash
# answers.md converted to answers.sh for quick testing of the cka-008 lab.
# Run it on the exam jumphost with KUBECONFIG pointing at the exam cluster.
set -x

### Question 1 -- a default-deny for ingress
cat <<'EOF' | kubectl apply -f -
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

### Question 2 -- allowing one client on one port
cat <<'EOF' | kubectl apply -f -
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

### Question 3 -- admitting a whole namespace
cat <<'EOF' | kubectl apply -f -
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

### Question 4 -- namespace and pod, in one peer
cat <<'EOF' | kubectl apply -f -
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

### Question 5 -- restricting egress without breaking dns
cat <<'EOF' | kubectl apply -f -
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

### Question 6 -- ipblock and except
cat <<'EOF' | kubectl apply -f -
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

### Question 7 -- two policies on one pod
cat <<'EOF' | kubectl apply -f -
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

### Question 8 -- two ports, two audiences
cat <<'EOF' | kubectl apply -f -
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

### Question 9 -- checkout cannot reach inventory
kubectl describe networkpolicy inventory-ingress -n np-ts-selector
kubectl get namespace np-ts-selector-clients --show-labels
cat <<'EOF' | kubectl apply -f -
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

### Question 10 -- a policy that enforces nothing
kubectl get networkpolicy vault-isolation -n np-ts-inert -o yaml
kubectl get pod -n np-ts-inert --show-labels
kubectl patch networkpolicy vault-isolation -n np-ts-inert \
  --type merge -p '{"spec":{"podSelector":{"matchLabels":{"app":"vault"}}}}'

### Question 11 -- the other end of the connection
kubectl describe networkpolicy archive-ingress -n np-ts-egress-store
kubectl get networkpolicy -A
cat <<'EOF' | kubectl apply -f -
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

### Question 12 -- designing the whole namespace
cat <<'EOF' | kubectl apply -f -
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
