# Contributing Labs to CK-X Simulator

This guide explains how to create and contribute your own practice labs for the CK-X Simulator. By following these steps, you can create custom assessment scenarios for Kubernetes certification preparation (CKAD, CKA, CKS) or other container-related topics.

## Lab Structure Overview

Each lab in CK-X Simulator consists of:

1. **Lab Entry** in the main labs registry
2. **Configuration File** for lab settings
3. **Assessment File** containing questions and verification steps
4. **Setup and Verification Scripts** to prepare environments and validate student solutions
5. **Answers File** with solution documentation

# Considerations Before Creating a Lab
1. The cluster will consist of one control-plane node and multiple worker nodes.
2. SSH access to the nodes is not provided, which may restrict the development of labs that require access to Kubernetes internals or node internals.
3. All setup scripts are executed one after another at exam start, in shell glob order (`q1`, `q10`…`q17`, `q2`…`q9`), so ensure that the questions are independent of each other and that no script waits longer than it has to — the warm-up the candidate sees is the sum of them all.
4. Limit the setup to a maximum of two worker nodes to reduce system resource consumption during the exam.
5. When creating files in the cluster, use the /tmp/exam directory. This directory will be created during setup and removed during cleanup.


## Step 1: Create Lab Directory Structure

First, create a directory structure for your lab using this pattern:

```
facilitator/
└── assets/
    └── exams/
        └── [category]/
            └── [id]/
                ├── config.json
                ├── assessment.json
                ├── answers.md
                └── scripts/
                    ├── setup/
                    │   └── [setup scripts]
                    └── validation/
                        └── [verification scripts]
```

Where:
- `[category]` is the certification type (e.g., `ckad`, `cka`, `cks`, `other`)
- `[id]` is a numeric identifier (e.g., `001`, `002`)

For example, to create a new CKAD lab with ID 003:
```
facilitator/assets/exams/ckad/003/
```

## Step 2: Create Configuration File

Create a `config.json` file in your lab directory with the following structure:

```json
{
  "lab": "ckad-003",
  "workerNodes": 1,
  "clusterType": "k3d",
  "answers": "assets/exams/ckad/003/answers.md",
  "questions": "assessment.json",
  "totalMarks": 100,
  "lowScore": 40,
  "mediumScore": 60,
  "highScore": 90
}
```

