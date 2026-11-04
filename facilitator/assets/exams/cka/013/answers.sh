#!/bin/bash
# Reference solution for CKA Practice Lab 013. Referenced by no code -- it is an
# author convenience for solving the whole lab in one shot on the jumphost to
# smoke-test the validation scripts.
#
#   docker compose exec -T jumphost su - candidate -c \
#     'export KUBECONFIG=/home/candidate/.kube/kubeconfig; bash /tmp/answers.sh'
#
# "su - candidate -c" does not source .bashrc, so without that export every
# apply below talks to 127.0.0.1:6443 and fails.
#
# Order matters in two places: question 4 stops the lab cluster's scheduler, so
# it runs on its own before anything else creates Pods, and question 9 drains
# node02, so it runs last.

set -u
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"
AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

step() { echo; echo "=== $* ==="; }

node_name() {
    local name
    name=$(awk -F= -v a="$1" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
    [ -n "$name" ] || name=$(kubectl get nodes -l "ck-x.io/alias=$1" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    echo "$name"
}

CP=$(node_name controlplane)
NODE02=$(node_name node02)
NODE03=$(node_name node03)

# ------- 1  auxiliary control plane
step "Question 1: repair the auxiliary cluster's API server and controller manager"
ssh $SSH_OPTS aux 'bash -s' <<'REMOTE'
sed -i 's#--etcd-servers=https://127.0.0.1:2397#--etcd-servers=https://127.0.0.1:2379#' /etc/kubernetes/manifests/kube-apiserver.yaml
sed -i 's#^\(\s*\)path: /etc/kubernetes/controller-manager.config$#\1path: /etc/kubernetes/controller-manager.conf#' /etc/kubernetes/manifests/kube-controller-manager.yaml
rm -f /etc/kubernetes/controller-manager.config
REMOTE
for _ in $(seq 1 36); do
    kubectl --kubeconfig="$AUX_KUBECONFIG" --request-timeout=5s get --raw /readyz >/dev/null 2>&1 && break
    sleep 5
done
kubectl --kubeconfig="$AUX_KUBECONFIG" rollout status deployment/relay-hub -n cp-relay --timeout=180s

# ------- 8  node03 NotReady
step "Question 8: bring node03 back"
ssh $SSH_OPTS node03 'bash -s' <<'REMOTE'
sed -i 's# --container-runtime-endpoint=unix:///var/run/cri-dockerd.sock##' /etc/default/kubelet
sed -i 's#^\(\s*server: https://[^:]*\):6643$#\1:6443#' /etc/kubernetes/kubelet.conf
systemctl restart kubelet
REMOTE
kubectl wait --for=condition=Ready node/"$NODE03" --timeout=120s

# ------- 4  scheduler bypass (on its own: nothing else may need scheduling meanwhile)
step "Question 4: run a Pod with the scheduler stopped"
ssh $SSH_OPTS controlplane 'mv /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml'
for _ in $(seq 1 24); do
    kubectl get pod "kube-scheduler-${CP}" -n kube-system >/dev/null 2>&1 || break
    sleep 5
done
kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: berth-manual
  namespace: sched-berth
spec:
  nodeName: $CP
  containers:
  - name: berth
    image: nginx:1.27.4
YAML
kubectl wait --for=condition=Ready pod/berth-manual -n sched-berth --timeout=90s
ssh $SSH_OPTS controlplane 'mv /root/kube-scheduler.yaml /etc/kubernetes/manifests/kube-scheduler.yaml'
for _ in $(seq 1 24); do
    kubectl wait --for=condition=Ready pod/"kube-scheduler-${CP}" -n kube-system --timeout=5s >/dev/null 2>&1 && break
    sleep 5
done
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: berth-auto
  namespace: sched-berth
spec:
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: berth
    image: nginx:1.27.4
YAML
kubectl wait --for=condition=Ready pod/berth-auto -n sched-berth --timeout=90s

# ------- 2  etcd snapshot and offline restore
step "Question 2: etcd snapshot, verified by an offline restore"
kubectl create configmap cutover-marker -n etcd-cutover --from-literal=wave=harbour-7
ssh $SSH_OPTS controlplane 'bash -s' <<'REMOTE'
etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /opt/etcd-backup/cutover.db
etcdutl snapshot status /opt/etcd-backup/cutover.db -w table
etcdutl snapshot restore /opt/etcd-backup/cutover.db --data-dir /opt/etcd-backup/cutover-verify
REMOTE

# ------- 3  helm rollback then upgrade
step "Question 3: roll back, then upgrade keeping the user values"
helm rollback tidewatch 1 -n helm-tide --wait --timeout 120s
helm upgrade tidewatch /tmp/exam/q3/tidewatch -n helm-tide --reuse-values \
    -f /tmp/exam/q3/values-season.yaml --set tier=priority --wait --timeout 120s
helm history tidewatch -n helm-tide

# ------- 5  kubelet configuration the kubeadm way
step "Question 5: log rotation in the kubeadm kubelet configuration"
kubectl get configmap kubelet-config -n kube-system -o json \
    | jq '.data.kubelet += "containerLogMaxSize: 25Mi\ncontainerLogMaxFiles: 4\n"' \
    | kubectl replace -f -
ssh $SSH_OPTS controlplane 'kubeadm upgrade node phase kubelet-config && systemctl restart kubelet'
kubectl wait --for=condition=Ready node/"$CP" --timeout=90s

# ------- 6  namespace guardrails
step "Question 6: Pod Security, quota and defaults"
kubectl label namespace wl-harbor \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=v1.34 --overwrite
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: harbor-quota
  namespace: wl-harbor
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
    pods: "6"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: harbor-defaults
  namespace: wl-harbor
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 50m
      memory: 64Mi
    default:
      cpu: 200m
      memory: 128Mi
YAML
kubectl patch deployment manifest-api -n wl-harbor -p '{"spec":{"template":{"spec":{
  "securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"api","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}}}'
