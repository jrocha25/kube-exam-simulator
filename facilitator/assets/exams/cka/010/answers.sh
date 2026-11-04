#!/bin/bash
# answers.md converted to answers.sh for quick testing of the cka-010 lab.
# Run it on the exam jumphost with KUBECONFIG pointing at the exam cluster.
#
# Like cka/006's, this script drives the cluster nodes over SSH -- six of the
# questions are answered on a node rather than through the API server -- and two
# of them (1 and 3) are answered on the auxiliary cluster's node. Question 3 is
# solved before question 1 on purpose; answers.md explains why.

set -u

CP=$(kubectl get nodes -l ck-x.io/alias=controlplane -o jsonpath='{.items[0].metadata.name}')
N1=$(kubectl get nodes -l ck-x.io/alias=node01 -o jsonpath='{.items[0].metadata.name}')
N2=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}')
echo "controlplane=$CP node01=$N1 node02=$N2"

echo "== Question 3: etcd snapshot and restore (aux cluster) =="
ssh aux 'bash -s' <<'REMOTE'
set -e
export ETCDCTL_API=3
ETCD="etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
$ETCD snapshot save /opt/etcd-backup/before-restore.db
etcdutl snapshot status /opt/etcd-backup/before-restore.db

# Stop the whole control plane by moving the static Pod manifests out of the
# directory the kubelet watches. Taking the API server, controller manager and
# scheduler down with etcd is deliberate: every one of them holds a watch cache
# filled from the OLD data, and bringing them back after the restore is what
# resets it. (A kubelet restart alone does not do that -- the kubelet re-adopts
# running static Pods; only a manifest change recreates them.)
mkdir -p /root/manifests
mv /etc/kubernetes/manifests/*.yaml /root/manifests/
for _ in $(seq 1 24); do [ -z "$(crictl ps -q --name 'etcd|kube-apiserver|kube-controller-manager|kube-scheduler')" ] && break; sleep 5; done

mv /var/lib/etcd /var/lib/etcd.pre-restore
etcdutl snapshot restore /opt/etcd-backup/aux-snapshot.db --data-dir /var/lib/etcd
mv /root/manifests/*.yaml /etc/kubernetes/manifests/
for _ in $(seq 1 36); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 5; done

# The kubelet's own watches are just as stale -- resource versions went
# backwards -- and a kubelet left like this never starts another Pod. Restart
# it once the new API server is up, so it lists afresh.
systemctl restart kubelet
# Then give the control plane a moment: RBAC is 403 for a few seconds after
# the API server starts, and the controller manager and scheduler have to win
# back the stale leases the snapshot brought with it. A Pod that runs is proof.
for _ in $(seq 1 24); do kubectl get cm -n etcd-restore >/dev/null 2>&1 && break; sleep 5; done
kubectl get cm -n etcd-restore
kubectl run restore-probe -n etcd-restore --image=busybox:1.36 --restart=Never -- sleep 60 >/dev/null 2>&1 || true
for _ in $(seq 1 24); do
    [ "$(kubectl get pod restore-probe -n etcd-restore -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && break
    sleep 5
done
kubectl delete pod restore-probe -n etcd-restore --wait=false >/dev/null 2>&1 || true
REMOTE

echo "== Question 1: upgrade the aux cluster to 1.34.10 =="
ssh aux 'bash -s' <<'REMOTE'
set -e
export DEBIAN_FRONTEND=noninteractive
sed -i 's#/v1\.33/#/v1.34/#' /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-mark unhold kubeadm
apt-get install -y -qq kubeadm='1.34.10-*'
apt-mark hold kubeadm
kubeadm version -o short
kubeadm upgrade plan >/dev/null
kubeadm upgrade apply v1.34.10 -y 2>&1 | tail -3

NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
apt-mark unhold kubelet kubectl
apt-get install -y -qq kubelet='1.34.10-*' kubectl='1.34.10-*'
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
# Restarting the kubelet bounces the static Pods, the API server included.
for _ in $(seq 1 24); do kubectl uncordon "$NODE" >/dev/null 2>&1 && break; sleep 5; done
kubectl get nodes
REMOTE

echo "== Question 2: rejoin node03 =="
JOIN=$(ssh controlplane "kubeadm token create --print-join-command")
ssh node03 "$JOIN"

echo "== Question 4: renew the control plane certificates =="
ssh controlplane 'bash -s' <<'REMOTE'
set -e
kubeadm certs check-expiration | head -5
kubeadm certs renew all >/dev/null
mkdir -p /root/manifests-restart
mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/kube-controller-manager.yaml \
   /etc/kubernetes/manifests/kube-scheduler.yaml /root/manifests-restart/
for _ in $(seq 1 12); do crictl ps --name kube-apiserver -q | grep -q . || break; sleep 5; done
mv /root/manifests-restart/*.yaml /etc/kubernetes/manifests/
for _ in $(seq 1 24); do kubectl --kubeconfig /etc/kubernetes/admin.conf get --raw /readyz >/dev/null 2>&1 && break; sleep 5; done
REMOTE

echo "== Question 5: bring node02 back =="
ssh node02 "sed -i 's#clientCAFile: /etc/kubernetes/pki/ca.pem#clientCAFile: /etc/kubernetes/pki/ca.crt#' /var/lib/kubelet/config.yaml; systemctl enable kubelet >/dev/null 2>&1; systemctl restart kubelet"

echo "== Question 6: static Pod on node01 =="
ssh node01 'cat > /etc/kubernetes/manifests/edge-cache.yaml <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: edge-cache
  namespace: static-edge
spec:
  containers:
  - name: cache
    image: nginx:1.27.4
    ports:
    - containerPort: 80
      hostPort: 8080
YAML'

echo "== Question 7: repair the kubeconfig =="
K=/tmp/exam/q7/release.kubeconfig
kubectl --kubeconfig $K config set-context release@lab --user=releasebot >/dev/null
kubectl --kubeconfig $K config set-cluster lab --server=https://k8s-api-server:6443 >/dev/null
kubectl --kubeconfig $K get pods -n kcfg-release

echo "== Question 8: CRD =="
kubectl apply -f - <<'YAML'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: shipments.logistics.ck-x.io
spec:
  group: logistics.ck-x.io
  scope: Namespaced
  names:
    kind: Shipment
    plural: shipments
    singular: shipment
    shortNames: ["shp"]
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["destination", "weightKg"]
            properties:
              destination:
                type: string
              weightKg:
                type: integer
                minimum: 1
    additionalPrinterColumns:
    - name: Destination
      type: string
      jsonPath: .spec.destination
YAML
# The CRD has to be established before the API server accepts an instance.
kubectl wait --for=condition=Established crd/shipments.logistics.ck-x.io --timeout=60s
kubectl apply -f - <<'YAML'
apiVersion: logistics.ck-x.io/v1
kind: Shipment
metadata:
  name: crate-1042
  namespace: crd-freight
spec:
  destination: rotterdam
  weightKg: 480
YAML

echo "== Question 9: DaemonSet =="
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-collector
  namespace: ds-fleet
spec:
  selector:
    matchLabels:
      app: node-collector
  template:
    metadata:
      labels:
        app: node-collector
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: collector
        image: busybox:1.36
        command: ["sleep", "86400"]
        volumeMounts:
        - name: host-log
          mountPath: /host/log
          readOnly: true
      volumes:
      - name: host-log
        hostPath:
          path: /var/log
YAML

echo "== Question 10: StatefulSet =="
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: ledger-db
  namespace: sts-ledger
spec:
  clusterIP: None
  selector:
    app: ledger-db
  ports:
  - port: 6379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ledger-db
  namespace: sts-ledger
spec:
  serviceName: ledger-db
  replicas: 2
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: ledger-db
  template:
    metadata:
      labels:
        app: ledger-db
    spec:
      containers:
      - name: db
        image: redis:7.4-alpine
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard
      resources:
        requests:
          storage: 100Mi
YAML

echo "== Question 11: CronJob =="
kubectl apply -f - <<'YAML'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: report-sweeper
  namespace: batch-reports
spec:
  schedule: "*/10 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 90
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: sweeper
            image: busybox:1.36
            command: ["sh", "-c", "echo sweeping; sleep 5"]
