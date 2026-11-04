# CKA Practice Lab 003 — Answers

Every solution below is written for the exam jumphost (`ckad9999`), where `kubectl` and `helm` already point at the exam cluster.

---

## Question 1: Manual PersistentVolume, PersistentVolumeClaim and Pod

```bash
cat <<EOF | kubectl apply -f -
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
```

The claim binds to `logs-pv` because both sides agree on `storageClassName: manual`, the access mode and a capacity that is large enough. Static binding is driven entirely by that match — there is no provisioner behind the `manual` class. `Retain` means the volume is not deleted when the claim goes away, and `DirectoryOrCreate` lets the kubelet create `/mnt/logs-data` on the node instead of failing when the directory is missing.

Verify with:

```bash
kubectl get pvc logs-pvc -n storage-manual
kubectl get pod log-writer -n storage-manual
```

---

## Question 2: Dynamic provisioning with a custom StorageClass

```bash
cat <<EOF | kubectl apply -f -
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
```

Do **not** add the `storageclass.kubernetes.io/is-default-class: "true"` annotation — the task explicitly forbids it, and the existing default class must stay untouched.

`WaitForFirstConsumer` means the PVC stays `Pending` until a Pod that uses it is scheduled. That is expected: create the Pod and the claim becomes `Bound` moments later. If you check the PVC before creating the Pod and see `Pending`, nothing is wrong.

---

## Question 3: DaemonSet on every node

```bash
cat <<EOF | kubectl apply -f -
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
```

A toleration with only `operator: Exists` — no `key` and no `effect` — matches *every* taint, which is what makes the DaemonSet land on tainted nodes too. This is the same trick the cluster's own system DaemonSets use.

Check the rollout with:

```bash
kubectl get daemonset log-agent -n node-agents
kubectl get nodes
```

`DESIRED` must equal the number of nodes and `READY` must equal `DESIRED`.

---

## Question 4: CronJob and a manually triggered Job

```bash
cat <<EOF | kubectl apply -f -
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
```

Then trigger it once without waiting for the schedule:

```bash
kubectl create job db-backup-manual --from=cronjob/db-backup -n batch-jobs
kubectl get job db-backup-manual -n batch-jobs
```

`--from=cronjob/...` copies the CronJob's `jobTemplate` into a standalone Job, which is exactly how an on-demand run is triggered in practice. The history limits control how many finished Jobs the CronJob keeps around; they do not affect the manual Job.

---

## Question 5: Deployment with a topology spread constraint

```bash
cat <<EOF | kubectl apply -f -
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
```

`maxSkew: 1` asks the scheduler to keep the number of matching Pods per node within one of each other. `ScheduleAnyway` makes the constraint a preference rather than a hard requirement, so Pods still get scheduled when the cluster cannot satisfy the spread — with `DoNotSchedule` they would sit in `Pending` instead.

---

## Question 6: Deployment, Service and Ingress

```bash
cat <<EOF | kubectl apply -f -
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
```

The chain only works if all three layers agree: the Service selector must match the Pod labels, and the Ingress backend must name the Service and a port the Service actually exposes. Confirm the Service found its Pods before blaming the Ingress:

```bash
kubectl get endpointslice -n web-shop -l kubernetes.io/service-name=shop-web-svc
```

---

## Question 7: NetworkPolicy restricting ingress to the backend

```bash
cat <<EOF | kubectl apply -f -
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
```

Once any Ingress policy selects a Pod, that Pod is isolated: everything not explicitly allowed is denied. So this single rule both permits `app=frontend` and blocks `app=monitoring` — no separate deny rule is needed.

Test both directions:

```bash
BACKEND_IP=$(kubectl get pod backend -n net-guard -o jsonpath='{.status.podIP}')
kubectl exec frontend -n net-guard -- wget -q -T 5 -O- http://$BACKEND_IP:80
kubectl exec monitoring -n net-guard -- wget -q -T 5 -O- http://$BACKEND_IP:80   # must time out
```

---

## Question 8: NodePort Service

```bash
cat <<EOF | kubectl apply -f -
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
```

