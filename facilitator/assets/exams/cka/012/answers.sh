#!/bin/bash
# Reference solution for CKA Practice Lab 012. Referenced by no code -- it is an
# author convenience for solving the whole lab in one shot on the jumphost to
# smoke-test the validation scripts.
#
#   docker compose exec -T jumphost su - candidate -c \
#     'export KUBECONFIG=/home/candidate/.kube/kubeconfig; bash /tmp/answers.sh'
#
# "su - candidate -c" does not source .bashrc, so without that export every
# apply below talks to 127.0.0.1:6443 and fails.

set -u
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

step() { echo; echo "=== $* ==="; }

node_name() {
    local name
    name=$(awk -F= -v a="$1" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
    [ -n "$name" ] || name=$(kubectl get nodes -l "ck-x.io/alias=$1" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    echo "$name"
}

static_dir() {
    local alias="$1" dir
    dir=$(ssh $SSH_OPTS "$alias" "awk '/^staticPodPath:/ {print \$2}' /var/lib/kubelet/config.yaml" 2>/dev/null | tr -d '\r')
    [ -n "$dir" ] || dir=/etc/kubernetes/manifests
    echo "$dir"
}

# ------- 1  static Pod on node02
step "Question 1: static Pod in the directory node02's kubelet reads"
Q1_DIR=$(static_dir node02)
echo "node02 staticPodPath: ${Q1_DIR}"
ssh $SSH_OPTS node02 "cat > ${Q1_DIR}/sensor-collector.yaml" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: sensor-collector
  namespace: node-sensor
  labels:
    duty: telemetry
spec:
  containers:
  - name: collector
    image: nginx:1.27.4
YAML

# ------- 2  remove the rogue static Pod
step "Question 2: remove the manifest that keeps recreating the Pod"
Q2_DIR=$(static_dir node01)
ssh $SSH_OPTS node01 "rm -f ${Q2_DIR}/relay-shim.yaml" || true

# ------- 3  one AND rule and one OR rule
step "Question 3: NetworkPolicy with both semantics in one object"
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tremor-ingress
  namespace: net-tremor
spec:
  podSelector:
    matchLabels:
      app: tremor-ingest
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchExpressions:
        - key: seismo.io/tier
          operator: In
          values: ["api"]
      podSelector:
        matchLabels:
          station-role: gateway
    ports:
    - protocol: TCP
      port: 8443
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: net-tremor-wave
    ports:
    - protocol: TCP
      port: 9100
YAML

# ------- 4  narrow the over-permissive policy
step "Question 4: put both selectors in the same from entry"
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: array-ingress
  namespace: net-array
spec:
  podSelector:
    matchLabels:
      app: station-relay
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: net-array-edge
      podSelector:
        matchLabels:
          station-role: collector
    ports:
    - protocol: TCP
      port: 8443
YAML

# ------- 5  CronJob with fields at three levels
step "Question 5: CronJob with each field at the level it belongs to"
kubectl apply -f - <<'YAML'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: trace-compactor
  namespace: wl-digest
spec:
  schedule: "*/20 * * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 30
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 2
  suspend: false
  jobTemplate:
    spec:
      activeDeadlineSeconds: 60
      backoffLimit: 2
      ttlSecondsAfterFinished: 120
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: compactor
            image: busybox:1.36
            command: ["sh", "-c", "echo compacting traces && sleep 5"]
YAML

# ------- 6  stop the runs overlapping
step "Question 6: forbid overlap, bound the run, clear the pile"
kubectl patch cronjob digest-trim -n wl-rotate --type=merge -p \
  '{"spec":{"concurrencyPolicy":"Forbid","jobTemplate":{"spec":{"activeDeadlineSeconds":45}}}}'
kubectl delete job --all -n wl-rotate --wait=false || true

# ------- 7  give the Service its endpoints back
step "Question 7: repair the Service's selector and target port"
# The selector is a map, and a merge patch merges maps -- so the two keys that
# are wrong have to be removed explicitly with null, or the Service ends up
# selecting all four labels and still matches nothing.
kubectl patch service station-catalog-svc -n svc-catalog --type=merge -p \
  '{"spec":{"selector":{"component":null,"managed-by":null,"app":"station-catalog","tier":"api"},"ports":[{"protocol":"TCP","port":80,"targetPort":80}]}}'

# ------- 8  capture the per-Pod lookup
step "Question 8: resolve the headless Service's per-Pod record"
mkdir -p /tmp/exam/q8
kubectl exec dns-tool -n dns-station -- \
    nslookup station-index-0.station-index.dns-station.svc.cluster.local. \
    > /tmp/exam/q8/lookup.txt 2>&1 || true
cat /tmp/exam/q8/lookup.txt

# ------- 9  init container plus two regular containers
step "Question 9: one init container, two regular containers, one emptyDir"
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: waveform-writer
  namespace: wl-waveform
spec:
  initContainers:
  - name: seed-ledger
    image: busybox:1.36
    command: ["sh", "-c", "echo '=== waveform ledger opened ===' > /srv/waveforms/ledger.log"]
    volumeMounts:
    - name: ledger
      mountPath: /srv/waveforms
  containers:
  - name: waveform-app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date) waveform written\" >> /srv/waveforms/ledger.log; sleep 5; done"]
    volumeMounts:
    - name: ledger
      mountPath: /srv/waveforms
  - name: ledger-tail
    image: busybox:1.36
    command: ["sh", "-c", "tail -f /srv/waveforms/ledger.log"]
    volumeMounts:
    - name: ledger
      mountPath: /srv/waveforms
  volumes:
  - name: ledger
    emptyDir: {}
