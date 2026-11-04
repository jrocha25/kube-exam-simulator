#!/bin/bash

# answers.md converted to answers.sh for quick testing of the cka-003 lab.
# Run it on the exam jumphost with KUBECONFIG pointing at the exam cluster.

echo "Implementing Question 1: manual PV, PVC and Pod"
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: logs-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/logs-data
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: logs-pvc
  namespace: storage-manual
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: log-writer
  namespace: storage-manual
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /data/app.log; sleep 5; done"]
    volumeMounts:
    - name: logs
      mountPath: /data
  volumes:
  - name: logs
    persistentVolumeClaim:
      claimName: logs-pvc
EOF

echo "Implementing Question 2: custom StorageClass with dynamic provisioning"
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: retain-local
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive-pvc
  namespace: storage-dynamic
spec:
  storageClassName: retain-local
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: archiver
  namespace: storage-dynamic
spec:
  containers:
  - name: archiver
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts:
    - name: archive
      mountPath: /archive
  volumes:
  - name: archive
    persistentVolumeClaim:
      claimName: archive-pvc
EOF

echo "Implementing Question 3: DaemonSet on every node"
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  namespace: node-agents
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      tolerations:
      - operator: Exists
      containers:
      - name: agent
        image: busybox:1.36
        command: ["sh", "-c", "while true; do sleep 30; done"]
EOF

echo "Implementing Question 4: CronJob and manual Job"
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: batch-jobs
spec:
  schedule: "*/5 * * * *"
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: busybox:1.36
            command: ["sh", "-c", "echo backup completed"]
EOF
kubectl create job db-backup-manual --from=cronjob/db-backup -n batch-jobs

echo "Implementing Question 5: Deployment with a topology spread constraint"
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spread-web
  namespace: spread-lab
spec:
  replicas: 4
  selector:
    matchLabels:
      app: spread-web
  template:
    metadata:
      labels:
        app: spread-web
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: spread-web
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

echo "Implementing Question 6: Deployment, Service and Ingress"
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-web
  namespace: web-shop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: shop-web
  template:
    metadata:
      labels:
        app: shop-web
    spec:
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: shop-web-svc
  namespace: web-shop
spec:
  type: ClusterIP
  selector:
    app: shop-web
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-web-ing
  namespace: web-shop
spec:
  ingressClassName: traefik
  rules:
  - host: shop.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: shop-web-svc
            port:
              number: 80
EOF

echo "Implementing Question 7: NetworkPolicy protecting the backend"
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: net-guard
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 80
EOF

echo "Implementing Question 8: NodePort Service"
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: cache-svc
  namespace: cache-tier
spec:
  type: NodePort
  selector:
    app: cache
  ports:
  - protocol: TCP
    port: 6379
    targetPort: 6379
    nodePort: 31379
EOF

echo "Implementing Question 9: RBAC for the deploy-bot service account"
kubectl create serviceaccount deploy-bot -n ops-rbac
kubectl create clusterrole deployment-reader \
  --verb=get,list,watch \
  --resource=deployments.apps,replicasets.apps
kubectl create rolebinding deploy-bot-reader \
  --clusterrole=deployment-reader \
  --serviceaccount=ops-rbac:deploy-bot \
  -n ops-rbac

echo "Implementing Question 10: install the local Helm chart"
helm install webstack /tmp/exam/q10/webstack \
  --namespace helm-apps \
  --set replicaCount=3 \
  --set image.tag=1.27.4

echo "Implementing Question 11: CRD and custom resource"
kubectl apply -f /tmp/exam/q11/backupjob-crd.yaml
kubectl wait --for=condition=Established --timeout=60s crd/backupjobs.ops.example.com
cat <<'EOF' | kubectl apply -f -
apiVersion: ops.example.com/v1
kind: BackupJob
metadata:
  name: nightly-db
  namespace: crd-lab
spec:
  schedule: "0 2 * * *"
  retention: 7
EOF

echo "Implementing Question 12: drain the maintenance node"
kubectl drain k3d-cluster-agent-1 --ignore-daemonsets --delete-emptydir-data --timeout=180s
kubectl patch deployment legacy-app -n drain-lab \
  --type=json \
  -p '[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]'

echo "Implementing Question 13: fix the broken image tag"
kubectl set image deployment/billing-api api=nginx:1.27.4 -n ts-image

echo "Implementing Question 14: point envFrom at the existing ConfigMap"
kubectl patch deployment payments-worker -n ts-config \
  --type=json \
  -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/envFrom/0/configMapRef/name", "value": "payments-cfg"}]'

echo "Implementing Question 15: fix the Service selector and target port"
kubectl patch svc catalog-svc -n ts-service \
  -p '{"spec": {"selector": {"app": "catalog"}, "ports": [{"protocol": "TCP", "port": 80, "targetPort": 80}]}}'

echo "Implementing Question 16: tolerate the analytics taint"
kubectl patch deployment analytics -n ts-sched \
  --type=json \
  -p '[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "workload", "operator": "Equal", "value": "analytics", "effect": "NoSchedule"}]}]'

echo "Implementing Question 17: fix the liveness probe"
kubectl patch deployment frontend -n ts-probe \
  --type=json \
  -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/path", "value": "/"}, {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": 80}]'

echo "Waiting for all workloads to settle"
kubectl rollout status deployment/spread-web -n spread-lab --timeout=300s
kubectl rollout status deployment/shop-web -n web-shop --timeout=300s
kubectl rollout status deployment/webstack-web -n helm-apps --timeout=300s
kubectl rollout status deployment/legacy-app -n drain-lab --timeout=300s
kubectl rollout status deployment/billing-api -n ts-image --timeout=300s
kubectl rollout status deployment/payments-worker -n ts-config --timeout=300s
kubectl rollout status deployment/analytics -n ts-sched --timeout=300s
kubectl rollout status deployment/frontend -n ts-probe --timeout=300s
kubectl rollout status daemonset/log-agent -n node-agents --timeout=300s
kubectl wait --for=condition=Ready pod/log-writer -n storage-manual --timeout=300s
kubectl wait --for=condition=Ready pod/archiver -n storage-dynamic --timeout=300s
kubectl wait --for=condition=Complete job/db-backup-manual -n batch-jobs --timeout=300s

echo "All answers applied"
