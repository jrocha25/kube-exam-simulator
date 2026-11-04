# CKA Practice Lab 010 — Answers

Every solution below is written for the exam jumphost (`ckad9999`), where `kubectl` already points at the exam cluster.

This lab runs on a **kubeadm** cluster, not k3s, which is what makes most of the first half possible at all. Three workers and the control plane are reachable over SSH with no password:

```bash
ssh controlplane     # the control plane: /etc/kubernetes/manifests, kubeadm, crictl
ssh node01           # first worker  -- question 6
ssh node02           # second worker -- question 5
ssh node03           # third worker  -- question 2 (not in the cluster when you start)
```

Questions 1 and 3 are set on a **second, separate cluster**, one Kubernetes minor behind this one, reached the same way:

```bash
ssh aux              # the auxiliary cluster's only node; kubectl there is already configured
```

You land as `root`, so no `sudo` is needed — but on the real exam you will `ssh node01` then `sudo -i`, so it is worth typing anyway.

The three workers are not interchangeable in this lab. `node02` carries question 5's fault and is `NotReady` until you fix it. `node03` is question 2's target and is not part of the cluster until you rejoin it. `node01` is healthy throughout and is where question 6's static Pod goes. Nothing stops you from using them differently, but the questions are written around that split, and nothing else in the lab is pinned to a worker.

Five of the sixteen questions (5, 7, 15, 16 and — arguably — 2) start from something that is already broken. Each of those answers opens with the commands that find the fault before it shows the fix; on the real exam nobody tells you what is wrong, and the diagnosis is most of the work.

**Do question 3 before question 1.** Both are on the auxiliary cluster. A restore rolls that cluster's data back to the moment the snapshot was taken, which was *before* the exam started — so if you upgrade first and restore second, every object the upgrade wrote through the API (the `kubeadm-config` and `kubelet-config` ConfigMaps, the `kube-proxy` DaemonSet, the CoreDNS Deployment) reverts to 1.33 while the binaries and static Pods stay at 1.34. That cluster still grades as upgraded, because the grading reads the static Pods and the kubelet, and it still grades as restored. But a real cluster in that state is a mess, and nothing about the order costs you anything the other way round. Restore, then upgrade.

---

## Question 1: Upgrading a cluster with kubeadm

Everything here runs on the auxiliary node:

```bash
ssh aux
kubectl get nodes
kubeadm version -o short
apt-mark showhold
cat /etc/apt/sources.list.d/kubernetes.list
```

```
NAME                        STATUS   ROLES           AGE   VERSION
cluster-aux-control-plane   Ready    control-plane   20m   v1.33.12
v1.33.12
kubeadm
kubectl
kubelet
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /
```

The packages come from the Kubernetes apt repository, and that repository is **per minor**: the `v1.33` channel will never offer a 1.34 package. So the first step of every kubeadm upgrade is pointing apt at the next minor, and it is the step people forget:

```bash
sed -i 's#/v1\.33/#/v1.34/#' /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-cache madison kubeadm | head -3
```

The signing key is the same for every channel, so nothing else in the repo configuration changes.

**Control plane first.** kubeadm is upgraded on its own and does the rest:

```bash
apt-mark unhold kubeadm
apt-get install -y kubeadm='1.34.10-*'
apt-mark hold kubeadm
kubeadm version -o short          # v1.34.10

kubeadm upgrade plan
kubeadm upgrade apply v1.34.10
```

`upgrade plan` shows what it will do — including that etcd moves from 3.5 to 3.6 and CoreDNS gets a patch release — and `upgrade apply` does it: pulls the 1.34.10 images, rewrites the static Pod manifests under `/etc/kubernetes/manifests` one component at a time, waits for each to come back, and updates the `kubeadm-config` ConfigMap, the RBAC for bootstrap tokens, `kube-proxy` and CoreDNS. It takes a few minutes, most of which is image pulls. It ends with `[upgrade] SUCCESS!`.

Note what it did **not** do: `kubectl get nodes` still shows `v1.33.12`. That column is the kubelet's version, and the kubelet is a package on the node, not a Pod the control plane manages.

**Then the kubelet**, on the node that is now running a newer control plane. The procedure is drain, upgrade the packages, restart, uncordon — the same on a control plane node as on a worker:

