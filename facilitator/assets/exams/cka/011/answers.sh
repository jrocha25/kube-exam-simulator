#!/bin/bash
# Solves every question of cka-011 in one shot, so the validation scripts can be
# smoke-tested without sitting the lab by hand. Referenced by no code -- it is an
# author convenience, the same as cka/002 - cka/005 carry.
#
# Run it on the jumphost as the candidate, exporting KUBECONFIG explicitly:
#
#   docker compose exec -T jumphost su - candidate -c \
#     'export KUBECONFIG=/home/candidate/.kube/kubeconfig; bash /tmp/answers.sh'
#
# "su - candidate -c" does not source .bashrc, so without that export every
# apply below talks to 127.0.0.1:6443 and fails.

set -u
AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

step() { echo; echo "=== $* ==="; }

# --------------------------------------------------------------- 1
step "Question 1: add the tower context"
KCFG=/tmp/exam/q1/ops.kubeconfig
kubectl --kubeconfig "$KCFG" config set-context tower \
    --cluster=airops --user=tower-ops --namespace=ops-access
kubectl --kubeconfig "$KCFG" config use-context tower

# --------------------------------------------------------------- 2
step "Question 2: install and upgrade the beacon release"
helm install beacon /tmp/exam/q2/beacon-chart -n ops-charts --set replicaCount=2 --wait --timeout 3m \
    || helm upgrade --install beacon /tmp/exam/q2/beacon-chart -n ops-charts --set replicaCount=2 --wait --timeout 3m
helm upgrade beacon /tmp/exam/q2/beacon-chart -n ops-charts \
    --set replicaCount=2 --set message=active --wait --timeout 3m

# --------------------------------------------------------------- 3
step "Question 3: deploy the metrics server and let it scrape the kubelets"
kubectl apply -f /tmp/exam/q3/metrics-server.yaml
# This first wait is expected to time out: without the flag added below the
# metrics-server never passes its own readiness probe, because it cannot scrape
# a single kubelet. Kept short deliberately -- it is the symptom, not a wait.
kubectl -n kube-system rollout status deployment/metrics-server --timeout=60s || true
# kind's kubelets serve certificates the cluster CA did not sign.
if ! kubectl -n kube-system get deployment metrics-server \
        -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q kubelet-insecure-tls; then
    kubectl -n kube-system patch deployment metrics-server --type=json \
        -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s || true

# --------------------------------------------------------------- 4
step "Question 4: radar-egress, one rule per destination and port"
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: radar-egress
  namespace: net-radar
spec:
  podSelector:
    matchLabels:
      app: radar
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: beacon
    ports:
    - protocol: TCP
      port: 5555
  - to:
    - podSelector:
        matchLabels:
          app: archive
    ports:
    - protocol: TCP
      port: 6666
YAML

# --------------------------------------------------------------- 5
step "Question 5: split the merged apron-egress rule in two"
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: apron-egress
  namespace: net-apron
spec:
  podSelector:
    matchLabels:
      app: apron
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: gate
    ports:
    - protocol: TCP
      port: 7001
  - to:
    - podSelector:
        matchLabels:
          app: fuel
    ports:
    - protocol: TCP
      port: 7002
YAML

# --------------------------------------------------------------- 6
step "Question 6: back up and extend the auxiliary cluster's Corefile"
mkdir -p /tmp/exam/q6
# The redirection stays on this side: the file belongs on the jumphost.
ssh -o BatchMode=yes aux "kubectl -n kube-system get configmap coredns -o yaml" \
    > /tmp/exam/q6/coredns-backup.yaml
kubectl --kubeconfig "$AUX_KUBECONFIG" -n kube-system get configmap coredns -o json \
    | python3 -c '
import json, re, sys
doc = json.load(sys.stdin)
corefile = doc["data"]["Corefile"]
if "airops.internal" not in corefile:
    corefile = re.sub(r"(kubernetes\s+cluster\.local)", r"\1 airops.internal", corefile, count=1)
doc["data"]["Corefile"] = corefile
json.dump(doc, sys.stdout)
' \
    | kubectl --kubeconfig "$AUX_KUBECONFIG" apply -f -
kubectl --kubeconfig "$AUX_KUBECONFIG" -n kube-system rollout restart deployment/coredns
kubectl --kubeconfig "$AUX_KUBECONFIG" -n kube-system rollout status deployment/coredns --timeout=180s || true

# --------------------------------------------------------------- 7
step "Question 7: the briefing Pod with its own resolver settings"
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: briefing
  namespace: dns-apron
spec:
  dnsPolicy: ClusterFirst
  dnsConfig:
    searches:
    - dns-apron-wx.svc.cluster.local
    options:
    - name: ndots
      value: "1"
  containers:
  - name: briefing
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

# --------------------------------------------------------------- 8
step "Question 8: claim the fast volume and mount it"
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cargo-claim
  namespace: stor-cargo
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ""
  resources:
    requests:
      storage: 2Gi
  selector:
    matchLabels:
      tier: fast
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cargo-hold
  namespace: stor-cargo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cargo-hold
  template:
    metadata:
      labels:
        app: cargo-hold
    spec:
      volumes:
      - name: cargo
        persistentVolumeClaim:
          claimName: cargo-claim
      containers:
      - name: hold
        image: nginx:1.27.4
        volumeMounts:
        - name: cargo
          mountPath: /var/cargo
YAML

# --------------------------------------------------------------- 9
step "Question 9: retention policy first, then scale in"
kubectl -n wl-baggage patch statefulset belt --type=merge -p \
    '{"spec":{"persistentVolumeClaimRetentionPolicy":{"whenScaled":"Delete","whenDeleted":"Retain"}}}'
