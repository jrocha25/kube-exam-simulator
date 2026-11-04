#!/bin/bash
# Reference solution for CKA Practice Lab 014. Referenced by no code -- it is an
# author convenience for solving the whole lab in one shot on the jumphost to
# smoke-test the validation scripts.
#
#   docker compose cp facilitator/assets/exams/cka/014/answers.sh jumphost:/tmp/answers.sh
#   docker compose exec -T jumphost su - candidate -c \
#     'export KUBECONFIG=/home/candidate/.kube/kubeconfig; bash /tmp/answers.sh'
#
# "su - candidate -c" does not source .bashrc, so without that export every
# apply below talks to 127.0.0.1:6443 and fails.
#
# Order matters once: question 11 needs the auxiliary API server that question 3
# repairs.

set -u
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"
AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

step() { echo; echo "=== $* ==="; }

node_name() {
    awk -F= -v a="$1" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1
}
NODE02=$(node_name node02)
NODE03=$(node_name node03)

# ------- 3  auxiliary API server
step "Question 3: point the auxiliary API server at etcd's client port"
ssh $SSH_OPTS aux 'bash -s' <<'REMOTE'
IP=$(sed -n 's#^\s*- --advertise-client-urls=https://\([0-9.]*\):2379$#\1#p' /etc/kubernetes/manifests/etcd.yaml)
sed -i "s#^\(\s*- --etcd-servers=\).*#\1https://${IP}:2379#" /etc/kubernetes/manifests/kube-apiserver.yaml
grep -- --etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
REMOTE
for _ in $(seq 1 36); do
    kubectl --kubeconfig="$AUX_KUBECONFIG" --request-timeout=5s get --raw /readyz >/dev/null 2>&1 && break
    sleep 5
done

