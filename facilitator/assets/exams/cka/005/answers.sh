#!/bin/bash
# answers.md converted to answers.sh for quick testing of the cka-005 lab.
# Run it on the exam jumphost with KUBECONFIG pointing at the exam cluster.

echo "Implementing Question 1: rebind the ledger claim to a storage class that exists"
kubectl scale deployment ledger-api -n store-data --replicas=0
kubectl wait --for=delete pod -l app=ledger-api -n store-data --timeout=120s
kubectl delete pvc ledger-data -n store-data --timeout=120s
cat <<'EOF' | kubectl apply -f -
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
kubectl rollout status deployment/ledger-api -n store-data --timeout=180s

echo "Implementing Question 2: retained archive tier"
cat <<'EOF' | kubectl apply -f -
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
kubectl wait --for=condition=Ready pod/archive-writer -n store-tier --timeout=180s

echo "Implementing Question 3: three reports on the insight namespace"
mkdir -p /tmp/exam/q3
kubectl get pods -n insight --sort-by=.status.containerStatuses[0].restartCount \
    -o custom-columns=NAME:.metadata.name --no-headers | tail -1 > /tmp/exam/q3/restarts.txt
kubectl get nodes --no-headers \
    -o custom-columns='NAME:.metadata.name,IP:.status.addresses[?(@.type=="InternalIP")].address' \
    | sort > /tmp/exam/q3/nodes.txt
kubectl get pods -n insight -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
    | sort -u > /tmp/exam/q3/images.txt

echo "Implementing Question 4: container and memory limit audit"
mkdir -p /tmp/exam/q4
: > /tmp/exam/q4/report.txt
for pod in $(kubectl get pods -n registry-audit -o jsonpath='{.items[*].metadata.name}'); do
    kubectl get pod "$pod" -n registry-audit \
        -o jsonpath="{range .spec.containers[*]}$pod,{.name},{.image}{'\n'}{end}" >> /tmp/exam/q4/report.txt
done
sort -o /tmp/exam/q4/report.txt /tmp/exam/q4/report.txt
kubectl get pods -n registry-audit -o json \
    | jq -r '.items[] | select(any(.spec.containers[]; (.resources.limits.memory // "") == "")) | .metadata.name' \
    | sort -u > /tmp/exam/q4/no-limits.txt

echo "Implementing Question 5: storefront autoscaler"
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 6: give the render worker the requests its autoscaler needs"
kubectl set resources deployment render-worker -n scale-batch --containers=worker \
    --requests=cpu=100m,memory=64Mi --limits=cpu=500m,memory=256Mi
kubectl rollout status deployment/render-worker -n scale-batch --timeout=180s

echo "Implementing Question 7: payments ingress policy"
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 8: let the restricted frontend reach kube-dns again"
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 9: namespaced read only access for the reporting job"
kubectl create serviceaccount report-runner -n rbac-app
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 10: on-call debugging and cluster inventory"
kubectl create serviceaccount oncall -n rbac-ops
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 11: point the binding at the ServiceAccount that actually runs"
kubectl patch rolebinding sync-agent-binding -n rbac-broken --type=json \
    -p '[{"op": "replace", "path": "/subjects/0/namespace", "value": "rbac-broken"}]'

echo "Implementing Question 12: install and upgrade podinfo from the public repository"
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update podinfo
helm install podinfo podinfo/podinfo -n helm-pub \
    --set replicaCount=2 --set ui.message="helioscale edge" --wait --timeout 5m
helm upgrade podinfo podinfo/podinfo -n helm-pub \
    --reuse-values --set replicaCount=4 --wait --timeout 5m

echo "Implementing Question 13: unquote the replica count and install the chart"
sed -i 's/{{ .Values.replicaCount | quote }}/{{ .Values.replicaCount }}/' \
    /tmp/exam/q13/orderbook/templates/deployment.yaml
helm uninstall orderbook -n helm-broken 2>/dev/null || true
helm install orderbook /tmp/exam/q13/orderbook -n helm-broken --wait --timeout 5m

echo "Implementing Question 14: production overlay"
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
kubectl apply -k /tmp/exam/q14/overlays/prod
kubectl rollout status deployment/prod-web -n kustom-app --timeout=180s

echo "Implementing Question 15: repair the staging overlay and render it"
sed -i 's/name: api-server/name: api/' \
    /tmp/exam/q15/overlays/staging/replicas-patch.yaml \
    /tmp/exam/q15/overlays/staging/kustomization.yaml
kubectl kustomize /tmp/exam/q15/overlays/staging > /tmp/exam/q15/rendered.yaml

echo "Implementing Question 16: the shop Gateway and its route"
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 17: open the shared Gateway to the application namespace"
kubectl patch gateway platform-gw -n edge-platform --type=json -p '[
  {"op": "replace", "path": "/spec/listeners/0/allowedRoutes/namespaces", "value":
    {"from": "Selector", "selector": {"matchLabels": {"gateway-access": "allowed"}}}}
]'
kubectl label namespace edge-team gateway-access=allowed --overwrite
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 18: attach the catalog route to the listener that exists"
kubectl patch httproute catalog-route -n edge-stuck --type=json -p '[
  {"op": "replace", "path": "/spec/parentRefs/0/sectionName", "value": "public"},
  {"op": "replace", "path": "/spec/hostnames/0", "value": "catalog.helioscale.io"}
]'

echo "All answers applied"
