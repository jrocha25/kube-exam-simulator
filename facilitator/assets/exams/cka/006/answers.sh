#!/bin/bash
# answers.md converted to answers.sh for quick testing of the cka-006 lab.
# Run it on the exam jumphost with KUBECONFIG pointing at the exam cluster.
#
# Unlike the earlier labs' answer scripts this one also drives the cluster nodes
# over SSH, because five of the questions are answered on a node rather than
# through the API server.

set -u

CP=$(kubectl get nodes -l ck-x.io/alias=controlplane -o jsonpath='{.items[0].metadata.name}')
N1=$(kubectl get nodes -l ck-x.io/alias=node01 -o jsonpath='{.items[0].metadata.name}')
N2=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}')
N3=$(kubectl get nodes -l ck-x.io/alias=node03 -o jsonpath='{.items[0].metadata.name}')
echo "controlplane=$CP node01=$N1 node02=$N2 node03=$N3"

echo "== Question 1: repair the static Pod on node01 =="
ssh node01 "
  sed -i 's#/opt/probe-datta#/opt/probe-data#' /etc/kubernetes/manifests/node-probe.yaml
  sed -i 's#/etc/probe/probe.cfg#/etc/probe/probe.conf#' /etc/kubernetes/manifests/node-probe.yaml
  rmdir /opt/probe-datta 2>/dev/null || true
"

echo "== Question 2: give node01 its memory back =="
ssh node01 "
  sed -i '/^systemReserved:/,+2d' /var/lib/kubelet/config.yaml
  systemctl restart kubelet
"