Parameters:
- `lab`: Unique identifier for the lab (should match directory structure)
- `workerNodes`: Number of worker nodes required for this lab
- `clusterType`: Which kind of cluster to build, `k3d` (default, may be omitted) or `kind`. See [Choosing a cluster type](#choosing-a-cluster-type)
- `auxCluster`: Optional. Set to `kind` to get a **second, single-node cluster** alongside the lab's own, for a question that breaks something cluster-wide. Omit it unless you need one. See [Questions that break the whole cluster](#questions-that-break-the-whole-cluster)
- `auxNodeImage`: Optional, only with `auxCluster`. A `kindest/node` image reference (`kindest/node:vX.Y.Z`, optionally with an `@sha256:` digest) to build the auxiliary cluster from instead of the pinned one, so that it can start **one Kubernetes minor behind** the lab cluster. That is what a "upgrade this cluster with `kubeadm`" question needs. See [Questions that upgrade a cluster](#questions-that-upgrade-a-cluster)
- `answers`: Path to answers markdown file
- `questions`: sessment JSON filename
- `totalMarks`: Maximum possible score
- `lowScore`, `mediumScore`, `highScore`: Score thresholds for result categorization

### Choosing a cluster type

Most labs want the default. Ask for `kind` only when a question genuinely needs the
control plane to be real.

| | `k3d` (default) | `kind` |
|---|---|---|
| Kubernetes | k3s, single embedded control-plane process | kubeadm-bootstrapped nodes |
| `/etc/kubernetes/manifests` | absent | present, with the four real static pods |
| Shell on a node | none | `ssh controlplane`, `ssh node01`, `ssh node02`, `ssh node03` |
| `crictl`, `kubelet` unit, `etcdctl` | none | available on every node |
| NetworkPolicy enforced | yes (k3s ships a controller) | yes (Calico replaces kindnet) |
| Gateway API | yes (Traefik) | no |
| Auxiliary cluster (`auxCluster`) | not supported as the aux itself | supported |
| Auxiliary cluster on an older minor (`auxNodeImage`) | no | yes |
| Startup | faster | slower — three nodes plus a CNI to install |

On a `kind` lab, resolve node names through the `ck-x.io/alias` label rather than
hardcoding them, since kind calls them `cluster-worker`, `cluster-worker2` and so on:

```bash
NODE01=$(kubectl get nodes -l ck-x.io/alias=node01 -o jsonpath='{.items[0].metadata.name}')
```

Setup and verification scripts on a `kind` lab may reach a node over SSH, which is
what makes questions about static pods, kubelet configuration and etcd possible:

```bash
ssh controlplane "ls /etc/kubernetes/manifests/"
ssh node01 "systemctl restart kubelet"
```

See `facilitator/assets/exams/cka/006` for a worked example, and `cka/010` for one that also
upgrades, rejoins and restores.

### Questions that break the whole cluster

Some faults cannot be contained by giving a question its own namespace. Taking cluster
DNS down, breaking the API server, or misconfiguring a kubelet affects everything else
running at the time — and the cost is not only to the other *verification scripts*, but
to the other *question prompts* and to `answers.md`.

`cka/006` learned this the expensive way. Its DNS question was staged on the lab's own
cluster, and every validation script in the lab was carefully written to avoid name
resolution — that part was right. But question 7's prompt still told the candidate that
`wget -qO- http://checkout` from a Pod had to return a page, which could not succeed
until the DNS question was solved. A candidate who had already applied the correct fix
to question 7 saw their own check fail, concluded it had not worked, and had every
reason to start changing things that were already right.

For a fault like that, ask for an auxiliary cluster instead:

```json
{
  "lab": "cka-006",
  "workerNodes": 3,
  "clusterType": "kind",
  "auxCluster": "kind"
}
```

That builds a second, single-node kubeadm cluster next to the lab's own. It is built in
parallel with the primary, so it costs contention rather than a second full warm-up.

Writing a question against it:

- **The candidate reaches it with `ssh aux`**, landing as root on its node, where a bare
  `kubectl` is already configured for that cluster. Say so in the question — it is not
  something they can discover.
- **Setup and verification scripts** stay on the jumphost and target it by exporting the
  auxiliary kubeconfig as their first line. This is the one place a script should set
  `KUBECONFIG` itself:

  ```bash
  export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux
  ```

- **Files the question asks for still live on the jumphost** (`/tmp/exam/...`), so keep
  any redirection on this side: `ssh aux "kubectl ..." > /tmp/exam/q8/lookup.txt`, not
  `ssh aux "kubectl ... > /tmp/exam/q8/lookup.txt"`.
- **Probe for it in `q0_setup.sh`** and write a marker (`/tmp/exam/aux-cluster-unavailable`)
  when it is missing, the same way the Gateway API and node-SSH probes work, so the
  question degrades to a warning rather than a hang.
- Only `kind` can serve as an auxiliary cluster, and only one is created per lab.

### Questions that upgrade a cluster

A `kubeadm upgrade` question needs a cluster that is *not* on the current version, and the
kind node image is pinned once for the whole simulator. `auxNodeImage` lets a lab build its
auxiliary cluster from an older image instead:

```json
{
  "lab": "cka-010",
  "workerNodes": 3,
  "clusterType": "kind",
  "auxCluster": "kind",
  "auxNodeImage": "kindest/node:v1.33.12@sha256:3f5c8443c620245e4d355cfe09e96a91ead32ceaa569d3f1ca9edf0cb2fe2ff4"
}
```

The candidate then upgrades that cluster to the minor the rest of the simulator runs. Things
`cka/010` learned staging it:

- **Stay within one minor of the jumphost's `kubectl`** (`KUBECTL_VERSION` in
  `jumphost/Dockerfile`) — the validation scripts drive the auxiliary cluster from there —
  and pick an image from the release notes of the pinned `KIND_VERSION`, which lists the
  digests it was tested with.
- **The node image has no package repository.** `kindest/node` ships `kubeadm`, `kubelet` and
  `kubectl` as bare binaries. The exam procedure is an apt procedure, so the lab's setup
  script configures the `pkgs.k8s.io` repository for the *current* minor on the node,
  installs the debs of the version already running (which changes nothing on disk but puts
  the binaries under dpkg's control) and holds them — the state a real node starts from.
  Pass `-o Dpkg::Options::=--force-confold`: the kubelet deb ships `/etc/default/kubelet` as a
  conffile and kind's image already has one, so dpkg would otherwise stop at a prompt.
- **An upgrade takes the API server down** for a moment, and a kubelet restart bounces every
  static Pod. That is the reason to stage it on the auxiliary cluster rather than the lab's own.
- **Pre-pull the target images** in the background from the setup script (`crictl pull` on the
  node): `kubeadm upgrade apply` spends most of its time pulling, and nothing about the
  procedure depends on the pull being slow.
- The upgrade regenerates the static Pod manifests from the cluster configuration, so an etcd
  restore staged on the same cluster has to go back into the configured data directory
  (`/var/lib/etcd`) or a later `kubeadm upgrade apply` silently abandons it.

## Step 3: Create Assessment File

Create an `assessment.json` file that defines questions, namespaces, and verification steps:

```json
{
  "questions": [
    {
      "id": "1",
      "namespace": "default",
      "machineHostname": "node01",
      "question": "Create a deployment named `nginx-deploy` with 3 replicas using the nginx:1.19 image.\n\nEnsure the deployment is created in the `default` namespace.",
      "concepts": ["deployments", "replication"],
      "verification": [
        {
          "id": "1",
          "description": "Deployment exists",
          "verificationScriptFile": "q1_s1_validate_deployment.sh",
          "expectedOutput": "0",
          "weightage": 2
        },
        {
          "id": "2",
          "description": "Deployment has 3 replicas",
          "verificationScriptFile": "q1_s2_validate_replicas.sh",
          "expectedOutput": "0",
          "weightage": 1
        },
        {
          "id": "3",
          "description": "Deployment uses correct image",
          "verificationScriptFile": "q1_s3_validate_image.sh",
          "expectedOutput": "0",
          "weightage": 1
        }
      ]
    }
    // Add more questions...
  ]
}
```

Each question should include:
- `id`: Unique question identifier
- `namespace`: Kubernetes namespace for the question
- `machineHostname`: The hostname to display for SSH connection
- `question`: The actual task description with formatting:
  - Use `\n` for line breaks to improve readability
  - Put code references, commands, or file paths in backtick (e.g., `nginx:1.19`) which will be highlighted in the UI
  - Structure your question with clear paragraphs separated by blank lines
- `concepts`: Array of concepts/topics covered
- `verification`: Array of verification steps

Each verification step includes:
- `id`: Unique step identifier
- `description`: Human-readable description of what's being checked
- `verificationScriptFile`: Script file path to validate the step (present in /scripts/validation directory)
- `expectedOutput`: Expected return code (usually "0" for success)
- `weightage`: Point value for this verification step

### Writing troubleshooting questions

Troubleshooting questions — anything whose `concepts` include `troubleshooting`, or whose setup script seeds a deliberate fault — are written differently from every other question type. On the real exam nobody tells you what is broken, so the question gives three things and stops:

1. **Symptom** — what is observably wrong, in the candidate's terms: "none of its Pods ever reach the `Running` state", "the Service has no endpoints", "the containers are killed and restarted over and over".
2. **Context** — only what is needed to understand the system and to bound the blast radius: what the application is supposed to be, and what belongs to someone else and must not be touched.
3. **Desired end state** — the acceptance criteria, phrased as the state to reach.

Never state the root cause, name the broken field, or prescribe the edit — that turns diagnosis into transcription.

Because verification is exact-value, the target values still have to appear in the question. Phrase them as context or acceptance criteria, never as a diff:

**Anti-pattern:**

> The Deployment `billing-api` in the `ts-image` namespace has `3` replicas, but none of its Pods start.
>
> Diagnose the problem and fix it by setting the image of the container named `api` to exactly `nginx:1.27.4`.

**Pattern:**

> The Deployment `billing-api` in the `ts-image` namespace is configured for `3` replicas, but none of its Pods ever reach the `Running` state.
>
> The approved container image for this application is `nginx:1.27.4`.
>
> Investigate the Deployment and restore it to a healthy state.
>
> When you are finished all `3` replicas must be ready, the Deployment must still declare `3` replicas, and it must still have exactly one container, named `api`, running the approved image.

Both versions satisfy the same strict verification scripts; only the second one requires the candidate to look at the Pod events.

Constraints are what keep a strict verification script fair. Spell out everything the scripts assert but the candidate cannot infer from the symptom — "keep `3` replicas", "do not modify the Deployment", "keep using `envFrom` with a `configMapRef`". If a constraint can only be phrased by revealing the fault, relax the verification script instead of leaking it into the question.

The diagnosis belongs in `answers.md`: open each troubleshooting answer with the investigation commands (`kubectl describe ... | grep -A5 Events`) and a sentence naming the fault, then give the fix. See `facilitator/assets/exams/cka/003/answers.md`, questions 13–17.

Every other question type keeps the explicit, prescriptive style used across the existing labs — names, values, and steps stated up front.

### Keeping questions in scope

These are Kubernetes certification labs, so the graded skill has to be Kubernetes. The line that
has caused the most trouble is **report files**.

Asking the candidate to save the output of a command to a path is fine and appears on the real
exam:

> Write the controller name of the accepted GatewayClass, and nothing else, into
> `/tmp/exam/q11/gatewayclass.txt`.

One `kubectl` invocation plus a `>` redirect. Asking them to *compute* a formatted report is not:

> One line for every container of every Pod in the namespace, in the format
> `pod_name,container_name,image` with no spaces, sorted in ascending order.
>
> The name of every Pod that has at least one container without a memory limit, one per line,
> sorted with no duplicates.

That second one cannot be expressed in JSONPath at all — it needs `jq` with a predicate over a
nested list — and the first is a `tr`/`sort` formatting exercise. Both grade the shell. If a task
only reads the cluster, prefer one that *changes* it and grade the resulting state.

Two related rules:

- **Never hardcode a report's expected output** in the verification script. If the answer is a
  heredoc the script compares against, the candidate can type it by hand without touching the
  cluster. Recompute the expected value live, or grade something else.
- **Verify provenance when output comes from inside a Pod.** A file that must contain
  `svc.cluster.local` is satisfied by `echo`. Require something unguessable too — the ClusterIP the
  name resolved to, say — the way `cka/006` q8 and `cka/002` q10 do.

### Keeping questions original

Your lab must not reproduce the examples on kubernetes.io. `docs/CONTRIBUTING.md` rules out
copied scenarios, and beyond the licensing point a question answerable by pasting a snippet
from the documentation grades recall rather than Kubernetes.

Renaming the workload is not enough — the candidate still writes the documentation's YAML.
Two things have to be original:

- **The scenario.** Never reuse the docs' identifiers: workload names, label keys, label
  values, zone names. `app: store`, `web-store`, `redis-cache`, `antarctica-east1`,
  `disktype: ssd`, `my-nginx` and the `wordpress`/`mysql` pair are all off limits. Pick your
  lab's own domain language and stay in it.
- **The shape of the answer.** Ask for a *composition the docs never show in one block*, so
  a pasted snippet is not merely unoriginal but wrong. Instead of one node-affinity
  expression, ask for two in the same term. Instead of a workload spreading itself, ask for
  anti-affinity against a workload someone else owns. Instead of one spread constraint, ask
  for two that contrast `DoNotSchedule` with `ScheduleAnyway`. See
  `facilitator/assets/exams/cka/009`, questions 6–10.

**Prove it by running it, not by reading it.** Take the docs snippet, substitute only the
names, apply it, and confirm your verification **fails**. If it scores, the question is still
a transcription and needs restaging.

For the checks that only read a resource's spec you can do this without a cluster: stub
`kubectl` so that `-o json` prints a synthetic Deployment, then run your real verification
script against both the docs shape and your own answer.

```bash
cat > /tmp/bin/kubectl <<'EOF'
#!/bin/bash
[[ "$*" == *"-o json"* ]] && { cat "$DEPLOY_JSON"; exit 0; }
exit 0
EOF
chmod +x /tmp/bin/kubectl

PATH=/tmp/bin:$PATH DEPLOY_JSON=docs-shape.json  ./q6_s1_validate_affinity.sh   # must fail
PATH=/tmp/bin:$PATH DEPLOY_JSON=reference.json   ./q6_s1_validate_affinity.sh   # must pass
```

## Step 4: Create Setup and Verification Scripts

The CK-X Simulator uses two types of scripts:

### Setup Scripts

Create setup scripts in the `scripts/setup/` directory to prepare the environment for each question. These scripts run before the student starts the exam to ensure the necessary resources are available.

Example setup script (`scripts/setup/q1_setup.sh`):

```bash
#!/bin/bash
# Setup environment for Question 1

# Create namespace if it doesn't exist
kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -

# Create any prerequisite resources
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: default
data:
  nginx.conf: |
    server {
      listen 80;
      server_name localhost;
      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
    }
EOF

echo "Environment setup complete for Question 1"
exit 0
```

### Verification Scripts

Create verification scripts in the `scripts/validation/` directory to validate student solutions. Each script should:

1. Check a specific aspect of the solution
2. Return exit code 0 for success, non-zero for failure
3. Output useful information for student feedback

Three rules the runner enforces:

- **Verification scripts run several at a time** (four by default), across all questions at
  once — not in question order. Two scripts that share a namespace or a scratch file can
  therefore race each other. Giving every question its own namespace is what keeps this safe.
- **Each script is killed after 90 seconds** and scores 0. Budget well under that.
- **Cap any retry loop at 60 seconds** — `for _ in $(seq 1 12); do … sleep 5; done`, breaking
  early on success — and check the cheap things first. A script that waits two minutes before
  concluding an answer is wrong pays that cost on every unsolved attempt, and the candidate
  waits for the sum of all of them:

```bash
# Fail fast on what cannot be fixed by waiting...
if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found"
    exit 1
fi

# ...then wait, bounded, only for what genuinely needs to converge.
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    [[ "$READY" == "3" ]] && break
    sleep 5
done
```

Example verification script (`scripts/validation/q1_s1_validate_deployment.sh`):

```bash
#!/bin/bash
# Check if deployment exists

DEPLOYMENT_NAME="nginx-deploy"
NAMESPACE="default"

kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE &> /dev/null
if [ $? -eq 0 ]; then
  echo "✅ Deployment '$DEPLOYMENT_NAME' exists in namespace '$NAMESPACE'"
  exit 0
else
  echo "❌ Deployment '$DEPLOYMENT_NAME' not found in namespace '$NAMESPACE'"
  exit 1
fi
```

## Step 5: Create Answers File

Create an `answers.md` file containing solutions to your questions. This file will be displayed directly to students when they view the exam answers.

Focus on providing clear, educational solutions with detailed explanations. The file is rendered as standard Markdown, so you can use all Markdown formatting features. Include complete solution commands, explanations of why certain approaches work, and any relevant tips or best practices.

For each question, provide the question text as a heading followed by a comprehensive solution that would help someone understand not just what to do but why that approach is correct.

## Step 6: Register Your Lab

Finally, add your lab to the main `labs.json` file:

```json
{
  "labs": [
    // ... existing labs ...
    {
      "id": "ckad-003",
      "assetPath": "assets/exams/ckad/003",
      "name": "CKAD Practice Lab - Advanced Deployments",
      "category": "CKAD",
      "description": "Practice advanced deployment patterns and strategies",
      "warmUpTimeInSeconds": 60,
      "difficulty": "medium",
      "examDurationInMinutes": 120
    }
  ]
}
```

Parameters:
- `id`: Unique identifier (should match directory structure)
- `assetPath`: Path to lab resources
- `name`: Display name for the lab
- `category`: Lab category (CKAD, CKA, CKS, etc.)
- `description`: Brief description of the lab content
- `warmUpTimeInSeconds`: Preparation time before exam starts
- `difficulty`: Difficulty level (easy, medium, hard)
- `examDurationInMinutes`: How long the candidate gets, in minutes. This is the only place the
  exam length is configured — it does **not** belong in `config.json`. Omit it and the UI
  silently counts down from a hardcoded 120 minutes. The timer is client-side and advisory:
  nothing server-side stops an exam when it runs out.

## Best Practices

1. **Realistic Scenarios**: Design questions that mimic real certification exam tasks
2. **Clear Instructions**: Write concise, unambiguous question descriptions
3. **Thorough Verification**: Create scripts that verify all aspects of the solution
4. **Comprehensive Answers**: Provide complete, educational solutions
5. **Progressive Difficulty**: Arrange questions from simple to complex
6. **Namespaces**: Use separate namespaces for different questions to avoid conflicts
7. **Resource Requirements**: Keep resource requirements reasonable
8. **Troubleshoot, Don't Transcribe**: For troubleshooting questions, "clear instructions" means an unambiguous *symptom and desired end state* — not the root cause or the field to edit. See [Writing troubleshooting questions](#writing-troubleshooting-questions)
9. **Original Scenarios**: Never ship a kubernetes.io example with the names changed — make both the scenario and the shape of the answer your own, and prove it by running the docs snippet against your verification. See [Keeping questions original](#keeping-questions-original)

## Testing Your Lab

Before submitting your lab:

1. Build and deploy the simulator with your new lab
2. Go through each question as a student would
3. Verify that all verification scripts work correctly
4. Ensure the answers solve the questions as expected
5. Check that scoring and evaluation work properly
6. Evaluate the lab **without solving anything** first. The score should be near zero — anything a candidate is handed for free is a check that passes for the wrong reason
7. Apply the documentation's own snippet for any question built on a common primitive, and confirm it does **not** score

## Contribution Process

1. Fork the CK-X Simulator repository
2. Add your lab following these guidelines
3. Test thoroughly
4. Submit a pull request with a description of your lab

Thank you for contributing to the CK-X community! 