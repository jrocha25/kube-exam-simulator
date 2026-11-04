#!/bin/bash
# answers.md converted to answers.sh for quick testing of the cka-004 lab.
# Run it on the exam jumphost with KUBECONFIG pointing at the exam cluster.

echo "Implementing Question 1: reuse the released PersistentVolume"
kubectl patch pv archive-pv --type=json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
cat <<'EOF' | kubectl apply -f -
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
sed -i 's/claimName: ""/claimName: archive-pvc/' /tmp/exam/q1/archive-deploy.yaml
kubectl apply -f /tmp/exam/q1/archive-deploy.yaml

echo "Implementing Question 2: scale and roll out media-api"
kubectl annotate deployment media-api -n media \
  kubernetes.io/change-cause="image update to nginx 1.27.4" --overwrite
kubectl scale deployment media-api -n media --replicas=4
kubectl set image deployment/media-api api=nginx:1.27.4 -n media

echo "Implementing Question 3: right size the report-builder requests"
kubectl patch deployment report-builder -n analytics --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "200m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "256Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "500m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"}
]'

echo "Implementing Question 4: HorizontalPodAutoscaler"
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 5: report the busiest Pod"
mkdir -p /tmp/exam/q5
HOG_POD=$(kubectl get pods -n loadgen -l app=cpu-hog -o jsonpath='{.items[0].metadata.name}')
echo "loadgen/$HOG_POD" > /tmp/exam/q5/top-pod.txt
kubectl get pod "$HOG_POD" -n loadgen -o jsonpath='{.spec.nodeName}' > /tmp/exam/q5/top-node.txt

echo "Implementing Question 6: apply the least permissive NetworkPolicy"
kubectl apply -f /tmp/exam/q6/policies/policy-b.yaml

echo "Implementing Question 7: RBAC for the delivery pipeline"
kubectl create serviceaccount pipeline-bot -n delivery
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 8: native sidecar for shipment-tracker"
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

echo "Implementing Question 9: PriorityClass for edge-proxy"
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 10: install, upgrade and roll back the local chart"
helm install web-edge /tmp/exam/q10/helioscale-web -n edge-helm --set replicaCount=3
helm upgrade web-edge /tmp/exam/q10/helioscale-web -n edge-helm --set replicaCount=5 --set image.tag=1.28.0
helm rollback web-edge 1 -n edge-helm

echo "Implementing Question 11: first Gateway and HTTPRoute"
mkdir -p /tmp/exam/q11
kubectl get gatewayclass traefik -o jsonpath='{.spec.controllerName}' > /tmp/exam/q11/gatewayclass.txt
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 12: migrate the legacy Ingress to an HTTPRoute"
cat <<'EOF' | kubectl apply -f -
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
kubectl delete ingress legacy-web -n edge-migrate --ignore-not-found=true

echo "Implementing Question 13: canary split for the payments API"
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 14: second listener and a cross namespace route"
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
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 15: TLS terminating Gateway"
cat <<'EOF' | kubectl apply -f -
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

echo "Implementing Question 16: cross namespace backend with a ReferenceGrant"
cat <<'EOF' | kubectl apply -f -
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
---
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

echo "Implementing Question 17: repair the broken Gateway API objects"
kubectl patch gateway shop-gw -n edge-broken --type=json -p '[
  {"op": "replace", "path": "/spec/gatewayClassName", "value": "traefik"}
]'
kubectl patch httproute shop-route -n edge-broken --type=json -p '[
  {"op": "replace", "path": "/spec/hostnames/0", "value": "shop.helioscale.io"},
  {"op": "replace", "path": "/spec/rules/0/backendRefs/0/port", "value": 80}
]'

echo "Waiting for all workloads to settle"
kubectl rollout status deployment/archive-api -n archive --timeout=300s
kubectl rollout status deployment/media-api -n media --timeout=300s
kubectl rollout status deployment/report-builder -n analytics --timeout=300s
kubectl rollout status deployment/shipment-tracker -n logistics --timeout=300s
kubectl rollout status deployment/edge-proxy -n priority --timeout=300s
kubectl rollout status deployment/web-edge -n edge-helm --timeout=300s

echo "All answers applied"