YAML

# ------- 10  native sidecar
step "Question 10: one regular container, an init container and a native sidecar"
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: trace-shipper
  namespace: wl-shipper
spec:
  initContainers:
  - name: prepare-spool
    image: busybox:1.36
    command: ["sh", "-c", "touch /var/spool/traces/trace.log"]
    volumeMounts:
    - name: spool
      mountPath: /var/spool/traces
  - name: log-forwarder
    image: busybox:1.36
    restartPolicy: Always
    command: ["sh", "-c", "tail -f /var/spool/traces/trace.log"]
    volumeMounts:
    - name: spool
      mountPath: /var/spool/traces
  containers:
  - name: trace-app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date) trace emitted\" >> /var/spool/traces/trace.log; sleep 5; done"]
    volumeMounts:
    - name: spool
      mountPath: /var/spool/traces
  volumes:
  - name: spool
    emptyDir: {}
YAML

# ------- 11  label the node the Pod is waiting for
step "Question 11: label node02 so the Pending Pod can be placed"
NODE02=$(node_name node02)
kubectl label node "$NODE02" seismo.io/duty=plotting --overwrite

# ------- 12  tolerate what node03 refuses
step "Question 12: add a toleration to the existing Pod, in place"
# A JSON patch APPENDS. A merge patch would replace the whole tolerations array,
# dropping the two NoExecute entries every Pod carries -- and removing a
# toleration from a running Pod is rejected, so the patch would fail.
kubectl patch pod borehole-sampler -n sched-borehole --type=json -p \
  '[{"op":"add","path":"/spec/tolerations/-","value":{"key":"seismo.io/borehole","operator":"Equal","value":"restricted","effect":"NoSchedule"}}]'

# ------- 13  the two files
step "Question 13: write the two files"
mkdir -p /tmp/exam/q13
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
    | awk -F'\t' '$2=="True" {print $1}' > /tmp/exam/q13/ready-nodes.txt
kubectl get namespaces --no-headers | wc -l | tr -d ' ' > /tmp/exam/q13/ns-count.txt
cat /tmp/exam/q13/ready-nodes.txt /tmp/exam/q13/ns-count.txt

step "All answers applied"