kubectl rollout status deployment/manifest-api -n wl-harbor --timeout=120s

# ------- 7  HPA in the prod overlay
step "Question 7: HPA with behavior through the prod overlay"
cat > /tmp/exam/q7/tidereader/overlays/prod/hpa.yaml <<'YAML'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: tide-reader
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tide-reader
  minReplicas: 2
  maxReplicas: 8
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      selectPolicy: Min
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
      - type: Percent
        value: 20
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 50
        periodSeconds: 30
YAML
sed -i 's#^- ../../base$#- ../../base\n- hpa.yaml#' /tmp/exam/q7/tidereader/overlays/prod/kustomization.yaml
kubectl apply -k /tmp/exam/q7/tidereader/overlays/prod

# ------- 10  NetworkPolicies
step "Question 10: egress on a named port, ingress from one namespace"
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tally-egress
  namespace: net-tally
spec:
  podSelector:
    matchLabels:
      app: tally-api
  policyTypes: ["Egress"]
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
  - to:
    - namespaceSelector:
        matchLabels:
          tier: data
      podSelector:
        matchLabels:
          role: ledger
    ports:
    - protocol: TCP
      port: pg-wire
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tally-ingress
  namespace: net-tally
spec:
  podSelector:
    matchLabels:
      app: tally-api
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: net-tally-front
      podSelector:
        matchLabels:
          role: teller
    ports:
    - protocol: TCP
      port: 80
YAML

# ------- 11  selectorless Service and a hand-written EndpointSlice
step "Question 11: Service without a selector, EndpointSlice by hand"
IP_A=$(kubectl get pod vault-a -n net-vault-backend -o jsonpath='{.status.podIP}')
IP_B=$(kubectl get pod vault-b -n net-vault-backend -o jsonpath='{.status.podIP}')
kubectl apply -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: vault-proxy
  namespace: net-vault
spec:
  ports:
  - name: api
    port: 80
    targetPort: 8080
  - name: metrics
    port: 9100
    targetPort: 9100
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: vault-proxy-1
  namespace: net-vault
  labels:
    kubernetes.io/service-name: vault-proxy
    endpointslice.kubernetes.io/managed-by: staff.ck-x.io
addressType: IPv4
ports:
- name: api
  port: 8080
  protocol: TCP
- name: metrics
  port: 9100
  protocol: TCP
endpoints:
- addresses: ["$IP_A"]
  conditions:
    ready: true
- addresses: ["$IP_B"]
  conditions:
    ready: false