YAML
kubectl create job report-sweeper-manual --from=cronjob/report-sweeper -n batch-reports

echo "== Question 12: multi-port Service =="
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: telemetry
  namespace: svc-telemetry
spec:
  selector:
    app: telemetry
  ports:
  - name: web
    port: 80
    targetPort: http
  - name: metrics
    port: 9100
    targetPort: metrics
YAML

echo "== Question 13: CoreDNS rewrite =="
kubectl get configmap coredns -n kube-system -o json \
  | jq '.data.Corefile |= sub("\\.:53 \\{\n"; ".:53 {\n    rewrite name ledger.corp.internal ledger.dns-alias.svc.cluster.local\n")' \
  | kubectl apply -f - >/dev/null
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=90s

echo "== Question 14: StorageClass =="
kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: bulk-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bulk-data
  namespace: stor-bulk
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: bulk-retain
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: bulk-writer
  namespace: stor-bulk
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "date > /bulk/started; sleep 86400"]
    volumeMounts:
    - name: bulk
      mountPath: /bulk
  volumes:
  - name: bulk
    persistentVolumeClaim:
      claimName: bulk-data
YAML

echo "== Question 15: rebind archive-claim =="
kubectl delete pvc archive-claim -n ts-storage --wait=true
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive-claim
  namespace: ts-storage
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: archive
  resources:
    requests:
      storage: 1Gi
YAML

echo "== Question 16: raise the memory limit =="
kubectl patch deployment render-worker -n ts-memory --type strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"renderer","resources":{"limits":{"memory":"128Mi"}}}]}}}}'

echo "== done =="