```bash
kubectl drain cluster-aux-control-plane --ignore-daemonsets

apt-mark unhold kubelet kubectl
apt-get install -y kubelet='1.34.10-*' kubectl='1.34.10-*'
apt-mark hold kubelet kubectl

systemctl daemon-reload
systemctl restart kubelet
```

Restarting the kubelet also restarts every static Pod it runs — the API server included — so `kubectl` will refuse connections for ten or twenty seconds. Wait it out, then:

```bash
kubectl uncordon cluster-aux-control-plane
kubectl get nodes                                   # v1.34.10
kubectl get pods -n kube-system -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
apt-mark showhold                                   # all three, again
```

Two things worth carrying away. The version pin in `apt-get install kubeadm='1.34.10-*'` matters: without it apt installs the newest 1.34.x in the channel, which is not what the question asked for, and `kubeadm upgrade apply` then refuses to go to a version newer than the kubeadm binary. And `apt-mark hold` is not decoration — an unattended `apt-get upgrade` on a node whose packages are not held will happily move the kubelet a minor ahead of its control plane, which is a supported-skew violation the cluster will not warn you about until something breaks.

---

## Question 2: Rejoining a node with kubeadm

```bash
kubectl get nodes
ssh node03
systemctl status kubelet
ls /etc/kubernetes
```

The node is missing from the cluster, the kubelet is `inactive`, and `/etc/kubernetes` holds only empty `manifests` and `pki` directories — no `kubelet.conf`, no `bootstrap-kubelet.conf`. That is what a node looks like after `kubeadm reset`. Joining it back needs three things from the control plane: the API server endpoint, a bootstrap token, and the hash of the CA certificate. `kubeadm` prints all three in one line:

```bash
ssh controlplane
kubeadm token create --print-join-command
```

```
kubeadm join cluster-control-plane:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:...
```

Tokens are short-lived (24 hours by default) and the ones the cluster was built with have long expired, which is why you create one rather than look one up. Run the printed command on the node:

```bash
ssh node03
kubeadm join cluster-control-plane:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:...
```

```
[kubelet-start] Starting the kubelet
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap
This node has joined the cluster:
```

The join writes the kubelet's configuration and kubeconfig, starts the kubelet, and the kubelet bootstraps its own client certificate through a CSR the control plane auto-approves. Back on the jumphost:

```bash
kubectl get nodes
kubectl get pods -n kube-system -o wide | grep worker3
```

The node appears within seconds and turns `Ready` as soon as the Calico DaemonSet has started a Pod on it — that is the "network add-on" the question mentions, and it is why the node is `NotReady` for the first few seconds. No CNI, no Ready. Nothing needs uncordoning: a freshly joined node is schedulable.

If the join complained about preflight checks (it did not, here), the checks it runs are the same ones kind skipped when it built the cluster, and `--ignore-preflight-errors=all` is the exam-time answer.

---

## Question 3: etcd backup and restore

On the auxiliary node. etcd is a static Pod, and its manifest is where the certificate paths live:

```bash
ssh aux
grep -E 'data-dir|cert-file|key-file|trusted-ca-file|listen-client' /etc/kubernetes/manifests/etcd.yaml
```

```
--cert-file=/etc/kubernetes/pki/etcd/server.crt
--data-dir=/var/lib/etcd
--key-file=/etc/kubernetes/pki/etcd/server.key
--listen-client-urls=https://127.0.0.1:2379,...
--trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
```

**First the backup of the current state**, which the question asks for before anything else — and which is what you would want in real life before restoring over a cluster:

```bash
export ETCDCTL_API=3
etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup/before-restore.db

etcdutl snapshot status /opt/etcd-backup/before-restore.db
```

**Then the restore.** A restore never happens *over* a running etcd. Stop it — and stop the rest of the control plane with it, for a reason that becomes clear in a moment. They are static Pods, so "stop" means moving the manifests out of the directory the kubelet watches:

```bash
mkdir -p /root/manifests
mv /etc/kubernetes/manifests/*.yaml /root/manifests/
crictl ps                      # etcd, kube-apiserver, controller-manager, scheduler all gone after ~20s
```

`kubectl` is unavailable from here until they are back. Move the old data directory aside and restore the snapshot into the original path, since the question requires etcd to keep serving from `/var/lib/etcd`:

