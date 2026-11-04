#!/bin/bash
#
# CKA Practice Lab 009 -- reference solution.
#
# Referenced by no code. It exists so the whole lab can be solved in one shot on
# the jumphost to smoke-test the validation scripts: an unsolved run must score 3
# and a run after this script must score 100.
#
# Run it from the jumphost as the candidate user, with KUBECONFIG already
# exported by the login shell.

set -x

### Question 1 -- a first overlay ############################################

mkdir -p /tmp/exam/q1/overlays/dev
cat > /tmp/exam/q1/overlays/dev/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-intro
nameSuffix: -dev
commonAnnotations:
  owner: platform-team
resources:
- ../../base
EOF

kubectl apply -k /tmp/exam/q1/overlays/dev

### Question 2 -- generators without the hash #################################

mkdir -p /tmp/exam/q2/overlays/prod
cat > /tmp/exam/q2/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-gen
resources:
- ../../base
configMapGenerator:
- name: app-settings
  literals:
  - DEPOT_REGION=north
  - MAX_PARCELS=5000
secretGenerator:
- name: depot-ca
  files:
  - ca.crt=depot-ca.pem
generatorOptions:
  disableNameSuffixHash: true
EOF

kubectl apply -k /tmp/exam/q2/overlays/prod

### Question 3 -- one patch, many targets ####################################

mkdir -p /tmp/exam/q3/overlays/prod

# The name here is a placeholder: with an explicit target, kustomize matches on
# the selector and ignores it. Naming a real Deployment would fail the form check.
cat > /tmp/exam/q3/overlays/prod/shift-window-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: placeholder
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: SHIFT_WINDOW
          value: night
EOF

cat > /tmp/exam/q3/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-patch
resources:
- ../../base
patches:
- path: shift-window-patch.yaml
  target:
    kind: Deployment
    labelSelector: tier=backend
EOF

kubectl apply -k /tmp/exam/q3/overlays/prod

### Question 4 -- composing two bases ########################################

mkdir -p /tmp/exam/q4/overlays/prod
cat > /tmp/exam/q4/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-compose
resources:
- ../../bases/app
- ../../bases/cache
labels:
- pairs:
    release: winter-2026
  includeSelectors: false
replicas:
- name: waybill-cache
  count: 2
EOF

kubectl apply -k /tmp/exam/q4/overlays/prod

### Question 5 -- repairing the overlay ######################################

# Fault 1 (loud): "behavior: merge" needs a ConfigMap of that name in the base,
# and there is none. Generating it outright is the fix.
cat > /tmp/exam/q5/overlays/staging/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-repair
resources:
- ../../base
configMapGenerator:
- name: checker-settings
  literals:
  - MODE=strict
patches:
- path: container-patch.yaml
- path: replica-patch.yaml
EOF

# Fault 2 (silent): container lists are merged by the "name" key. The base's
# container is "checker"; the patch said "check", so kustomize appended a second
# container instead of editing the first.
cat > /tmp/exam/q5/overlays/staging/container-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: customs-check
spec:
  template:
    spec:
      containers:
      - name: checker
        image: nginx:1.27.4
EOF

kubectl apply -k /tmp/exam/q5/overlays/staging

### Question 6 -- required node affinity, two expressions in one term #########

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sorting-engine
  namespace: sched-nodeaff
  labels:
    app: sorting-engine
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sorting-engine
  template:
    metadata:
      labels:
        app: sorting-engine
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-class
                operator: In
                values:
                - compute
                - memory
              - key: decommission
                operator: DoesNotExist
      containers:
      - name: engine
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

### Question 7 -- preferred node affinity, two competing weights ##############

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tracking-api
  namespace: sched-prefer
  labels:
    app: tracking-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: tracking-api
  template:
    metadata:
      labels:
        app: tracking-api
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 70
            preference:
              matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                - edge-1
          - weight: 30
            preference:
              matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                - edge-2
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

### Question 8 -- anti-affinity against another workload #####################

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: label-printer
  namespace: sched-antiaff
  labels:
    app: label-printer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: label-printer
  template:
    metadata:
      labels:
        app: label-printer
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: scan-gateway
            topologyKey: kubernetes.io/hostname
      containers:
      - name: printer
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

### Question 9 -- pod affinity across namespaces #############################

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: depot-agent
  namespace: sched-podaff
  labels:
    app: depot-agent
spec:
  replicas: 2
  selector:
    matchLabels:
      app: depot-agent
  template:
    metadata:
      labels:
        app: depot-agent
    spec:
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: depot-telemetry
            namespaces:
            - sched-podaff-infra
            topologyKey: kubernetes.io/hostname
      containers:
      - name: agent
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

### Question 10 -- two spread constraints at once ############################

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: parcel-tracker
  namespace: sched-spread
  labels:
    app: parcel-tracker
spec:
  replicas: 4
  selector:
    matchLabels:
      app: parcel-tracker
  template:
    metadata:
      labels:
        app: parcel-tracker
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: parcel-tracker
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: parcel-tracker
      containers:
      - name: tracker
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

### Question 11 -- pods that will not schedule ###############################

# Diagnosis: the required node affinity demands node-class=archive, and no node
# carries it. The approved classes are compute and memory.
kubectl -n ts-sched patch deployment customs-broker --type='json' -p='[
  {"op": "replace",
   "path": "/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/0/values",
   "value": ["compute", "memory"]}
]'

### Question 12 -- an overlay that injects scheduling policy #################

mkdir -p /tmp/exam/q12/overlays/prod
cat > /tmp/exam/q12/overlays/prod/placement-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: freight-api
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: freight-api
            topologyKey: kubernetes.io/hostname
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: freight-api
EOF

cat > /tmp/exam/q12/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-sched
resources:
- ../../base
replicas:
- name: freight-api
  count: 3
patches:
- path: placement-patch.yaml
EOF

kubectl apply -k /tmp/exam/q12/overlays/prod

set +x
echo
echo "All questions applied. Give the workloads a moment to settle, then evaluate."