echo "== Question 3: certificate-based user =="
mkdir -p /tmp/exam/q3
openssl genrsa -out /tmp/exam/q3/mira.key 2048 2>/dev/null
openssl req -new -key /tmp/exam/q3/mira.key -out /tmp/exam/q3/mira.csr -subj "/CN=mira/O=developers"
kubectl delete csr mira-access --ignore-not-found=true
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: mira-access
spec:
  request: $(base64 -w 0 /tmp/exam/q3/mira.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF
kubectl certificate approve mira-access
for i in $(seq 1 12); do
  CERT=$(kubectl get csr mira-access -o jsonpath='{.status.certificate}')
  [ -n "$CERT" ] && break
  sleep 5
done
kubectl get csr mira-access -o jsonpath='{.status.certificate}' | base64 -d > /tmp/exam/q3/mira.crt
kubectl create role dev-reader -n dev-team --verb=get,list,watch --resource=pods,pods/log \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create rolebinding mira-reader -n dev-team --role=dev-reader --user=mira \
  --dry-run=client -o yaml | kubectl apply -f -

echo "== Question 4: etcd snapshot =="
ssh controlplane '
  mkdir -p /opt/etcd-backup
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /opt/etcd-backup/snapshot.db
  if command -v etcdutl >/dev/null 2>&1; then
    etcdutl snapshot status /opt/etcd-backup/snapshot.db --write-out=json > /opt/etcd-backup/status.json
  else
    ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup/snapshot.db --write-out=json > /opt/etcd-backup/status.json
  fi
'

echo "== Question 5: drain and uncordon node02 =="
mkdir -p /tmp/exam/q5
kubectl get pods -n node-maint -l app=shop-web --field-selector "spec.nodeName=$N2" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep . > /tmp/exam/q5/drained.txt
kubectl drain "$N2" --ignore-daemonsets --delete-emptydir-data --timeout=180s
kubectl uncordon "$N2"

echo "== Question 6: harden the API server =="
ssh controlplane '
  M=/etc/kubernetes/manifests/kube-apiserver.yaml
  cp "$M" /root/kube-apiserver.yaml.bak
  sed -i "/- kube-apiserver/a\\    - --tls-min-version=VersionTLS12\n    - --tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256" "$M"
'
echo "waiting for the API server to come back..."
for i in $(seq 1 36); do
  kubectl get --raw /readyz >/dev/null 2>&1 && break
  sleep 5
done

echo "== Question 7: fix the checkout Service selector =="
kubectl patch svc checkout -n svc-orders -p '{"spec":{"selector":{"app":"checkout-api"}}}'

echo "== Question 8: restore cluster DNS =="
kubectl patch svc kube-dns -n kube-system -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'
mkdir -p /tmp/exam/q8
for i in $(seq 1 12); do
  if kubectl exec -n dns-check ticker -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then break; fi
  sleep 5
done
kubectl exec -n dns-check ticker -- nslookup kubernetes.default.svc.cluster.local > /tmp/exam/q8/lookup.txt

echo "== Question 9: orders-lockdown NetworkPolicy =="
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

echo "== Question 10: point billing-egress at the invoice pods =="
kubectl patch networkpolicy billing-egress -n net-billing --type=json \
  -p '[{"op":"replace","path":"/spec/egress/0/to/0/podSelector/matchLabels/app","value":"invoice"}]'

echo "== Question 11: three Services =="
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

echo "== Question 12: kustomize base and production overlay =="
mkdir -p /tmp/exam/q12/base /tmp/exam/q12/overlays/production
cat > /tmp/exam/q12/base/deployment.yaml <<'EOF'
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
cat > /tmp/exam/q12/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
EOF
cat > /tmp/exam/q12/overlays/production/kustomization.yaml <<'EOF'
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
kubectl apply -k /tmp/exam/q12/overlays/production
kubectl kustomize /tmp/exam/q12/overlays/production > /tmp/exam/q12/rendered.yaml

echo "== Question 13: patches and a generated Secret =="
cat > /tmp/exam/q13/overlays/staging/log-level-patch.yaml <<'EOF'
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
cat > /tmp/exam/q13/overlays/staging/replicas-patch.yaml <<'EOF'
- op: replace
  path: /spec/replicas
  value: 3
EOF
cat > /tmp/exam/q13/overlays/staging/kustomization.yaml <<'EOF'
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
kubectl apply -k /tmp/exam/q13/overlays/staging

echo "== Question 14: repair the staging overlay (render only) =="
cd /tmp/exam/q14/overlays/staging
sed -i 's#^- \.\./base#- ../../base#' kustomization.yaml
sed -i 's/kind: StatefulSet/kind: Deployment/' replica-patch.yaml
grep -q '^images:' kustomization.yaml || cat >> kustomization.yaml <<'EOF'
images:
- name: nginx
  newTag: 1.27.4
EOF
kubectl kustomize /tmp/exam/q14/overlays/staging > /tmp/exam/q14/rendered.yaml
cd /home/candidate

echo "== Question 15: immutable ConfigMap and Secret =="
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: audit-config
  namespace: compliance
immutable: true
data:
  MIN_TLS_VERSION: "1.2"
  AUDIT_MODE: "enabled"
---
apiVersion: v1
kind: Secret
metadata:
  name: audit-keys
  namespace: compliance
type: Opaque
immutable: true
stringData:
  SIGNING_KEY: "r7-audit-2026"
EOF

echo "== Question 16: rotate onto a new immutable ConfigMap =="
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
kubectl patch deployment feature-api -n config-rotate --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/envFrom/0/configMapRef/name","value":"feature-flags-v2"}]'
kubectl rollout status deployment/feature-api -n config-rotate --timeout=180s

echo "== Question 17: reserve node02 =="
kubectl taint node "$N2" workload=latency:NoSchedule --overwrite
kubectl label node "$N2" tier=realtime --overwrite
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

echo "== Question 18: priority and preemption =="
kubectl create priorityclass batch-low --value=10000 --dry-run=client -o yaml | kubectl apply -f -
kubectl create priorityclass critical-high --value=100000 --dry-run=client -o yaml | kubectl apply -f -
kubectl patch deployment bulk-import -n sched-priority \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"batch-low"}}}}'
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

echo
echo "== settling =="
for d in "sched-batch batch-runner" "kustom-prod prod-trade-app" "kustom-stage api" \
         "sched-pin quote-engine" "sched-priority market-feed" "node-maint shop-web"; do
  set -- $d
  kubectl rollout status "deployment/$2" -n "$1" --timeout=240s || echo "  (still settling: $1/$2)"
done

echo
echo "All answers applied."