```bash
mv /var/lib/etcd /var/lib/etcd.pre-restore
etcdutl snapshot restore /opt/etcd-backup/aux-snapshot.db --data-dir /var/lib/etcd
mv /root/manifests/*.yaml /etc/kubernetes/manifests/
crictl ps                      # all four back
```

Restoring into the original directory is what makes the answer survive question 1 in either order: `kubeadm upgrade apply` regenerates `etcd.yaml` from the cluster configuration, whose data directory is `/var/lib/etcd`, and a restore that had gone to `/var/lib/etcd-restored` would be silently abandoned by the regenerated manifest.

Now the part most people miss. Had you moved only `etcd.yaml` and left the API server running, this is what you would see afterwards:

```
$ kubectl get cm -n etcd-restore
NAME                 DATA   AGE
kube-root-ca.crt     1      25m
migration-scratch    1      12m
```

**Nothing changed** — because the API server answers from a watch cache it filled from the *old* etcd, and every other component (controller manager, scheduler, kubelet) is sitting on a watch that waits for resource versions the restored etcd will never reach. etcd's revision counter went *backwards*, and nothing that was connected before notices. The documentation's post-restore instruction is to restart all of them. Taking the manifests out and back in restarted three of the four; the kubelet is the one that is not a static Pod, and a kubelet that merely restarts *re-adopts* running static Pods rather than recreating them, so it has to be restarted on its own, after the new API server is up:

```bash
systemctl restart kubelet
```

Give it a minute before moving on to anything else on this cluster. The API server answers a few seconds before its RBAC cache is warm (every request is `Forbidden` until then), and the controller manager and scheduler have to wait out the stale leader leases the snapshot brought back before they do anything. `kubeadm upgrade plan`, run too soon after this, fails its own preflight with `Job "upgrade-health-check-…" did not complete in 15s` — that is a cluster that is not finished restarting, not a broken upgrade. The quickest proof that everything is back is a Pod that runs:

```bash
kubectl get cm -n etcd-restore
kubectl run probe --image=busybox:1.36 --restart=Never -- sleep 60
kubectl get pod probe -w           # Running
kubectl delete pod probe
```

```
NAME               DATA   AGE
kube-root-ca.crt   1      25m
ledger-state       2      25m
```

`ledger-state` is back with the contents it had when the snapshot was taken, `migration-scratch` — created after it — is gone. The grading also checks etcd's own cluster id, which `snapshot restore` regenerates — a ConfigMap recreated by hand has the right name and the wrong cluster id — and that the cluster can still start a Pod, which is the check a forgotten kubelet restart fails.

---

## Question 4: Renewing the control plane certificates

```bash
ssh controlplane
kubeadm certs check-expiration
```

The table lists every certificate kubeadm manages — the API server's serving cert, its client certs for etcd and the kubelets, the front-proxy client, etcd's own three, and the client certificates embedded in `admin.conf`, `super-admin.conf`, `controller-manager.conf` and `scheduler.conf` — with a year to run on each, plus the CAs, which it does not touch. Renewing them all is one command:

```bash
kubeadm certs renew all
kubeadm certs check-expiration
```

Every non-CA line now shows a fresh expiry a year out. But the files on disk are not what the components are using: each of them read its certificate when it started and holds it in memory. The question says so, and `kubeadm` says so at the end of its own output — *restart the control plane components*. They are static Pods, so the restart is the manifest shuffle:

```bash
mkdir -p /root/manifests
mv /etc/kubernetes/manifests/kube-{apiserver,controller-manager,scheduler}.yaml /root/manifests/
crictl ps | grep -E 'kube-(apiserver|controller|scheduler)'    # gone after ~20s
mv /root/manifests/*.yaml /etc/kubernetes/manifests/
```

`crictl rm -f` on the three containers does the same thing faster — the kubelet recreates a static Pod's container the moment it disappears. Either way, once the API server is back, prove it from the jumphost:

```bash
echo | openssl s_client -connect k8s-api-server:6443 2>/dev/null | openssl x509 -noout -enddate
```

That date has to match `apiserver.crt` on the node, which is exactly what is graded: a renewed file that the running server does not present is not a renewed certificate.

Your own `kubectl` on the jumphost keeps working throughout, even though `admin.conf` was renewed: the old client certificate is still valid until its original expiry, and Kubernetes does not revoke certificates. That is also why renewing certificates is not a way to lock a leaked credential out.