# ------- 11  auxiliary CNI
step "Question 11: install Calico on the auxiliary cluster with the cluster's Pod CIDR"
ssh $SSH_OPTS aux 'bash -s' <<'REMOTE'
CIDR=$(kubectl get cm kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' | sed -n 's/^\s*podSubnet:\s*//p')
echo "podSubnet: $CIDR"
cp /root/cni/calico.yaml /root/cni/calico-custom.yaml
sed -i -e 's|^\( *\)# \(- name: CALICO_IPV4POOL_CIDR\)$|\1\2|' \
       -e "s|^\( *\)#   value: \"192.168.0.0/16\"$|\1  value: \"$CIDR\"|" /root/cni/calico-custom.yaml
grep -A1 'name: CALICO_IPV4POOL_CIDR' /root/cni/calico-custom.yaml
kubectl apply -f /root/cni/calico-custom.yaml >/dev/null
kubectl rollout status daemonset/calico-node -n kube-system --timeout=180s
kubectl wait --for=condition=Ready node --all --timeout=120s
REMOTE

# ------- 9  node03
step "Question 9: repair node03's kubelet unit and enable it"
ssh $SSH_OPTS node03 'bash -s' <<'REMOTE'
sed -i 's#^ExecStart=/usr/local/bin/kubelet #ExecStart=/usr/bin/kubelet #' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
systemctl enable --now kubelet
systemctl restart kubelet
REMOTE
kubectl wait --for=condition=Ready node/"$NODE03" --timeout=120s

# ------- 1  Helm
step "Question 1: render and install berthwatch 0.7.2 without its CRD"
CHART=/tmp/exam/q1/charts/berthwatch-0.7.2.tgz
helm template berthwatch "$CHART" -n helm-berth --set replicaCount=2 --set crds.install=false > /tmp/exam/q1/berthwatch.yaml
helm install berthwatch "$CHART" -n helm-berth --create-namespace --set replicaCount=2 --set crds.install=false
kubectl rollout status deployment/berthwatch -n helm-berth --timeout=120s

# ------- 2  Gateway API
step "Question 2: migrate quay-web to the Gateway API"
kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: quay-gw
  namespace: quay-edge
spec:
  gatewayClassName: harbor-gwc
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: quay.harbor.local
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: quay-tls
  - name: http
    protocol: HTTP
    port: 80
    hostname: quay.harbor.local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: quay-web
  namespace: quay-edge
spec:
  parentRefs:
  - name: quay-gw
    sectionName: https
  hostnames:
  - quay.harbor.local
  rules:
  - matches:
    - path:
        type: Exact
        value: /healthz/berths
    backendRefs:
    - name: quay-status
      port: 8080
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: quay-web
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: quay-redirect
  namespace: quay-edge
spec:
  parentRefs:
  - name: quay-gw
    sectionName: http
  hostnames:
  - quay.harbor.local
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
YAML
kubectl delete ingress quay-web -n quay-edge

# ------- 4  HPA
step "Question 4: autoscale crane-telemetry"
kubectl apply -f - <<'YAML'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: crane-telemetry
  namespace: hpa-crane
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: crane-telemetry
  minReplicas: 2
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 45
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
YAML

# ------- 5  Released PV
step "Question 5: rebind the retained ledger volume"
kubectl patch pv ledger-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ledger-data
  namespace: ledger
spec:
  storageClassName: ledger-manual
  volumeName: ledger-pv
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
YAML
kubectl apply -f /tmp/exam/q5/ledger-db.yaml
kubectl rollout status deployment/ledger-db -n ledger --timeout=120s

# ------- 6  NetworkPolicy
step "Question 6: apply the least permissive policy"
kubectl apply -f /tmp/exam/q6/api-ingress-2.yaml

# ------- 7  node prep
step "Question 7: prepare node01"
ssh $SSH_OPTS node01 'bash -s' <<'REMOTE'
dpkg -i /root/harbor-cri-shim_1.4.2_all.deb
systemctl enable --now harbor-cri-shim
cat > /etc/sysctl.d/99-harbor.conf <<CONF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
CONF
sysctl -p /etc/sysctl.d/99-harbor.conf
REMOTE

# ------- 8  native sidecar
step "Question 8: add the manifest-shipper sidecar ahead of schema-migrate"
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: manifest-api
  namespace: manifest-ops
spec:
  replicas: 2
  selector:
    matchLabels:
      app: manifest-api
  template:
    metadata:
      labels:
        app: manifest-api
    spec:
      volumes:
      - name: manifest-logs
        emptyDir: {}
      initContainers:
      - name: manifest-shipper
        image: busybox:1.36
        restartPolicy: Always
        command: ["sh", "-c", "tail -n 0 -F /var/log/manifest/migrate.log /var/log/manifest/app.log"]
        volumeMounts:
        - name: manifest-logs
          mountPath: /var/log/manifest
      - name: schema-migrate
        image: busybox:1.36
        command:
        - sh
        - -c
        - mkdir -p /var/log/manifest; sleep 3; for i in 1 2 3; do echo "$(date -u +%T) migrate step $i" >> /var/log/manifest/migrate.log; sleep 1; done
        volumeMounts:
        - name: manifest-logs
          mountPath: /var/log/manifest
      containers:
      - name: api
        image: busybox:1.36
        command:
        - sh
        - -c
        - mkdir -p /var/log/manifest; while true; do echo "$(date -u +%T) api heartbeat" >> /var/log/manifest/app.log; sleep 5; done
        volumeMounts:
        - name: manifest-logs
          mountPath: /var/log/manifest
YAML
kubectl rollout status deployment/manifest-api -n manifest-ops --timeout=120s

# ------- 10  PriorityClass
step "Question 10: berth-urgent one below the highest user-defined class"
HIGHEST=$(kubectl get priorityclass -o json | jq '[.items[] | select(.metadata.name | startswith("system-") | not) | .value] | max')
kubectl create priorityclass berth-urgent --value=$((HIGHEST - 1)) --description="pilot dispatch"
kubectl patch deployment pilot-dispatch -n pilot-ops -p '{"spec":{"template":{"spec":{"priorityClassName":"berth-urgent"}}}}'
kubectl rollout status deployment/pilot-dispatch -n pilot-ops --timeout=120s

# ------- 12  NodePort
step "Question 12: named port and NodePort Service"
kubectl patch deployment tally-board -n tally -p '{"spec":{"template":{"spec":{"containers":[{"name":"board","ports":[{"name":"http","containerPort":80,"protocol":"TCP"}]}]}}}}'
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: tally-board-np
  namespace: tally
spec:
  type: NodePort
  selector:
    app: tally-board
  ports:
  - port: 80
    targetPort: http
    nodePort: 30814
YAML
kubectl rollout status deployment/tally-board -n tally --timeout=120s

# ------- 13  divide node02
step "Question 13: split node02 between three crane-sim Pods"
CPU_M=$(kubectl get node "$NODE02" -o jsonpath='{.status.allocatable.cpu}' | awk '/m$/ {sub("m",""); print; next} {print $1*1000}')
MEM_KI=$(kubectl get node "$NODE02" -o jsonpath='{.status.allocatable.memory}' | sed 's/Ki$//')
REQ_CPU="$((CPU_M * 28 / 100))m"
REQ_MEM="$((MEM_KI * 28 / 100 / 1024))Mi"
echo "allocatable ${CPU_M}m / ${MEM_KI}Ki -> each Pod requests $REQ_CPU / $REQ_MEM"
kubectl patch deployment crane-sim -n crane-sim --type=json -p "[
  {\"op\":\"add\",\"path\":\"/spec/template/spec/initContainers/0/resources\",\"value\":{\"requests\":{\"cpu\":\"$REQ_CPU\",\"memory\":\"$REQ_MEM\"}}},
  {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/resources\",\"value\":{\"requests\":{\"cpu\":\"$REQ_CPU\",\"memory\":\"$REQ_MEM\"}}}
]"
kubectl scale deployment crane-sim -n crane-sim --replicas=3
kubectl rollout status deployment/crane-sim -n crane-sim --timeout=120s

# ------- 14  CRDs
step "Question 14: list the tides CRDs and explain spec.retention"
kubectl get crd | grep tides.harbor.io > /tmp/exam/q14/tide-crds.txt
kubectl explain tideforecasts.spec.retention > /tmp/exam/q14/retention-doc.txt

# ------- 15  default StorageClass
step "Question 15: harbor-fast as the only default StorageClass"
kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: harbor-fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
allowVolumeExpansion: true
YAML
kubectl annotate storageclass standard storageclass.kubernetes.io/is-default-class=false --overwrite

# ------- 16  Pod Security
step "Question 16: make customs-gate admissible under restricted"
kubectl patch deployment customs-gate -n customs -p '{"spec":{"template":{"spec":{
  "securityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"gate","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}}}'
kubectl rollout status deployment/customs-gate -n customs --timeout=120s

echo
echo "All answers applied."