YAML

# ------- 12  ServiceCIDR
step "Question 12: a second Service range"
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata:
  name: orbit-range
spec:
  cidrs: ["10.250.0.0/24"]
YAML
kubectl wait --for=condition=Ready servicecidr/orbit-range --timeout=60s
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: orbit-gw
  namespace: net-orbit
spec:
  clusterIP: 10.250.0.40
  selector:
    app: orbit
  ports:
  - port: 80
    targetPort: 80
YAML
kubectl get service orbit-legacy -n net-orbit -o json \
    | jq 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields, .status, .spec.clusterIPs)
          | .metadata.annotations |= (. // {} | del(."kubectl.kubernetes.io/last-applied-configuration"))
          | .spec.clusterIP = "10.250.0.41"' > /tmp/orbit-legacy.json
kubectl delete service orbit-legacy -n net-orbit
kubectl create -f /tmp/orbit-legacy.json

# ------- 13  grow a claim
step "Question 13: allow expansion, then grow the claim"
kubectl patch storageclass harbor-grow -p '{"allowVolumeExpansion":true}'
kubectl patch pvc ledger-data -n stor-ledger -p '{"spec":{"resources":{"requests":{"storage":"1Gi"}}}}'

# ------- 14  local PersistentVolume pinned by a label
step "Question 14: local volume pinned through a node label"
kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vault-local
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vault-pv-01
spec:
  capacity:
    storage: 1Gi
  accessModes: ["ReadWriteOnce"]
  storageClassName: vault-local
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /srv/ck-x/tidevault
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: storage.ck-x.io/vault
          operator: In
          values: ["nvme"]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vault-claim
  namespace: stor-vault
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: vault-local
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: vault-reader
  namespace: stor-vault
spec:
  containers:
  - name: reader
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts:
    - name: vault
      mountPath: /vault
  volumes:
  - name: vault
    persistentVolumeClaim:
      claimName: vault-claim
YAML
kubectl wait --for=condition=Ready pod/vault-reader -n stor-vault --timeout=90s

# ------- 15  the rollout that would not land
step "Question 15: strategy, Secret key and probe port"
kubectl patch deployment cargo-api -n ts-cargo --type=json -p '[
  {"op":"replace","path":"/spec/strategy","value":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}},
  {"op":"replace","path":"/spec/template/spec/containers/0/env/1/valueFrom/secretKeyRef/key","value":"api-token"},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":80}]'
kubectl rollout status deployment/cargo-api -n ts-cargo --timeout=180s

# ------- 16  namespace stuck Terminating
step "Question 16: release the finalizers inside ts-decom"
for gauge in $(kubectl get tidegauges -n ts-decom -o name); do
    kubectl patch "$gauge" -n ts-decom --type=merge -p '{"metadata":{"finalizers":null}}'
done
kubectl wait --for=delete namespace/ts-decom --timeout=120s

# ------- 17  read a value out of a shell-less container
step "Question 17: ephemeral debug container with ptrace"
kubectl debug beacon-core -n ts-lighthouse --image=busybox:1.36 --target=core \
    --profile=general -c recover -- sh -c 'tr "\0" "\n" < /proc/1/environ | sed -n "s/^LIGHT_TOKEN=//p"; sleep 3600'
for _ in $(seq 1 12); do
    TOKEN=$(kubectl logs beacon-core -n ts-lighthouse -c recover 2>/dev/null | head -1)
    [ -n "$TOKEN" ] && break
    sleep 5
done
echo "$TOKEN" > /tmp/exam/q17/token.txt

# ------- 9  PDB and drain (last: it empties node02)
step "Question 9: one disruption budget, then drain node02"
kubectl delete pdb quorum-legacy -n wl-quorum
kubectl apply -f - <<'YAML'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: quorum-budget
  namespace: wl-quorum
spec:
  maxUnavailable: 1
  unhealthyPodEvictionPolicy: AlwaysAllow
  selector:
    matchLabels:
      app: quorum
      ring: primary
YAML
kubectl drain "$NODE02" --ignore-daemonsets --delete-emptydir-data --timeout=180s
kubectl rollout status deployment/quorum -n wl-quorum --timeout=120s

echo
echo "All answers applied."