---

## Question 5: A NotReady node

```bash
kubectl get nodes
kubectl get pods -n node-outage -o wide
kubectl describe node cluster-worker2 | grep -A8 Conditions
```

`node02` is `NotReady` with `Kubelet stopped posting node status`, and the `sensor-relay` Pods are either `Pending` (evicted and recreated, nowhere to go) or `Terminating`. Everything about a NotReady node is on the node:

```bash
ssh node02
systemctl status kubelet
journalctl -u kubelet -n 30 --no-pager
```

The unit is `activating (auto-restart)` — it starts, fails, and systemd tries again every ten seconds. The log names the reason:

```
"command failed" err="failed to run Kubelet: ... unable to load client CA file /etc/kubernetes/pki/ca.pem: open /etc/kubernetes/pki/ca.pem: no such file or directory"
```

The kubelet's configuration points at a CA file that does not exist. The file that does exist is right next to it:

```bash
ls /etc/kubernetes/pki/
grep -n clientCAFile /var/lib/kubelet/config.yaml
```

```
ca.crt
    clientCAFile: /etc/kubernetes/pki/ca.pem
```

Fix the path, make sure the unit will survive a reboot, and restart:

```bash
sed -i 's#/etc/kubernetes/pki/ca.pem#/etc/kubernetes/pki/ca.crt#' /var/lib/kubelet/config.yaml
systemctl enable kubelet
systemctl restart kubelet
systemctl is-active kubelet     # active
```

Back on the jumphost the node turns `Ready` within a few seconds and the two `Pending` replicas schedule onto it:

```bash
kubectl get nodes
kubectl get pods -n node-outage -o wide
```

The fault could have been anything the kubelet reads at start — a wrong `--kubeconfig` path in the unit's drop-in, a mangled `config.yaml`, a stopped and disabled unit — and the diagnosis is the same every time: `systemctl status`, then `journalctl -u kubelet`. The Deployment was never the problem and was not to be touched.

---

## Question 6: A static Pod

Static Pods are run by the kubelet from manifests in a directory it watches, and that directory is set in the kubelet's configuration:

```bash
ssh node01
grep staticPodPath /var/lib/kubelet/config.yaml
```

```
staticPodPath: /etc/kubernetes/manifests
```

Write the manifest there. `hostPort` is what publishes a container port on the node:

```bash
cat > /etc/kubernetes/manifests/edge-cache.yaml <<'YAML'
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
YAML
```

The kubelet picks the file up within seconds. Check on the node first, then through the API server:

```bash
crictl ps | grep cache
curl -s http://localhost:8080 | grep title
```

```bash
kubectl get pods -n static-edge
```

```
NAME                          READY   STATUS    RESTARTS   AGE
edge-cache-cluster-worker     1/1     Running   0          20s
```

The `-cluster-worker` suffix is the tell: the API object is a *mirror* Pod the kubelet creates so the static Pod shows up in `kubectl`, and it is named after the node. Deleting the mirror does nothing — the kubelet recreates it — and `kubectl edit` on it is ignored; the manifest on the node is the only source of truth. Equally, the namespace in the manifest has to exist, or the Pod runs on the node with no mirror at all and looks like it was never created.

---

## Question 7: A broken kubeconfig

```bash
kubectl --kubeconfig /tmp/exam/q7/release.kubeconfig get pods -n kcfg-release
```

```
error: auth info "release-bot" does not exist
```

That is a kubeconfig *structure* error, raised before any connection is made: the current context names a user entry that the file does not define. Look at what it does define:

```bash
kubectl --kubeconfig /tmp/exam/q7/release.kubeconfig config view
```

```yaml
contexts:
- context:
    cluster: lab
    namespace: kcfg-release
    user: release-bot
  name: release@lab
current-context: release@lab
users:
- name: releasebot
  user:
    token: REDACTED
```

The user entry is called `releasebot`; the context asks for `release-bot`. Point the context at the entry that exists — either name is fine, the question only fixes the context's name:

```bash
kubectl --kubeconfig /tmp/exam/q7/release.kubeconfig config set-context release@lab --user=releasebot
kubectl --kubeconfig /tmp/exam/q7/release.kubeconfig get pods -n kcfg-release
```

```
Unable to connect to the server: tls: failed to verify certificate: x509: certificate signed by unknown authority
```