`nodePort` must be inside the cluster's node port range (30000–32767 by default); if you omit it the API server assigns a random one, which would not satisfy the task. `port` is the Service's own cluster port and `targetPort` is the container port — here they happen to be identical.

---

## Question 9: RBAC for an automation account

```bash
kubectl create serviceaccount deploy-bot -n ops-rbac

kubectl create clusterrole deployment-reader \
  --verb=get,list,watch \
  --resource=deployments.apps,replicasets.apps

kubectl create rolebinding deploy-bot-reader \
  --clusterrole=deployment-reader \
  --serviceaccount=ops-rbac:deploy-bot \
  -n ops-rbac
```

Binding a ClusterRole with a **RoleBinding** is the idiomatic way to reuse one cluster-wide permission set while keeping the grant scoped to a single namespace. The same ClusterRole bound with a ClusterRoleBinding would have granted access in every namespace.

Verify the scope:

```bash
kubectl auth can-i list deployments --as=system:serviceaccount:ops-rbac:deploy-bot -n ops-rbac   # yes
kubectl auth can-i list deployments --as=system:serviceaccount:ops-rbac:deploy-bot -n default    # no
```

---

## Question 10: Install a local Helm chart

```bash
helm install webstack /tmp/exam/q10/webstack \
  --namespace helm-apps \
  --set replicaCount=3 \
  --set image.tag=1.27.4

helm list -n helm-apps
kubectl get deployment webstack-web -n helm-apps
```

Helm can install straight from a chart directory — no repository is involved. `--set` overrides individual values from `values.yaml` at install time, which is why the rendered Deployment ends up with 3 replicas and `nginx:1.27.4` even though the chart defaults are 1 and `1.26.3`.

If you need to inspect what Helm would produce before installing:

```bash
helm template webstack /tmp/exam/q10/webstack --set replicaCount=3 --set image.tag=1.27.4
```

---

## Question 11: CustomResourceDefinition and a custom resource

```bash
kubectl apply -f /tmp/exam/q11/backupjob-crd.yaml
kubectl wait --for=condition=Established --timeout=60s crd/backupjobs.ops.example.com

cat <<EOF | kubectl apply -f -
apiVersion: ops.example.com/v1
kind: BackupJob
metadata:
  name: nightly-db
  namespace: crd-lab
spec:
  schedule: "0 2 * * *"
  retention: 7
EOF
```

The custom resource's `apiVersion` is built from the CRD's `spec.group` and the version name: `ops.example.com/v1`. The API server only starts serving that endpoint once the CRD reports the `Established` condition, so applying the custom resource immediately after the CRD can fail — waiting for the condition avoids the race.

```bash
kubectl get backupjobs -n crd-lab
kubectl get bj nightly-db -n crd-lab -o yaml
```

---

## Question 12: Node maintenance with cordon and drain

```bash
kubectl drain k3d-cluster-agent-1 --ignore-daemonsets --delete-emptydir-data --force --timeout=180s

kubectl patch deployment legacy-app -n drain-lab \
  --type=json \
  -p '[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]'

kubectl rollout status deployment/legacy-app -n drain-lab
```

`kubectl drain` cordons the node first (so nothing new is scheduled there) and then evicts the existing Pods. `--ignore-daemonsets` is required because DaemonSet Pods are immediately recreated on the node and would otherwise block the drain; `--delete-emptydir-data` acknowledges that data in emptyDir volumes is lost.

The `maintenance=reserved:NoSchedule` taint on the node keeps every other workload away, so `legacy-app` and the cluster's DaemonSets are the only things the drain has to move. Leave that taint alone — removing it would let other Pods drift back onto a node that is supposed to be out of service.

The drain alone is not enough here: `legacy-app` is pinned to the drained node by its `nodeSelector`, so its Pods would stay `Pending` forever. Removing the `nodeSelector` lets the scheduler place them on the remaining nodes. Leave the node cordoned — `kubectl uncordon` would undo the maintenance state the task asks for.

---

## Question 13: Pods that never pull their image

```bash
kubectl get pods -n ts-image
kubectl describe pod -n ts-image -l app=billing-api | grep -A5 Events
```