kubectl -n wl-baggage scale statefulset belt --replicas=1

# --------------------------------------------------------------- 10
step "Question 10: a create-only Role"
kubectl -n rbac-tower create serviceaccount flightplan-writer --dry-run=client -o yaml | kubectl apply -f -
kubectl -n rbac-tower create role flightplan-writer \
    --verb=create --resource=configmaps --resource=secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl -n rbac-tower create rolebinding flightplan-writer \
    --role=flightplan-writer --serviceaccount=rbac-tower:flightplan-writer \
    --dry-run=client -o yaml | kubectl apply -f -

# --------------------------------------------------------------- 11
step "Question 11: query the API server as the Pod's ServiceAccount"
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: beacon-probe
  namespace: api-beacon
spec:
  serviceAccountName: beacon-reader
  containers:
  - name: probe
    image: curlimages/curl:8.11.1
    command: ["sh", "-c", "sleep 86400"]
YAML
kubectl -n api-beacon wait --for=condition=Ready pod/beacon-probe --timeout=180s || true
mkdir -p /tmp/exam/q11
kubectl -n api-beacon exec beacon-probe -- sh -c '
  SA=/var/run/secrets/kubernetes.io/serviceaccount
  curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" \
       https://kubernetes.default.svc/api/v1/namespaces/api-beacon/configmaps
' > /tmp/exam/q11/configmaps.json

# --------------------------------------------------------------- 12
step "Question 12: a DaemonSet that tolerates the control plane"
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: deice
  namespace: ds-deice
spec:
  selector:
    matchLabels:
      app: deice
  template:
    metadata:
      labels:
        app: deice
        zone: apron
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
      containers:
      - name: deice
        image: nginx:1.27.4
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
YAML

# --------------------------------------------------------------- 13
step "Question 13: the tug container, seen from its node"
mkdir -p /tmp/exam/q13
NODE=$(kubectl -n node-crictl get pod tug -o jsonpath='{.spec.nodeName}')
ALIAS=$(awk -F= -v n="$NODE" '$2==n {print $1}' /tmp/exam/nodes.env | head -1)
CID=$(ssh -o BatchMode=yes "$ALIAS" "crictl ps -q --name '^tug\$' --state Running" | head -1 | tr -d '\r')
RUNTIME=$(ssh -o BatchMode=yes "$ALIAS" "crictl inspect ${CID}" | jq -r '.info.runtimeType')
echo "${CID} ${RUNTIME}" > /tmp/exam/q13/container.txt
ssh -o BatchMode=yes "$ALIAS" "crictl logs ${CID} 2>&1" > /tmp/exam/q13/container.log

# --------------------------------------------------------------- 14
step "Question 14: read the etcd certificate, renew one other"
mkdir -p /tmp/exam/q14
ssh -o BatchMode=yes controlplane "openssl x509 -noout -enddate -in /etc/kubernetes/pki/etcd/server.crt" \
    | tr -d '\r' | cut -d= -f2- > /tmp/exam/q14/etcd-expiry.txt
# Deliberately one certificate, not "all".
ssh -o BatchMode=yes controlplane "kubeadm certs renew apiserver-kubelet-client"

# --------------------------------------------------------------- 15
step "Question 15: drop the ConfigMap, add the autoscaler"
ROOT=/tmp/exam/q15/flightboard

cat > "${ROOT}/base/flightboard.yaml" <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flightboard
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flightboard
spec:
  replicas: 1
  selector:
    matchLabels:
      id: flightboard
  template:
    metadata:
      labels:
        id: flightboard
    spec:
      serviceAccountName: flightboard
      containers:
      - name: board
        image: nginx:1.27.4
        resources:
          requests:
            cpu: 10m
            memory: 20Mi
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: flightboard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: flightboard
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
YAML

cat > "${ROOT}/staging/flightboard.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flightboard
  labels:
    env: staging
YAML

cat > "${ROOT}/prod/flightboard.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flightboard
  labels:
    env: prod
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: flightboard
spec:
  maxReplicas: 6
YAML

kubectl kustomize "${ROOT}/staging" | kubectl apply -f -
kubectl kustomize "${ROOT}/prod"    | kubectl apply -f -
# Kustomize keeps no state, so the live copies have to go by hand.
kubectl -n kustom-flight-staging delete configmap refresh-config --ignore-not-found=true
kubectl -n kustom-flight-prod    delete configmap refresh-config --ignore-not-found=true

# --------------------------------------------------------------- 16
step "Question 16: raise hangar-ops to Guaranteed"
# A STRATEGIC merge patch: container lists are merged on the "name" key, so the
# image survives. "--type=merge" is a JSON merge patch, which replaces the whole
# array and is rejected with "spec.template.spec.containers[0].image: Required".
kubectl -n qos-hangar patch deployment hangar-ops -p '
spec:
  template:
    spec:
      containers:
      - name: ops
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 50m
            memory: 64Mi
'

# --------------------------------------------------------------- 17
step "Question 17: expose the Pod and capture kube-proxy's rules"
kubectl -n svc-iptables expose pod apronctl --name=apronctl --port=8080 --target-port=80 \
    --dry-run=client -o yaml | kubectl apply -f -
mkdir -p /tmp/exam/q17
# Give kube-proxy a moment to programme the node before reading the rules back.
sleep 5
ssh -o BatchMode=yes controlplane "iptables-save | grep svc-iptables/apronctl" \
    > /tmp/exam/q17/rules.txt

echo
echo "=== all questions answered ==="