A second, different fault, only visible once the first is out of the way. The CA in the file is the lab cluster's — compare `certificate-authority-data` with the one in `~/.kube/kubeconfig` — so the certificate it is rejecting belongs to a *different* server. Compare the `server:` lines:

```bash
kubectl --kubeconfig /tmp/exam/q7/release.kubeconfig config view -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
kubectl config view -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
```

```
https://k8s-api-server:6444
https://k8s-api-server:6443
```

Port `6444` is another API server on the same host (the auxiliary cluster's, as it happens), with a certificate this CA never signed. Fix the port:

```bash
kubectl --kubeconfig /tmp/exam/q7/release.kubeconfig config set-cluster lab --server=https://k8s-api-server:6443
kubectl --kubeconfig /tmp/exam/q7/release.kubeconfig get pods -n kcfg-release
kubectl --kubeconfig /tmp/exam/q7/release.kubeconfig auth whoami
```

```
NAME             READY   STATUS    RESTARTS   AGE
release-canary   1/1     Running   0          30m
ATTRIBUTE   VALUE
Username    system:serviceaccount:kcfg-release:release-bot
```

`kubectl config set-*` edits the file in place, which is what keeps the context name and the current context intact; so does a text editor. `kubectl auth whoami` is the quickest way to confirm that a kubeconfig authenticates as who it should — errors from a missing user, a wrong CA and a wrong server all look different, and each one hides the ones behind it.

---

## Question 8: A CustomResourceDefinition

Everything the question lists maps onto a field of the CRD:

```bash
kubectl apply -f - <<'YAML'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: shipments.logistics.ck-x.io        # <plural>.<group>, always
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
```

`kubectl explain shipment.spec` works as soon as the CRD is established, and is a good check that the schema went in. Then the instance:

```bash
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

kubectl get shp -n crd-freight
```

```
NAME         DESTINATION
crate-1042   rotterdam
```

The schema is what is really being graded, and it is worth proving to yourself the way the grader does — by asking the API server to reject something, without persisting anything:

```bash
kubectl create --dry-run=server -f - <<'YAML'
apiVersion: logistics.ck-x.io/v1
kind: Shipment
metadata: {name: bad, namespace: crd-freight}
spec: {destination: oslo, weightKg: 0}
YAML
```

```
The Shipment "bad" is invalid: spec.weightKg: Invalid value: 0: spec.weightKg in body should be greater than or equal to 1
```

`required` lives on the *parent* object (`spec`), not on the fields themselves, and `minimum` only applies to numeric types — a `weightKg` declared as a string would accept `"0"` and `"heavy"` alike.

---

## Question 9: A DaemonSet on every node

The control plane node carries the `node-role.kubernetes.io/control-plane:NoSchedule` taint that kubeadm sets, and a DaemonSet does not get a pass on taints. It needs a toleration:

```bash
kubectl describe node cluster-control-plane | grep Taints
```

```bash
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

kubectl get pods -n ds-fleet -o wide
```

One Pod per schedulable node. If you have not yet solved questions 2 and 5, that is two workers plus the control plane; `node03` gets its Pod the moment it rejoins, and `node02` when its kubelet comes back — a DaemonSet's controller keeps trying, which is the whole point of the kind. The grading only looks at the control plane and `node01`.

`readOnly: true` goes on the *mount*, not the volume; a `hostPath` volume has no read-only setting of its own.

---

## Question 10: A StatefulSet

The headless Service has to exist for the StatefulSet's per-Pod DNS names to resolve, and the StatefulSet has to name it in `serviceName` — the two are wired together by that field, not by the selector:

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: ledger-db
  namespace: sts-ledger
spec:
  clusterIP: None                # headless
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
  podManagementPolicy: Parallel   # both at once, not ordinal by ordinal
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

kubectl get pods,pvc -n sts-ledger
```

```
pod/ledger-db-0   1/1   Running
pod/ledger-db-1   1/1   Running
persistentvolumeclaim/data-ledger-db-0   Bound
persistentvolumeclaim/data-ledger-db-1   Bound
```

The claims are named `<template>-<statefulset>-<ordinal>`. With the default `OrderedReady` policy the replicas come up one at a time, `ledger-db-1` only once `ledger-db-0` is ready; `podManagementPolicy: Parallel` starts them all at once, which is what the question asks for. Note that the policy governs creation and deletion only — rolling updates still go ordinal by ordinal. The claims outlive the Pods and the StatefulSet: deleting `ledger-db` leaves both claims behind, and recreating it picks them up again by name, which is the entire reason to use a StatefulSet over a Deployment.

---

## Question 11: A CronJob and a Job from it

```bash
kubectl apply -f - <<'YAML'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: report-sweeper
  namespace: batch-reports
spec:
  schedule: "*/10 * * * *"
  concurrencyPolicy: Forbid          # never overlap
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 1                # one retry
      activeDeadlineSeconds: 90      # then it is killed
      template:
        spec:
          restartPolicy: Never       # never restarted in place
          containers:
          - name: sweeper
            image: busybox:1.36
            command: ["sh", "-c", "echo sweeping; sleep 5"]
YAML
```

Three of those settings live at three different depths, and getting the depth wrong is the usual mistake: `concurrencyPolicy` and the history limits are properties of the *CronJob*; `backoffLimit` and `activeDeadlineSeconds` are properties of each *Job*; `restartPolicy` is a property of the *Pod*. `kubectl explain cronjob.spec.jobTemplate.spec` is the fastest way to check.

The manual run:

```bash
kubectl create job report-sweeper-manual --from=cronjob/report-sweeper -n batch-reports
kubectl get jobs -n batch-reports -w
```

```
NAME                    STATUS     COMPLETIONS   DURATION
report-sweeper-manual   Complete   1/1           9s
```

`--from` copies the CronJob's Job template and stamps the Job with `cronjob.kubernetes.io/instantiate: manual`, which is what the grading looks for — a Job written by hand to the same shape is not "created from" the CronJob, and on the real exam the wording is the same.

---

## Question 12: A multi-port Service with named target ports

Look at how the Pods declare their ports:

```bash
kubectl get deployment telemetry -n svc-telemetry -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{": "}{.ports}{"\n"}{end}'
```

```
web: [{"containerPort":80,"name":"http"}]
exporter: [{"containerPort":9100,"name":"metrics"}]
```

A Service with more than one port has to name each of them, and `targetPort` can be either a number or the *name* of a container port. The question asks for the name:

```bash
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

kubectl get endpointslice -n svc-telemetry -l kubernetes.io/service-name=telemetry
```

Naming the target port is not cosmetics. If the exporter is ever rebuilt to listen on `9200`, only the Deployment changes — the Service still says `metrics` and keeps working. With `targetPort: 9100` every Service pointing at it would have to be found and edited.

Prove it from inside the namespace, with a Pod that already exists:

```bash
IP=$(kubectl get svc telemetry -n svc-telemetry -o jsonpath='{.spec.clusterIP}')
POD=$(kubectl get pods -n svc-telemetry -l app=telemetry -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n svc-telemetry $POD -c exporter -- wget -qO- http://$IP:9100/metrics
kubectl exec -n svc-telemetry $POD -c exporter -- wget -qO- http://$IP:80/ | head -3
```

---

## Question 13: A legacy hostname in CoreDNS

Cluster DNS is CoreDNS, configured by the `Corefile` in a ConfigMap:

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

```
.:53 {
    errors
    health { lameduck 5s }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa { ... }
    prometheus :9153
    forward . /etc/resolv.conf { max_concurrent 1000 }
    cache 30
    loop
    reload
    loadbalance
}
```

The `rewrite` plugin rewrites a query's name before the other plugins see it, so a lookup for the legacy name becomes a lookup for the Service's real cluster-local name, which the `kubernetes` plugin then answers with the Service's cluster IP. Add one line inside the server block:

```bash
kubectl edit configmap coredns -n kube-system
```

```
.:53 {
    rewrite name ledger.corp.internal ledger.dns-alias.svc.cluster.local
    errors
    ...
```

CoreDNS has `reload` in that Corefile and picks the change up on its own within a couple of minutes, but the exam does not have a couple of minutes to spare:

```bash
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system
kubectl get svc ledger -n dns-alias
kubectl -n dns-alias exec resolver -- nslookup ledger.corp.internal
```

```
Name:      ledger.corp.internal
Address 1: 10.96.144.12 ledger.dns-alias.svc.cluster.local
```

The `hosts` plugin with the Service's IP written into it would also pass the grading, but it is the wrong tool: the IP is stable for the life of the Service and no longer, and a `hosts` entry is a hardcoded number nobody will remember to update. `rewrite` follows the Service.

If something in that edit goes wrong — a typo, a brace out of place — the symptom is every name in the cluster failing to resolve, and `kubectl logs -n kube-system deploy/coredns` says why. The second check on this question is exactly that: ordinary names still have to work.

---

## Question 14: A StorageClass with delayed binding

```bash
kubectl get storageclass
```

`standard` is the local-path provisioner kind ships with, and it will serve any StorageClass that names it:

```bash
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
```

Apply the claim without the Pod first and watch it: it sits `Pending` with the event `waiting for first consumer to be created before binding`. That is `WaitForFirstConsumer` doing its job — a local volume can only be created on the node the Pod lands on, so the provisioner waits for the scheduler. Once the Pod exists, claim and Pod converge together:

```bash
kubectl get pvc,pod -n stor-bulk
kubectl get pv -o custom-columns=NAME:.metadata.name,RECLAIM:.spec.persistentVolumeReclaimPolicy,CLAIM:.spec.claimRef.name
```

The PV inherits `Retain` from the class, which is what the last check reads. The default StorageClass is a matter of one annotation (`storageclass.kubernetes.io/is-default-class: "true"`), and the question asks you *not* to set it — `standard` stays the default.

---

## Question 15: A claim that never binds

```bash
kubectl get pvc,pv -n ts-storage
kubectl describe pvc archive-claim -n ts-storage | grep -A5 Events
```

```
Warning  ProvisioningFailed  storageclass.storage.k8s.io "archive-old" not found
```

The claim asks for a StorageClass that does not exist, so nothing will provision for it — and nothing will *bind* to it either, because binding only considers volumes of the same class. Compare the claim with the volume it was meant for:

```bash
kubectl get pv archive-pv -o jsonpath='{.spec.storageClassName} {.spec.accessModes} {.spec.capacity.storage}{"\n"}'
kubectl get pvc archive-claim -n ts-storage -o jsonpath='{.spec.storageClassName} {.spec.accessModes} {.spec.resources.requests.storage}{"\n"}'
```

```
archive ["ReadWriteOnce"] 1Gi
archive-old ["ReadWriteMany"] 1Gi
```

Two mismatches, not one: the class, and the access mode — the volume offers `ReadWriteOnce` and the claim demands `ReadWriteMany`, which a volume can never satisfy by being "more" than asked. Both fields are immutable on a claim, so the fix is to recreate it. The volume was not to be touched, and does not need to be:

```bash
kubectl delete pvc archive-claim -n ts-storage
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

kubectl get pvc,pod -n ts-storage
```

The claim binds to `archive-pv` within seconds, and the Pod — which was `Pending` on an unbound claim and needs no change — starts. Deleting the claim was allowed because the Pod was never scheduled: the `pvc-protection` finalizer only holds a claim that a *scheduled* Pod is using.

---

## Question 16: A container that keeps dying

```bash
kubectl get pods -n ts-memory
kubectl describe pod -n ts-memory -l app=render-worker | grep -B2 -A6 'Last State'
```

```
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
    Restart Count:  6
```

`OOMKilled` with exit code 137: the kernel killed the container for exceeding its memory limit. `kubectl logs --previous` shows it got as far as `loading working set` and never printed `ready` — it dies while allocating. Read the limit:

```bash
kubectl get deployment render-worker -n ts-memory -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```

```json
{"limits":{"memory":"32Mi"},"requests":{"cpu":"50m","memory":"16Mi"}}
```

A 40 MB working set under a 32 Mi limit. The approved limit is 128 Mi; the requests stay as they are:

```bash
kubectl patch deployment render-worker -n ts-memory --type strategic \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"renderer","resources":{"limits":{"memory":"128Mi"}}}]}}}}'
kubectl get pods -n ts-memory -w
```

A strategic-merge patch merges into `resources`, so the requests survive; `kubectl set resources --limits=memory=128Mi` does the same. `kubectl edit` works too, as long as the requests are left alone — the grading compares them with what was there.

The new Pod prints `ready` and its restart count stays at zero, which is what the grading watches for thirty seconds. Raising the *request* would have changed where the Pod can be scheduled and nothing about whether it survives; the limit is the only number the OOM killer reads.
