#!/bin/bash
set -e

# Question 10: egress scoped to a *named* port across namespaces, plus a
# namespace-and-pod ingress rule.
#
#   net-tally          tally-api (the Pods the policies select)
#   net-tally-data     tier=data:   ledger          role=ledger  pg-wire=5432, pg-admin=5433
#                                   ledger-replica  role=ledger  pg-wire=6432
#                                   audit           role=audit   pg-wire=5432
#   net-tally-sandbox  (no tier):   ledger-decoy    role=ledger  pg-wire=5432
#   net-tally-front                 teller (role=teller), kiosk (role=kiosk)
#
# ledger-replica names a different number "pg-wire", so a policy that writes
# port 5432 instead of the name cuts it off. Every Pod is nginx (it ships bash,
# so the validators can probe with /dev/tcp) and pinned to node01.

PIN='nodeSelector: {ck-x.io/alias: node01}'

for ns in net-tally net-tally-data net-tally-sandbox net-tally-front; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl label namespace net-tally-data tier=data --overwrite >/dev/null
kubectl delete networkpolicy --all -n net-tally --ignore-not-found=true >/dev/null

# One nginx config per listening layout.
listen_conf() {
    local name="$1" ns="$2"; shift 2
    local listens=""
    for p in "$@"; do listens="${listens}    listen ${p};
"; done
    kubectl apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: $name
  namespace: $ns
data:
  default.conf: |
    server {
${listens}      location / { return 200 "\$hostname \$server_port\n"; }
    }
YAML
}

listen_conf ledger-ports net-tally-data 5432 5433
listen_conf replica-ports net-tally-data 6432
listen_conf audit-ports net-tally-data 5432
listen_conf decoy-ports net-tally-sandbox 5432

# workload <ns> <name> <role> <configmap or ""> <ports>
workload() {
    local ns="$1" name="$2" role="$3" conf="$4" ports="$5"
    local volume="" mount=""
    if [ -n "$conf" ]; then
        mount="        volumeMounts: [{name: conf, mountPath: /etc/nginx/conf.d}]"
        volume="      volumes: [{name: conf, configMap: {name: $conf}}]"
    fi
    kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  namespace: $ns
spec:
  replicas: 1
  selector:
    matchLabels: {app: $name}
  template:
    metadata:
      labels: {app: $name, role: $role}
    spec:
      $PIN
      containers:
      - name: main
        image: nginx:1.27.4
        ports: $ports
$mount
$volume
YAML
}

workload net-tally       tally-api      api    ""            '[{name: http, containerPort: 80}]'
workload net-tally-data  ledger         ledger ledger-ports  '[{name: pg-wire, containerPort: 5432}, {name: pg-admin, containerPort: 5433}]'
workload net-tally-data  ledger-replica ledger replica-ports '[{name: pg-wire, containerPort: 6432}]'
workload net-tally-data  audit          audit  audit-ports   '[{name: pg-wire, containerPort: 5432}]'
workload net-tally-sandbox ledger-decoy ledger decoy-ports   '[{name: pg-wire, containerPort: 5432}]'
workload net-tally-front teller         teller ""            '[{name: http, containerPort: 80}]'
workload net-tally-front kiosk          kiosk  ""            '[{name: http, containerPort: 80}]'

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: ledger-db
  namespace: net-tally-data
spec:
  selector: {role: ledger}
  ports:
  - name: pg
    port: 5432
    targetPort: pg-wire
YAML

for pair in net-tally/tally-api net-tally-data/ledger net-tally-data/ledger-replica net-tally-data/audit \
            net-tally-sandbox/ledger-decoy net-tally-front/teller net-tally-front/kiosk; do
    kubectl rollout status deployment/"${pair#*/}" -n "${pair%/*}" --timeout=90s >/dev/null \
        || echo "WARNING: ${pair} did not become ready"
done

if [ -f /tmp/exam/networkpolicy-unavailable ]; then
    echo "WARNING: NetworkPolicy is not enforced on this cluster; question 10 cannot be graded fairly"
fi

echo "Setup completed for Question 10"