The events show `ErrImagePull` / `ImagePullBackOff`: the tag `nginx:1.99-not-real` does not exist. Fix the tag only:

```bash
kubectl set image deployment/billing-api api=nginx:1.27.4 -n ts-image
kubectl rollout status deployment/billing-api -n ts-image
```

`kubectl set image` targets the container by name, so it cannot accidentally rename the container or change the replica count.

---

## Question 14: envFrom pointing at a missing ConfigMap

```bash
kubectl get pods -n ts-config
kubectl describe pod -n ts-config -l app=payments-worker | grep -A5 Events
kubectl get configmaps -n ts-config
```

The Pods sit in `CreateContainerConfigError` because `envFrom` references `payments-config`, while the ConfigMap in the namespace is called `payments-cfg`. Point the Deployment at the ConfigMap that exists:

```bash
kubectl patch deployment payments-worker -n ts-config \
  --type=json \
  -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/envFrom/0/configMapRef/name", "value": "payments-cfg"}]'

kubectl rollout status deployment/payments-worker -n ts-config
```

Creating a second ConfigMap named `payments-config` would also make the Pods start, but it is explicitly forbidden — and in the real world it leaves you with two sources of truth for the same configuration.

Confirm the variables actually reach the container:

```bash
POD=$(kubectl get pods -n ts-config -l app=payments-worker -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -n ts-config -- printenv PAYMENT_MODE
```

---

## Question 15: Service with no endpoints

```bash
kubectl get endpointslice -n ts-service -l kubernetes.io/service-name=catalog-svc
kubectl describe svc catalog-svc -n ts-service
kubectl get pods -n ts-service --show-labels
```

Two things are wrong: the Service selects `app=catalog-api` while the Pods are labelled `app=catalog`, and it forwards to port `8080` while the containers listen on `80`.

```bash
kubectl patch svc catalog-svc -n ts-service \
  -p '{"spec": {"selector": {"app": "catalog"}, "ports": [{"protocol": "TCP", "port": 80, "targetPort": 80}]}}'
```

A strategic-merge patch on `spec.ports` replaces the whole list, so the port entry must be given in full. Re-check the endpoints — three ready addresses should appear immediately:

```bash
kubectl get endpointslice -n ts-service -l kubernetes.io/service-name=catalog-svc -o yaml
```

Note that the Deployment itself is correct and must not be touched: relabelling the Pods would "fix" the symptom while leaving the Service misconfigured.

---

## Question 16: Pods left Pending by a node taint

```bash
kubectl get pods -n ts-sched -o wide
kubectl describe pod -n ts-sched -l app=analytics | grep -A5 Events
kubectl describe node k3d-cluster-agent-0 | grep -i taint
```

The scheduler reports that the only node allowed by the `nodeSelector` has the taint `workload=analytics:NoSchedule`. Add the matching toleration:

```bash
kubectl patch deployment analytics -n ts-sched \
  --type=json \
  -p '[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "workload", "operator": "Equal", "value": "analytics", "effect": "NoSchedule"}]}]'

kubectl rollout status deployment/analytics -n ts-sched
kubectl get pods -n ts-sched -o wide
```

Removing the taint would also start the Pods, but it opens the node up to every other workload in the cluster — which is precisely what the taint was there to prevent. Tolerations belong on the workload that is meant to run there.

---

## Question 17: Liveness probe killing healthy Pods

```bash
kubectl get pods -n ts-probe
kubectl describe pod -n ts-probe -l app=frontend | grep -A10 Events
```

The events show repeated `Liveness probe failed: ... connection refused` followed by `Killing container`. The probe targets `/healthz` on port `8080`, but nginx serves `/` on port `80`, so the kubelet keeps restarting a container that was never unhealthy.

```bash
kubectl patch deployment frontend -n ts-probe \
  --type=json \
  -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/path", "value": "/"},
       {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": 80}]'

kubectl rollout status deployment/frontend -n ts-probe
kubectl get pods -n ts-probe
```

Keep `initialDelaySeconds` and `periodSeconds` as they are — the timing was never the problem. Deleting the probe would stop the restarts too, but it would also remove the cluster's ability to detect a genuinely hung container.
