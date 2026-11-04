# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

CK-X is a Docker Compose based Kubernetes certification exam simulator (CKA/CKAD/CKS). Bash plus vanilla Node/Express; no bundler, no linter, no runnable tests; CI only builds and pushes the images (`.github/workflows/images.yml`).

## Working Style

- Before starting any non-trivial task, ask clarifying questions until you are ~95% confident you understand what I want.
- Do not guess at ambiguous requirements — ask instead of assuming.
- Only proceed without asking if the task is trivial or fully unambiguous.
- Always update readme.md and claude.md at the end of tasks, if needed.

## Running the simulator

- `./start.sh` is the only supported entry point (`./compose-deploy.sh` is just `start.sh --rebuild`). Other actions: `--stop`, `--restart`, `--status`, `--logs`, `--port N`, `--no-browser`. UI on http://localhost:30080; `--port` is persisted as `CKX_PORT` in a gitignored `.env`.
- **Build-mode trap:** a plain `./start.sh` builds **nothing**. It pulls all seven `ghcr.io/jrocha25/ck-x-simulator-*:latest` images named in `docker-compose.yaml`, which `.github/workflows/images.yml` builds from this repo and pushes on every `master` push that touches an image's sources. Every script is `COPY`-ed into its image and there are no bind mounts, so *no* local edit — `nginx/`, `remote-*/`, `kind-cluster/`, `jumphost/`, and exam assets under `facilitator/assets/` alike — is visible until either `./start.sh --rebuild` (or `docker compose build <service> && docker compose up -d <service>`), or CI has pushed a new `:latest` *and* the stack is restarted: the already-running short-circuit exits before the pull, so `./start.sh --restart` is what picks up a fresh image. `start.sh` carries no copy of the registry name; it reads the image list from `docker compose config --images`, and a pull refused with `unauthorized`/`denied` fails with a `docker login <registry>` hint.
- A `./start.sh` that finds the core services already healthy short-circuits before the build step and prints "CK-X is already running". `./start.sh --stop` first when you need a rebuild to take effect.
- Verify a change end-to-end: `./start.sh`, start the lab in the browser, solve it, hit Evaluate. Logs: `./start.sh --logs`, or `docker compose logs -f facilitator`. The whole exam lifecycle is also drivable over the API without the UI, which is much faster for testing evaluation: `POST /facilitator/api/v1/exams/` with `{"id","assetPath","name","category"}`, poll `GET /exams/<id>/status` until `READY`, then `POST /exams/<id>/evaluate` and poll the same status until `EVALUATED`.

## Cluster flavours

A lab picks its cluster with `clusterType` in `config.json`. The value is threaded
`examService.js` → `jumphostService.js` → `prepare-exam-env.sh` → `env-setup`, and
is matched against an allowlist in `examService.js` before it reaches a shell.

- **`k3d`** (the default, and what every lab before `cka-006` uses) — k3s in docker.
  Fast, ships a NetworkPolicy controller and the Gateway API, but the control plane
  is one embedded process: no kubeadm, no `/etc/kubernetes/manifests`, no node shell.
- **`kind`** — kubeadm-bootstrapped nodes, created by `kind-cluster/scripts/env-setup-kind`.
  Real static pods, `crictl`, kubelet units, `etcdctl`, and SSH into the nodes.

A lab may additionally ask for a second cluster with `auxCluster` in `config.json`
— see **The auxiliary cluster** below. It is threaded down the same chain as a
fourth positional argument and matched against its own allowlist (`kind` only).
`auxNodeImage` (optional, only with `auxCluster`) is the fifth: a `kindest/node`
reference the aux cluster is built from instead of the pinned image, so it can start
a minor *behind* the primary for a `kubeadm upgrade` question. An image ref is not an
enum, so it is matched against a strict shape (`^kindest/node:v\d+\.\d+\.\d+(@sha256:[0-9a-f]{64})?$`)
in `examService.js` *and* again in `prepare-exam-env.sh`, and `env-setup-kind` only
honours it for the aux role. `cka/010` is the only tenant.

`env-cleanup` does **not** take the flavour; it deletes every cluster `kind get
clusters` and `k3d cluster list` report rather than the one name it was handed.
Two callers agreeing on a value is one more thing that can desync — and with two
clusters in play a leak is expensive, since the aux cluster holds ~2.5G until
something reclaims it.

### The kind flavour

- **Node shells.** `ssh controlplane`, `ssh node01`, `ssh node02`, `ssh node03` from
  the jumphost, as root with no password. The node containers live inside the
  `k8s-api-server` container's own docker daemon and are not routable from anywhere
  else, so each node's sshd is mapped out to a distinct port on that container
  (2222 + index) and `jumphost/Dockerfile` writes the matching `~/.ssh/config`.
  Adding a fourth worker means adding a `node04` stanza there too.
- **Nodes are labelled `ck-x.io/alias=<controlplane|node01|…>`** by `env-setup-kind`,
  because kind names them `cluster-control-plane` / `cluster-worker` / `cluster-worker2`
  and every exam question speaks in CKA terms. Resolve names through the label;
  never hardcode `cluster-worker2`.
- **Calico replaces kindnet** (`disableDefaultCNI: true`, `podSubnet: 192.168.0.0/16`
  to match Calico's default pool). kindnet accepts every NetworkPolicy and enforces
  none, so a policy question graded by live traffic would pass no matter what the
  candidate wrote. This also means the cluster has **no CNI at all** until Calico is
  applied — `kind create cluster` is deliberately run without `--wait`, since no node
  can reach Ready before then.
- **kubeadm patches must not name an `apiVersion`.** kind matches a patch on its
  `kind:` field and generates a kubeadm config whose apiVersion tracks the node
  image's minor (`v1beta3` for 1.34). Naming a version that does not match makes the
  patch silently do nothing: the cluster comes up fine and only fails later, when
  kubectl rejects the apiserver certificate for a SAN that was never added.
  `env-setup-kind` asserts it can reach the API server for that reason.
- `KIND_VERSION`, `KIND_NODE_IMAGE` and `CALICO_VERSION` are pinned in
  `kind-cluster/Dockerfile` and mirrored into `/etc/ck-x-versions`; the node image's
  minor tracks `KUBECTL_VERSION` in `jumphost/Dockerfile`.
- `k8s-api-server` is capped at 8 CPU / 13G in `docker-compose.yaml` — three kubeadm
  nodes plus Calico do not fit in the old 2 CPU / 4G, and the headroom above that
  pays for an auxiliary cluster — and `CLUSTER_TIMEOUT` in `start.sh` allows for the
  slower bootstrap.

### The auxiliary cluster

`"auxCluster": "kind"` in a lab's `config.json` builds a **second, single-node
kubeadm cluster** alongside the lab's own. It exists so that a question may break
something *cluster-wide* — DNS, the API server, a kubelet — without every other
question in the lab having to be written around the damage. `cka/006` q8 was the first
tenant; `cka/010` q1 (kubeadm upgrade) and q3 (etcd restore) share theirs, which is
why its node image can differ from the primary's (`auxNodeImage`). `cka/013` q1 takes
down its API server *and* controller manager at once. `cka/014` stages two questions on
one aux cluster — q11 removes its CNI, q3 cuts its API server off from etcd — and says in
q11's prompt that q3 comes first, since a CNI cannot be applied through a dead API server.

|  | primary | auxiliary |
|---|---|---|
| name | `cluster` | `cluster-aux` |
| nodes | `workerNodes` + control plane | control plane only |
| API server port | 6443 | 6444 |
| node sshd port | 2222–2225 | 2232 |
| jumphost SSH alias | `controlplane`, `node01`–`node03` | `aux`, `aux-controlplane` |
| kubeconfig on the jumphost | `~/.kube/kubeconfig` | `~/.kube/kubeconfig-aux` |
| node image | `KIND_NODE_IMAGE` pin | the pin, or `auxNodeImage` |
| pod CIDR | `192.168.0.0/16` | `192.169.0.0/16` |
| service CIDR | kind default | `10.97.0.0/16` |
| docker network | `kind` | `kind-aux` |
| markers | `networkpolicy-unavailable`, … | `aux-` prefixed |

- **The candidate works it over SSH.** `ssh aux` lands as root on its node, where
  `env-setup-kind` has copied `/etc/kubernetes/admin.conf` to `/root/.kube/config` so
  a bare `kubectl` just works — the real-exam shape. It also clears the control-plane
  taint, since the cluster has no worker to schedule on otherwise.
- **Scripts drive it from the jumphost** by `export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux`
  as their first line. That is the one documented exception to *"`KUBECONFIG` is
  exported by the caller — don't set it"*: a per-script export overrides the caller's,
  which is why grading a second cluster needed no facilitator change at all.
- **Distinct CIDRs and a distinct docker network are load-bearing, not tidiness.**
  kind puts every cluster on one shared bridge, and Calico's default pool is
  `192.168.0.0/16` for both. Two clusters handing out pod addresses from the same
  range on the same L2 segment produce conflicting routes. And `calico.yaml` ships
  `CALICO_IPV4POOL_CIDR` *commented out*, so Calico ignores whatever kubeadm was told
  — `env-setup-kind`'s `apply_calico()` uncomments and rewrites it for any pod subnet
  that is not Calico's default, and warns loudly if the manifest's shape has changed.
- **Only `kind` implements it.** The k3d path pins port 6443 and one fixed kubeconfig
  path; a second k3d cluster would silently overwrite the first's kubeconfig, which
  surfaces later as a primary cluster that has quietly become unreachable. `env-setup`
  refuses a non-kind aux rather than building one. A k3d primary *may* carry a kind
  aux, which is why `env-cleanup` checks both flavours independently.
- **It is built in parallel** with the primary (`prepare-exam-env.sh` backgrounds it
  and `wait`s before the setup-script loop), so it adds contention rather than a
  second full bootstrap. The wait is bounded: a lab must still be gradeable without
  its aux cluster, and `q0_setup.sh` writes `/tmp/exam/aux-cluster-unavailable` and
  warns when the probe fails.

**The rule this mechanism came from:** a question that seeds a cluster-wide fault
constrains not just other *validation scripts* but other *question prompts and
`answers.md`*. `cka/006` got the scripts right — every validator was deliberately
DNS-free — and still shipped a q7 whose stated acceptance criterion was
`wget -qO- http://checkout`, unachievable while q8's outage was live. A candidate with
a correct q7 answer saw it fail and had every reason to go break something else.
Audit all three, or move the fault to the aux cluster.

## Exam labs

Authoring guide: @docs/how-to-add-new-labs.md

Labs live in `facilitator/assets/exams/<category>/<id>/` with `config.json`, `assessment.json`, `answers.md`, `scripts/setup/`, `scripts/validation/`. Rules the code enforces but the guide doesn't spell out:

- A lab is invisible to the UI unless registered in `facilitator/assets/exams/labs.json`. `assetPath` there and `answers` in `config.json` are repo-root-relative (`assets/exams/...`); `questions` in `config.json` is exam-dir-relative.
- **The exam's countdown lives in `labs.json`, not `config.json`** — `examDurationInMinutes`, which the authoring guide's example omits. The webapp POSTs the whole lab entry to the facilitator, which stores it untouched, and `app/public/js/components/timer-service.js` counts down from it. Leave it out and the page silently falls back to a hardcoded `120`. The timer is purely client-side: nothing in `facilitator/src/` ends an exam on time.
- Setup scripts run only if they match the glob `q*_setup.sh` (`jumphost/scripts/prepare-exam-env.sh`); any other filename in `scripts/setup/` is silently skipped. They run **sequentially in glob order** (`q1`, `q10`…`q17`, `q2`…`q9`), so questions must be independent — one namespace each, scratch files under `/tmp/exam` — and warm-up time is the *sum* of every script. Their exit codes are ignored and `prepare-exam-env.sh` always exits 0, so a broken setup yields a `READY` exam with a broken question: keep every wait bounded and `echo "WARNING: ..."` instead of failing or hanging.
- Validation scripts are named `qN_sM_validate_<thing>.sh` by convention, but only the exact `verificationScriptFile` string in `assessment.json` is resolved. **Only the exit code matters**: 0 awards `weightage`, non-zero awards 0. `expectedOutput` is decorative and never read. Script output is logged for the facilitator only, never shown to the candidate.
- `weightage` across all verification steps should sum to `totalMarks` (100) by convention, but **nothing reads `totalMarks`**: `jumphostService.js` accumulates `totalPossibleScore` from the weightages it actually ran and reports `totalScore / totalPossibleScore * 100`. So a lab whose weights sum to something else still scores as a correct percentage — `cka/001` sums to 52 and `cka/002` to 102, and both grade fine; every other lab is exactly 100. Keep new labs at 100 and keep edits weight-neutral per question, but don't reweight an existing lab to "fix" its total. Result ranks are hardcoded 80/60 in the same file — `lowScore`/`mediumScore`/`highScore` in `config.json` are not read either.
- `answers.sh` (cka/002, cka/003, cka/004) is referenced by no code; it's an author convenience for solving a lab in one shot on the jumphost to smoke-test validation scripts.
- Never commit `assets.tar.gz` — `facilitator/entrypoint.sh` generates it at container start.

### How evaluation runs

`jumphostService.evaluateExamOnJumphost` flattens every `(question, verification)` pair into
one work list and runs it through a bounded pool (`VALIDATION_CONCURRENCY`, default 4), then
reassembles the per-question arrays by index — so results and scores are identical to the
serial order regardless of concurrency. Each script still gets its own SSH session.

- **Validation scripts must stay independent.** The pool runs four at once, so two scripts that
  touch the same namespace, or a shared scratch file, can now race each other. One namespace per
  question is what makes this safe.
- **Each script is capped at `VALIDATION_SCRIPT_TIMEOUT_SECONDS` (default 90).** The cap is
  applied by `timeout -k 5` *on the jumphost*, which signals the script's process group so its
  children die with it. `sshService.executeCommand`'s own `timeoutMs` is only a backstop for a
  wedged SSH channel and is deliberately set later — closing an exec channel from the facilitator
  side would not kill anything, since exec sessions get no PTY and nothing sends SIGHUP. A script
  that overruns scores 0 and is logged as `TIMED OUT`; keep any single script well under the cap.
- **`POST /evaluate` returns immediately** and the work is detached, so `GET /exams/<id>/result`
  answering 404 is the *normal* state while an evaluation is in flight — the results page treats
  it as "not ready" and polls `/status`. The result is written to Redis *before* the status flips
  to `EVALUATED`, so a poller can never see `EVALUATED` without a result. Don't reorder those two.
- **The results page has no deadline** while the status is `EVALUATING`; it shows an elapsed
  counter and waits. `EVALUATION_FAILED` is the only failure signal, so an evaluation that dies
  without setting it leaves the page spinning forever.

### Question wording

**Troubleshooting questions** (anything whose `concepts` include `troubleshooting`, or whose setup script seeds a deliberate fault) are written like the real CKA exam: three parts, in this order.

1. **Symptom** — what is observably wrong, in the candidate's terms (`Pods never reach Running`, `the Service has no endpoints`, `containers restart over and over`).
2. **Context** — only what is needed to understand the system and to bound the blast radius: what the app is supposed to be, what is owned by someone else and must not be touched.
3. **Desired end state** — the acceptance criteria, phrased as the state to reach.

Never state the root cause, name the broken field, or prescribe the edit. "The node carries a taint", "the ConfigMap does not exist", "set the image of container `api` to X" all turn the task into transcription.

Validation is exact-value (see above), so target values still have to appear — but as *context or acceptance criteria*, never as a diff:

- ✅ "The approved container image for this application is `nginx:1.27.4`." / "All `3` replicas must be ready."
- ❌ "Fix it by setting the image of the container named `api` to `nginx:1.27.4`." / "the image is currently `nginx:1.99-not-real`."

Constraints are what keep a strict script fair — spell out everything the script asserts but the candidate can't infer (`keep 3 replicas`, `do not modify the Deployment`, `keep using envFrom`). If a constraint can only be phrased by revealing the fault, relax the validation script instead of leaking it into the question.

**A troubleshooting question that also carries a non-fault requirement has to state it outright.** Folded into the closing acceptance criteria it is indistinguishable from a description of the repaired state, so a candidate who diagnoses every seeded fault correctly still fails that step and has nothing in the prompt to explain why. Give it its own sentence in the prescriptive style — the fault stays hidden, the extra work does not. `cka/006` q14 seeds two faults in a Kustomize overlay and *also* wants an image bump the base never had a transformer for; its criteria listed the target tag alongside the replica count until the bump was called out separately.

`answers.md` is where the diagnosis lives: open each troubleshooting answer with the investigation commands (`kubectl describe … | grep -A5 Events`) and a sentence naming the fault, then the fix — the `cka/003` q13–q17 answers are the model.

**Every other question type keeps the explicit, prescriptive style** used across the existing labs — names, values and steps stated up front.

### Originality

**A question must never be a kubernetes.io example with the names changed.** `docs/CONTRIBUTING.md` forbids copied scenarios, and a task answerable by pasting a snippet out of the documentation grades recall rather than Kubernetes. This bites hardest where the primitive is small and its docs example is famous — scheduling above all (`app: store` / `web-store` / `redis-cache` inter-pod affinity, `antarctica-east1` node affinity, the `maxSkew: 1` + `DoNotSchedule` spread block, `disktype: ssd`), and on the Kustomize page the `wordpress`/`mysql` pair and `my-nginx`.

**Two things have to be original: the scenario *and* the shape of the answer.** Renaming the workload is not enough — the candidate still writes the documentation's YAML. Build each question as a **composition the docs never show in one block**, so a pasted snippet is not merely unoriginal but *wrong*. `cka/009` q6–q10 are the worked examples:

| | the archetype it avoids | what it demands instead |
|---|---|---|
| q6 | one `In` expression under `requiredDuringScheduling…` | two `matchExpressions` in **one** term, so AND-within-a-term is the graded idea |
| q7 | one `preferred` term alongside a `required` one | **two competing weighted** terms and **no** required block |
| q8 | self anti-affinity on the pod's own label | anti-affinity against **another workload's** label |
| q9 | `podAffinity` inside one namespace | `podAffinity` **across namespaces**, which the own-namespace default makes fail |
| q10 | one `maxSkew: 1` zone constraint | **two constraints**, contrasting `DoNotSchedule` with `ScheduleAnyway` |

**Never reuse the docs' identifiers** — label keys, label values, workload names, zone names. Pick the lab's own domain language; `cka/009` is freight and depots throughout, and labels nodes `node-class` rather than `disktype`.

**Prove it adversarially, by running it.** Reading the question is not the check. Apply the corresponding docs snippet with only the names substituted and confirm the validation **fails**; if it scores, the question is still a transcription and needs restaging. The spec-shape scripts can be driven offline for this — stub `kubectl` so `-o json` returns a synthetic Deployment, and run the real validation script against both the docs shape and the reference answer. Record the result alongside the unsolved and solved runs.

### Script conventions

`#!/bin/bash` with `set -e` (the cka/002 and cka/003 style — follow it for new scripts; older labs omit `set -e`). Constants as UPPERCASE vars at the top, values read via `kubectl -o jsonpath=`, guard clauses that `echo "❌ ..."` then `exit 1`, and one `echo "✅ ..."` / `exit 0` at the end. Setup scripts are idempotent: `kubectl create ... --dry-run=client -o yaml | kubectl apply -f -`, `kubectl delete --ignore-not-found=true`, heredoc applies.

Scripts run **on the jumphost** as `candidate`, never inside the cluster. `KUBECONFIG` is exported by the caller — don't set it, unless the script targets the auxiliary cluster, which is the one case that must (`export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux`; see **The auxiliary cluster**). There are no shared helper libraries; every script is self-contained. On a `k3d` lab there is no SSH access to the cluster nodes; on a `kind` lab both setup and validation scripts may `ssh controlplane` / `ssh node01`. Keep worker counts low — 2 on k3d, 3 on `cka/006`, `cka/010`, `cka/012`, `cka/013` and `cka/014` — to bound resource use. `kubectl`, `helm`, `jq`, `python3` and `docker` are available on the jumphost; there is no standalone `kustomize` binary (use `kubectl kustomize`) and no `nslookup` (probe DNS from inside a `busybox` Pod with `kubectl exec`).

Validation retry loops are capped at **60 seconds** — `for _ in $(seq 1 12); do … sleep 5; done`
with an early `break` on success. Validation runs at the *end* of the exam, long after setup, so
the cluster has settled and a longer wait mostly just punishes a wrong answer: `cka/004` once had
eleven 150-second loops and took 41 minutes to grade an unsolved attempt. Prefer failing fast —
check the cheap guards (does the resource exist? is the field right?) *before* paying for any
stability window, the way `cka/003` q17_s3 does with its `sleep 30`.

Setup scripts don't need a matching question — the runner is a plain `q*_setup.sh` glob — so shared preamble can live in its own `q0_setup.sh`, which always sorts first. `cka/005` uses that for the Gateway API probe instead of bolting it onto whichever Gateway question happens to sort first, the way `cka/004` had to. The same trick works at the other end: `z` sorts after every digit, so a setup script that has to run last can be named `qz_setup.sh`. `cka/006` used that to hold back the script that takes cluster DNS down, until the fault moved to the auxiliary cluster and the ordering stopped mattering — glob-order tricks buy a setup script *ordering*, never *isolation*, and a fault the rest of the lab has to be written around wants isolation.

**Files a setup script needs can ship next to it.** `prepare-exam-env.sh` untars the whole lab onto the jumphost at `/tmp/exam-assets/` and only *runs* what matches the glob, so anything else under `scripts/setup/` reaches the jumphost untouched and is read by absolute path. `cka/014` vendors the Gateway API CRDs, Calico, Flannel and metrics-server manifests in `scripts/setup/files/` so its warm-up needs no download from GitHub.

Traps that make a validation script pass for the wrong reason, all hit while writing `cka/005`:

- **`kubectl auth can-i <verb> pods/log` does not test the subresource.** The positional form is `verb resource/resourceName`, so `pods/log` asks about *the Pod named `log`* and answers `yes` whenever plain `get pods` is allowed. Subresources need `--subresource=log` / `--subresource=exec`.
- **An HPA reaches `minReplicas` even when its metrics are unreadable**, so a replica count is no evidence that a broken autoscaler was fixed. Assert `status.conditions[type=ScalingActive].status` or a non-null `status.currentMetrics[].resource.current.averageUtilization`.
- **`kubectl apply -f x.yaml --dry-run=client -o json` wraps multiple documents in a single `List`**, not a JSON stream — `jq -s '.[] | if .kind == "List" then .items[] else . end'` handles both. It also does no schema type checking, so it won't reproduce a server-side rejection.
- A validation step that only asserts a *constraint* ("still exists", "still denied", "unchanged") passes on an untouched cluster. Keep those at `weightage: 1` and put the marks on the steps that need the work done. An unsolved `cka/005` scores 5/100, which is the floor to aim for.

Traps hit while writing `cka/006`, on the kubeadm flavour:

- **A `hostPath` with `type: DirectoryOrCreate` never fails on a wrong path** — the kubelet creates the empty directory and the container mounts it cleanly, so the only evidence is the container's own output. This is the fault `cka/006` q1 stages deliberately.
- **`systemReserved` is not just an accounting figure.** The kubelet's default `enforceNodeAllocatable` is `["pods"]`, so `Allocatable` is a hard memory cap on the pods cgroup. Squeezing a node to stage an "Insufficient memory" symptom also OOMKills everything already running there — `calico-node` included — which breaks other questions. Leave real headroom and raise the workload's *request* instead.
- **A kubelet stops watching a ConfigMap marked `immutable`** (that is the documented benefit) and caches it for the life of the node. Deleting and recreating one under the same name is therefore never noticed by a node that already cached it: new Pods there keep getting the old values forever, while Pods on other nodes get the new ones. Rotate immutable config by creating a **new object under a new name** and repointing consumers — which is exactly what `configMapGenerator`'s content hash does automatically.
- **busybox's `nslookup` ignores the `search` list in `/etc/resolv.conf`** and queries the name exactly as given, so `nslookup kubernetes.default` answers `NXDOMAIN` from a busybox Pod even when DNS is healthy. Ask for the FQDN in any question graded on a lookup.
- **`--tls-cipher-suites` on the API server must include an `AES_128_GCM_SHA256` suite.** The API server serves HTTP/2, which makes one mandatory, and rejects a list of nothing but 256-bit suites with `error configuring http2` — after the manifest parses, so the Pod is created and then exits.
- **A workload pinned to a node the candidate is asked to taint or drain will collide with whichever question runs first.** Give each such question its own worker (`cka/006` uses `workerNodes: 3`), and keep uncontrolled Pods off any node a question drains — `kubectl drain` refuses to evict a Pod with no controller, and `--force` would delete another question's fixtures permanently.

Traps found while auditing `cka/001`–`cka/005` against CKA scope (see the audit that produced
the `q4`/`q6` rewrites in `cka/005` and `cka/007`):

- **A validation script must never create its own client Pod to test a NetworkPolicy.** A Pod the
  script runs itself is not selected by the candidate's policies, so whatever it can or cannot reach
  proves nothing about them. Probe from the Pods the question already asks for. `cka/002` q17 had a
  `kubectl run test-client` script sitting unreferenced on disk for exactly this reason.
- **`bash`'s `/dev/tcp` is the probe to reach for.** The stock `nginx` and `postgres` images ship no
  `curl` and no `wget`, so `kubectl exec … -- timeout 4 bash -c "echo > /dev/tcp/$IP/$PORT"` is the
  only thing that works without adding a container to the question.
- **A `preferred` pod anti-affinity is the only satisfiable form when replicas outnumber nodes.**
  `requiredDuringSchedulingIgnoredDuringExecution` leaves the surplus Pods `Pending` forever, so a
  question asking 3 replicas to spread over a `workerNodes: 1` cluster has to say "preference".
  Grade the rule's `labelSelector` too: one that matches nothing is satisfied everywhere and spreads
  nothing.
- **A LimitRange is applied at admission and is never retroactive.** Creating one changes nothing
  about the Pods already running, which is what makes "bring this existing Pod under the new policy"
  a real task — the answer is to have it admitted again. Its `defaultRequest` is also the honest way
  to prove the LimitRange did the work: a hand written `limits.memory` with no request defaults the
  request *to the limit*, so an asymmetric request/limit pair can only have come from the policy.
- **`kubectl create --dry-run=server` runs the full admission chain without persisting**, which is
  how to assert that a policy *rejects* something from a validation script that has to stay
  read-only. `--dry-run=client` does not do this — it never reaches the API server.
- **Grading a report file's exact contents grades the shell, not Kubernetes** — and when the
  expected output is hardcoded rather than recomputed, it grades typing. One `kubectl` invocation
  plus a `>` redirect is fair game and appears on the real exam; a pipeline that reshapes, joins,
  dedupes or sorts records into an invented text format is not. Prefer a question that changes
  cluster state and grade the state.

Traps hit while writing `cka/007`, which is RBAC end to end:

- **Several non-resource URLs are already granted to everybody.** `system:public-info-viewer`
  hands `/healthz`, `/livez`, `/readyz` and `/version` to `system:authenticated` *and*
  `system:unauthenticated`, and `system:discovery` adds `/api*`, `/apis*` and `/openapi*`.
  `kubectl auth can-i --as=…` impersonates, and an impersonated identity joins
  `system:authenticated`, so asserting `yes` on any of those proves nothing and asserting
  `no` on them fails against a correct answer. Only `/metrics` and subpaths such as
  `/healthz/etcd` are granted by no default binding.
- **`resourceNames` cannot restrict `list` or `watch`.** Those verbs return a collection and
  the authorizer has no name to match before the request runs, so a rule pairing `list` with
  `resourceNames` grants nothing at all. That is what makes "may read these two ConfigMaps,
  may not list the namespace" expressible — and it means a `list` check is the honest way to
  prove a named grant is narrow.
- **An aggregated ClusterRole's `rules` field belongs to the controller.** It is recomputed as
  the union of every ClusterRole matching `aggregationRule.clusterRoleSelectors` and
  overwrites anything written by hand, so grade the `aggregationRule` itself; if you also
  assert the filled-in `.rules`, give the controller a bounded moment first.
- **`grep -c` on empty input prints `0` and exits 1.** The usual `$(… | grep -c … || true)`
  therefore reports "zero bad Pods" just as loudly when there are no Pods at all — pair any
  such count with an assertion that the collection was non-empty. `cka/007` q8_s1 checks
  `readyReplicas` for exactly that reason.
- **The positional `resource/name` form is right for `resourceNames` and wrong for
  subresources.** `can-i get configmaps/app-settings` is the correct way to probe a named
  grant, while `can-i get pods/log` asks about a Pod called `log`. Same syntax, opposite
  meanings — subresources need `--subresource`.
- A question whose work is entirely cluster-scoped still needs a `namespace` in
  `assessment.json` for the UI; `cka/007` q2 files its ClusterRole work under `rbac-audit`
  and never uses it.
- **`busybox` cannot talk to the API server.** Its `ssl_client` handshake is rejected with
  `TLS error from peer (alert code 47)`, so an in-cluster `wget https://kubernetes.default.svc`
  fails *before* authorization runs. A seeded-fault container that reports its own made-up
  error therefore keeps reporting it after a correct fix, and the candidate's feedback loop
  says the fix did not work — while the validation scripts, which grade the cluster rather
  than the logs, pass. `cka/007` q8 uses `curlimages/curl:8.11.1` and echoes the API server's
  real `Status` body, which names the refused identity.

Traps hit while writing `cka/008`, which is NetworkPolicy end to end:

- **A name-based probe can be answered by the host's search domain.** Pods get
  `ndots:5`, and `svc.cluster.local` names have only four dots, so both resolvers here
  treat them as *relative* and walk the `search` list first. glibc (the `nginx` image)
  does this, and so does busybox's `wget` — though busybox's `nslookup` does not, which
  is why the two disagree inside one container. k3d inherits the node's resolver, so a
  developer machine on a network with wildcard DNS resolves
  `api.np-design.svc.cluster.local.<their-domain>` to a public address and the probe
  silently tests the internet. **Append a trailing dot** to every probed FQDN to make it
  absolute; `cka/008`'s connectivity scripts all do.
- **k3d enforces NetworkPolicy but exposes nothing to probe for.** The controller is
  embedded in the k3s server process, so there is no `calico-node` DaemonSet to look for
  the way `cka/006` does on kind. A lab graded by live traffic has to probe enforcement
  *functionally* — stand up a client and server in a scratch namespace, deny all, confirm
  the client is cut off — which is what `cka/008`'s `q0_setup.sh` does before any question
  runs. Without it an unenforced cluster passes every "can reach" check and fails every
  "cannot reach" one, and the score is silently meaningless.
- **k3d's CIDRs are not configured anywhere and are therefore the k3s defaults**: Pods
  `10.42.0.0/16`, Services `10.43.0.0/16`, kube-dns `10.43.0.10`. That makes them safe to
  name in an `ipBlock` question, but `cka/008` q6's setup still warns if the live node
  `podCIDR` moves out from under it.
- **A deny-side probe on a namespace that setup already default-denied is a free mark.**
  The Pod is shut out before the candidate starts, so the check has to be guarded on the
  candidate's *own* policy existing. Where the seeded policy is the thing being repaired
  (`cka/008` q9, q11) a name guard is not enough — those steps first assert the *allowed*
  path works, then assert the denied one still does not. That is what holds the unsolved
  score at 3/100, all of it from three deliberate `weightage: 1` constraint checks.
- **The exam id is the UUID returned by `POST /exams/`, not the lab id.** `GET
  /exams/cka-008/status` answers `Exam not found`; poll the returned `id`, or read
  `GET /exams/current`.

Traps hit while writing `cka/009`, which is Kustomize and pod placement:

- **The k3d server node is schedulable**, so `workerNodes: 2` is a *three*-node cluster
  for scheduling purposes (`k3d-cluster-server-0` plus two agents). `env-setup` passes no
  `--disable-agent` and k3s taints nothing, which is what makes a required one-pod-per-node
  anti-affinity question gradeable at 3 replicas inside the documented k3d envelope. It is
  also a dependency worth probing: `cka/009`'s `q0_setup.sh` counts `Ready` nodes carrying
  no `NoSchedule` taint and writes `/tmp/exam/insufficient-nodes`, so the placement steps
  fail naming the real cause rather than looking like a wrong answer.
- **k3d labels nothing.** The `ck-x.io/alias` labels are applied by `env-setup-kind` and
  exist only on the kind flavour, and no node anywhere carries a zone label. A k3d lab that
  reasons about topology has to build it in `q0_setup.sh` — and should make the zones
  *uneven*, since an even split is satisfied identically by a zone spread and a hostname
  spread and would not tell a correct answer from a lucky one.
- **A strategic merge patch naming a container the base does not have adds one.** Container
  lists are merged on the `name` key, so a patch that says `check` where the base says
  `checker` renders cleanly, appends a second container *first in the list*, and leaves the
  original untouched. Nothing warns. It is the silent half of `cka/009` q5, and the reason
  that step asserts the container *count* — an image check alone passes against the broken
  output, because the appended container does carry the approved image.
- **`behavior: merge` (and `replace`) in a generator needs the object to already exist in a
  base**, and fails the whole build with `does not exist; cannot merge or replace` when it
  does not. That is a useful *loud* fault to pair with a silent one.
- **`podAffinity` and `podAntiAffinity` are scoped to the Pod's own namespace** unless the
  term carries `namespaces:` or `namespaceSelector:`. Omitting it is not an error — the rule
  simply matches nothing, is never satisfiable, and the replicas sit `Pending` with no
  diagnostic beyond the scheduler's `FailedScheduling`.
- **A preferred rule can only be graded on its spec.** Weights are a scoring hint the
  scheduler may overrule, so asserting where the Pods landed grades the scheduler's mood.
  Grade the two weighted terms and readiness, and leave placement to the required rules.
- **Kustomize proves its own provenance through the name hash — until you turn it off.**
  `cka/005` q14 identifies a generated ConfigMap by its `-<hash>` suffix; a question that
  asks for `disableNameSuffixHash` destroys that evidence, so provenance has to come from
  the overlay instead (`grep -rq configMapGenerator`). Be honest about *why* the hash is
  disabled, too: Kustomize rewrites `configMapRef`/`secretRef` names automatically, so a
  hash never breaks a reference inside the same kustomization — only a consumer outside it.
- **A "the files are still there" constraint check passes on the seeded broken state.**
  `cka/009` q5's "both patch files still referenced" step is true before the candidate
  starts, so it is guarded on the overlay actually building. The unsolved floor is 4/100,
  all of it from four `weightage: 1` checks (three `sha256sum -c` base guards and the node
  labels); solved it scores 100/100, and the whole evaluation runs in about 15 seconds.
- **`su - candidate -c` does not export `KUBECONFIG`.** It is set in the candidate's
  `.bashrc`, which a non-interactive shell never sources, so running `answers.sh` that way
  fails every apply against `127.0.0.1:6443`. The facilitator exports it explicitly over
  SSH; do the same when smoke-testing by hand:
  `docker compose exec -T jumphost su - candidate -c 'export KUBECONFIG=/home/candidate/.kube/kubeconfig; bash /tmp/answers.sh'`.

Traps hit while writing `cka/010`, which upgrades, rejoins and restores kubeadm clusters:

- **`kindest/node` has no package repository, and its binaries belong to no package.** `kubeadm`,
  `kubelet` and `kubectl` sit in `/usr/bin` unowned by dpkg. The real-exam upgrade is an apt
  procedure, so `q1_setup.sh` configures `pkgs.k8s.io` for the *current* minor, installs the debs
  of the version already running (nothing changes on disk, the binaries are now dpkg's) and holds
  them. The kubelet deb ships `/etc/default/kubelet` as a conffile and kind's image already has one
  (`--runtime-cgroups`), so without `-o Dpkg::Options::=--force-confold` dpkg stops at a prompt.
  kind's kubelet units live in `/etc/systemd/system/`, which wins over the deb's `/lib/systemd/`
  copies, so the units are untouched. apt 3 on Debian 13 accepts an armored key; `gnupg` is
  installed anyway so the docs' `gpg --dearmor` line works.
- **`kubeadm upgrade apply` takes ~3 minutes, nearly all of it image pulls**, and also renews every
  certificate (`--certificate-renewal` defaults to true). The jumphost's `kubeconfig-aux` keeps
  working because the old admin client cert is never revoked. `q1_setup.sh` pre-pulls the target
  images in the background (`setsid nohup crictl pull …`), which finished before setup did.
- **After an etcd restore, restart the control plane *and then* the kubelet — and a kubelet
  restart does not restart static Pods.** The API server serves its watch cache from before the
  restore until it is recreated (it eventually crashes on its own — its etcd compactor panics on
  the rewound revision — but minutes later). The controller manager, scheduler and kubelet all sit
  on watches waiting for resource versions the restored etcd will never reach: `kubectl get`
  answers with stale objects and no new Pod ever starts. `kubeadm upgrade plan` surfaces it as its
  `upgrade-health-check` Job failing preflight. `systemctl restart kubelet` on its own *re-adopts*
  the running static Pods rather than recreating them (`crictl ps -a` shows the same container
  ids), so it fixes only the kubelet. Move all four manifests out and back (or `crictl rm -f` the
  containers), then restart the kubelet once the new API server answers. Even then the cluster
  needs ~30s more: RBAC is `Forbidden` until the API server's informers sync, and the controller
  manager and scheduler wait out the stale leader leases the snapshot brought back. `q3_s4`
  grades it by starting a probe Pod.
- **A restore has to go back into the configured data directory** (`/var/lib/etcd`) when an upgrade
  shares the cluster: `kubeadm upgrade apply` regenerates `etcd.yaml` from the cluster
  configuration and would silently abandon `/var/lib/etcd-restored`. A restore *after* the upgrade
  reverts every object the upgrade wrote through the API (`kubeadm-config`, `kube-proxy`, CoreDNS)
  while the static Pods and kubelet stay upgraded, so q1 grades static Pod images and the kubelet
  and never kube-proxy. etcd 3.6 opens a 3.5 snapshot without complaint.
- **`kubeadm reset` stops the kubelet and wipes `/etc/kubernetes`, `/var/lib/kubelet` and the CNI
  config; `kubeadm join` on a kind node needs no `--ignore-preflight-errors` and is done in under a
  second** — the node is Ready ~5s later once Calico re-adopts it. The re-joined Node object has
  lost its `ck-x.io/alias` label, so q2's scripts read the name from `/tmp/exam/nodes.env`, written
  by `q0_setup.sh` before the node was removed.
- **Setup glob order puts most fixtures *before* the scripts that break a node** (`q1, q10..q16,
  q2..q9`). A bare Pod (q13's `resolver`, q7's canary) that landed on node03 was deleted with the
  Node object and never came back; one on node02 would be evicted after five minutes of NotReady.
  `q0_setup.sh` cordons both nodes before anything is scheduled and `q5_setup.sh` uncordons node02
  right before staging its own Deployment there. A cordon is the cheap way to reserve a node for
  the question that breaks it.
- **Pods on a node whose kubelet just died keep reporting `Running` for five minutes**, until the
  node controller evicts them. `q5_s3` passed on the unsolved exam for that reason; "Running on
  node02" is only evidence once node02 itself is Ready, so guard on the node first.
- **A kubeconfig whose context names a user entry that does not exist makes `kubectl` prompt for a
  username on stdin**, and the facilitator's exec session never closes stdin — q7's validators hung
  to the 90s cap instead of failing. Any validator that runs `kubectl` with a candidate-supplied
  kubeconfig needs `</dev/null`.
- **A kubelet restart on the aux node takes its API server down for ~30s**, and q1's procedure ends
  with one. The aux reachability guard in every aux validator retries (4 × 10s) rather than failing
  on one attempt.
- **A CRD and its first instance cannot go in one `kubectl apply`** — the instance is rejected with
  `no matches for kind` until the CRD is Established. `answers.sh` waits on the condition between
  the two.
- **Calico 3.32.1 runs fine on 1.33.12** although only 1.34+ is in its tested matrix; 3.31 covers
  1.32–1.35 if that ever stops being true.
- Warm-up is ~3.5 minutes with the node images cached (five kubeadm nodes plus setup) — far less
  than `cka/006`'s 18-minute estimate. Unsolved floor is 2/100 (two `weightage: 1` constraint
  checks: q1's "held and schedulable" and q3's "serves from `/var/lib/etcd`").

Traps hit while writing `cka/011`, which is the Metrics API, egress port scoping and CoreDNS:

- **`kubectl apply --dry-run=client -f file -o json` prints the file merged with the live
  object**, not the file. A check that read a captured backup that way was really reading the
  cluster's current state, and passed for any file that merely named the right object.
  `kubectl create --dry-run=client -f file -o json` renders the file alone — and it is also how
  to parse YAML at all here, since the jumphost has `python3` but **no PyYAML**.
- **`--dry-run=server` refuses a `kubectl get -o yaml` backup** with `Conflict`, because the
  captured object carries its `resourceVersion`. That is true of a perfectly good backup, so it
  is the wrong way to ask "could this be restored" — restoring one is a delete then an apply.
- **`kubectl patch --type=merge` replaces the whole `containers` array.** A patch that sets only
  `resources` is rejected with `spec.template.spec.containers[0].image: Required value`. The
  default strategic merge patch merges container lists on `name` and is what these questions want
  — with the matching caveat, from `cka/009` q5, that a wrong container name silently *appends*.
- **`kubectl auth can-i --as=<sa>` answers `no` for a ServiceAccount that does not exist**, so a
  "this account can do nothing else" step passes on an untouched namespace. It was worth 2 marks
  of free score until it was guarded on the account existing *and* on the grant it is meant to
  have actually working.
- **A NetworkPolicy "can reach" probe passes when there is no policy at all.** The allow-side
  probes of a policy-writing question have to be guarded on the candidate's own policy existing,
  or an untouched namespace collects them; that was 4 free marks here. `cka/008` q9/q11 make the
  same point from the deny side.
- **kind ships a default StorageClass** (`standard`, local-path), so a PVC that omits
  `storageClassName` has it injected by admission, is dynamically provisioned, and never binds to
  a staged PV. Binding to a specific pre-provisioned volume needs `storageClassName: ""`.
- **metrics-server never becomes Ready on kind** without `--kubelet-insecure-tls`: the kubelets
  serve certificates the cluster CA did not sign. The Deployment rolls out, its readiness probe
  never passes, `kubectl top` fails and the APIService sits at `Available=False` — a good fault to
  build a question on, and the reason `kubectl top` works out of the box on k3d but not here.
- **Deny-side connectivity probes must not use the usual 12 × 5s loop.** A `timeout 4` connect
  plus `sleep 5`, twelve times, is 108 seconds — over the 90 second script cap — and it only runs
  that long when the answer is *wrong*, so the failing case is the one that gets killed. Validation
  runs at the end of the exam, when nothing is still converging: four attempts is enough.
- **`POST /exams/` refuses a second exam while one is active.** `POST /exams/<id>/terminate`
  first; the error names the `currentExamId`.
- Warm-up is ~2.5 minutes with the node images cached (control plane, two workers, and a
  single-node aux cluster). Evaluation is 15s solved and ~136s unsolved — failing checks are the
  ones that pay for retry loops. Unsolved floor is 5/100, all of it `weightage: 1` constraint
  checks (q5's "policy kept" and "approved paths still work", q6's "CoreDNS intact", q14's "other
  certificates untouched", q16's "still 2 replicas and one container").

Traps hit while writing `cka/012`, which drills selector semantics and Pod composition:

- **Fingerprinting a Pod's `.spec` to prove the candidate did not edit it has to exclude
  `nodeName`.** The scheduler writes that field, so a baseline taken while the Pod is `Pending`
  can never match once the Pod is `Running` — the check fails every correct answer and only
  correct answers. `cka/012` q11 records `jq -S '.spec | del(.nodeName)'`. A Deployment's `.spec`
  has no such field and is safe to hash whole, the way q7 does.
- **Every Pod already carries two tolerations.** The `DefaultTolerationSeconds` admission plugin
  adds `node.kubernetes.io/not-ready` and `node.kubernetes.io/unreachable`, both `NoExecute` with
  `tolerationSeconds: 300`, so a check that `spec.tolerations` is non-empty is true of the
  untouched, Pending Pod. Match the seeded taint's key *and* value, and reject an `operator:
  Exists` entry with no key — that tolerates every taint in the cluster, including the ones that
  keep workloads off unhealthy nodes.
- **`staticPodPath` is already `/etc/kubernetes/manifests`,** so "put the manifest in the
  directory that node's kubelet reads" is a question with no content unless the lab moves it.
  `cka/012` q1 rewrites it on node02 and restarts that kubelet, which is cheap because a worker
  runs no control-plane static Pods — but revert it if the node does not come back `Ready`, or
  the whole lab is damaged. The validator reads the path off the node too, so it grades whatever
  the node really says.
- **`successfulJobsHistoryLimit` defaults to 3 and `failedJobsHistoryLimit` to 1.** Asking for a
  default value is a free mark: the field reads back correct from a candidate who never set it.
- **`activeDeadlineSeconds` is a field of both `JobSpec` and `PodSpec`, and not of `CronJobSpec`.**
  So the same mistake fails in two opposite ways: on the CronJob spec it is rejected outright
  (`unknown field`, since server-side field validation is strict for `apply`/`create`/`edit`),
  while on the Job's *Pod template* it is accepted in silence and even appears to work — the
  kubelet does kill the Pod, but the Job then starts a replacement. That asymmetry is the whole
  of `cka/012` q5, and grading it means reading the three paths exactly rather than searching the
  object.
- **A JSON merge patch merges maps.** Repairing a Service whose selector names the wrong labels
  needs the wrong keys set to `null` explicitly — `--type=merge -p '{"spec":{"selector":{"component":null,...`
  — or the result selects the union of both sets and still matches nothing, which is a confusing
  thing to debug on top of the original fault. `kubectl edit` sidesteps it.
- **A merge patch cannot add a toleration to a running Pod.** `spec.tolerations` accepts
  *additions* in place (one of the few mutable Pod fields, alongside container images,
  `activeDeadlineSeconds` and `terminationGracePeriodSeconds`), but a merge patch *replaces* the
  array, which drops the two admission-added entries — and removals are rejected. Append with
  `--type=json` and `"path": "/spec/tolerations/-"`.
- **The `READY` column counts native sidecars too, so it cannot tell the two shapes apart.**
  On kubectl 1.34 a Pod with one application container plus one restartable init container reads
  `2/2`, exactly like a Pod with two regular containers and no sidecar — `cka/012` q9 and q10
  were measured side by side and both report `2/2`. Readiness is no help either: a plain init
  container that exited successfully also reports `ready: true` in
  `.status.initContainerStatuses`. The discriminators are `spec.containers | length` and the
  state *key* under `.status.initContainerStatuses[]` (`terminated` for a plain init container,
  `running` for a sidecar). A question must not promise the candidate a `READY` figure that
  distinguishes them — q10's acceptance criterion was written that way and had to be corrected.
- **Grading a sidecar by name scores the documentation's own snippet.** The Sidecar Containers
  page is one regular container plus *one* init container carrying `restartPolicy: Always`, so a
  check that looks for an `initContainers` entry of the right name with the right policy passes
  on a pasted block with the names changed. Asserting the init container *count*, their order,
  and that only the sidecar carries `restartPolicy: Always`, is what makes the composition the
  graded idea.
- **A deny-all policy passes every deny-side probe.** CLAUDE.md already records that an allow-side
  probe pays out on a namespace with no policy; the mirror of it is that replacing a policy with
  one that has no rules at all collects every "cannot reach" mark for breaking the namespace. Each
  deny check therefore asserts the *allowed* path first — in `cka/012` q4 that is the difference
  between scoring 1 and scoring 9 for a deny-all.
- **A multi-container question states every container's command verbatim**, the way the real
  exam does. The graded idea is the Pod's composition, not shell scripting, and "appends a line
  every few seconds" leaves the candidate guessing at a loop nobody grades. `cka/012` q9 and q10
  first described the commands in prose, and q9 asked for a "header line" it never quoted. Copy
  the strings from `answers.md` so the two cannot drift. The renderer
  (`app/public/js/components/question-service.js`) does not escape HTML and collapses
  indentation, so avoid `<` and nested bullets in a prompt.
- Warm-up and floor are **design targets, not yet measured**: `warmUpTimeInSeconds: 420` for a
  control plane and three workers with no auxiliary cluster, thirteen setup scripts and one
  kubelet restart, and an unsolved floor of 2/100 (q4's two `weightage: 1` constraint checks,
  which are true of the seeded over-permissive policy on purpose and are the guard for the eight
  marks beside them). Correct both after the first `./start.sh --rebuild` and an
  evaluate-without-solving run.

Traps hit while writing `cka/013`, a killer.sh-difficulty mock built from the topics no earlier lab drilled:

- **The scheduler leaves no `managedFields` entry for `spec.nodeName`.** It binds through the
  `binding` subresource, while a client that writes `nodeName` itself owns the field. That is
  the discriminator between "placed by the scheduler" and "placed by hand" (`cka/013` q4, q14) —
  and `kubectl get -o json` omits `managedFields` unless you pass `--show-managed-fields`.
- **The control-plane `NoSchedule` taint is enforced by the scheduler, not the kubelet**, so a Pod
  with a hand-written `nodeName` runs on the control plane with no toleration. A Pod found there
  without one is proof the scheduler was bypassed.
- **A kubelet restart keeps a static Pod's mirror Pod UID; moving the manifest out and back
  changes it.** That is how q4 proves the scheduler was really stopped — and why q5's kubelet
  restart on the same node cannot hand q4 the mark (measured: same UID after a restart).
- **Two PodDisruptionBudgets covering one Pod make eviction fail outright** with `This pod has more
  than one PodDisruptionBudget, which the eviction subresource does not support`, and `kubectl
  drain` retries forever. "Exactly one budget covers these Pods" is not free on the seeded state,
  so q9 s2 compares the covering set against `quorum-budget` by name.
- **Force-finalizing a namespace leaves its resources in etcd.** `PUT …/namespaces/x/finalize`
  removes the Namespace object only; `kubectl get <crd> -n x` still lists the orphans afterwards,
  and patching them answers `namespaces "x" not found` until the namespace is recreated. q16 s1
  checks for orphans, and its two constraint steps are guarded on there being none.
- **`kubectl debug`'s default profile on kubectl 1.34 is still `legacy`, with no `SYS_PTRACE`.**
  Reading `/proc/1/environ` of a process owned by another uid — the pause image runs as 65535 —
  answers `Permission denied`; `--profile=general` adds the capability and works.
- **local-path has no resizer.** Without `allowVolumeExpansion` the API rejects a bigger request
  (`only dynamically provisioned pvc can be resized…`); with it, the request is accepted, the claim
  gets an `ExternalExpanding` event and `status.capacity` never moves. Grade the request, and say so.
- **A new ServiceCIDR is not used until the default range runs out.** A Service recreated without an
  explicit `clusterIP` lands back in `10.96.0.0/16`, so moving one means a `clusterIP` from the new
  range *and* dropping `clusterIPs` from the old object.
- **`kubeadm upgrade node phase kubelet-config` round-trips kind's `config.yaml` byte for byte**
  (checked on v1.34.8), which is what makes "nothing else changed" diffable against a baseline.
- **kind's `/etc/default/kubelet` has no trailing newline**, so `echo … >>` glues text onto
  `KUBELET_EXTRA_ARGS`; edit the line with `sed`. Workers' `kubelet.conf` names the API server
  by IP (`https://172.x.x.x:6443`), not by hostname.
- **jq's `//` treats `false` as missing.** `.conditions.ready // true` turns an explicit
  `ready: false` into `true`; q11 s2 failed the reference answer for that until it compared
  against `null` explicitly.
- **`read` returns non-zero at EOF on a file with no trailing newline**, and under `set -e` that
  ends the script with the variables already set. `kubectl -o jsonpath=… > file` writes exactly
  such a file — q13 s2 failed the reference answer until the `read` got `|| true`.
- **busybox's `sh` ignores SIGTERM**, so a rolled-out Deployment's old Pods linger `Terminating`
  for the 30s grace period. A check for "no Pods from the old template" has to skip Pods with a
  `deletionTimestamp`, or it fails a correct answer evaluated straight after the rollout (q6 s3).
- **etcdctl 3.6 warns on `ETCDCTL_API=3`** (`unrecognized environment variable`); it speaks only v3.
- Warm-up is **~220s** measured (four kubeadm nodes, the aux cluster and eighteen setup scripts).
  The unsolved floor is **0/100** — every `weightage: 1` constraint is guarded on the real work —
  and evaluation takes ~120s unsolved and ~30s solved. `answers.sh` solves it in ~160s.

Traps hit while writing `cka/014`, an exam-format rehearsal built from the topics the current CKA keeps asking about:

- **kind has no Gateway API.** Traefik's provider exists only on k3d. A kind lab that wants a
  Gateway question installs the CRDs itself (vendored, `kubectl apply --server-side`) plus a
  GatewayClass naming a controller that does not exist, and grades the spec. Nothing ever
  reports `Accepted` or `Programmed`, so the prompt must not promise it.
- **A kind node reports the host's CPU and memory as allocatable** (16 CPU / ~32Gi on the
  development machine), not the 8 CPU / 13G cap on `k8s-api-server`. A "share the node fairly"
  question has to compute its bounds from live `status.allocatable`; `cka/014` q13 accepts
  20–34% of it per Pod.
- **Only network-namespaced sysctls are safe on a kind node.** A node is a privileged
  container, so a kernel-wide key written there changes the *host*. `net.bridge.*` does not
  exist inside a node at all. q7 uses `net.ipv4.ip_forward` and
  `net.ipv6.conf.all.forwarding`, and `answers.sh` applies them with `sysctl -p <file>`.
  `sysctl --system` would also replay `/usr/lib/sysctl.d`'s kernel-wide keys onto the host.
- **A `.deb` can be built on the node with `dpkg-deb --root-owner-group --build`.** That
  makes a "install this package and enable its service" question needing no repository and no
  network. Leave the unit disabled in the package so `enable --now` is the candidate's job.
- **A chart that templates a CRD someone else installed fails `helm install` loudly** with
  `invalid ownership metadata`, as long as the existing CRD carries a non-Helm
  `app.kubernetes.io/managed-by`. That is the honest trap: no validator needs to catch a
  takeover, because the install cannot succeed. Grade `crds.install=false` from
  `helm get values -a`.
- **busybox `tail -F` prints a file that appears later from its start, even with `-n 0`**
  (`has appeared; following end of new file` is followed by the whole file). A sidecar
  running `tail -n 0 -F` therefore ships an init container's output only if it was started
  *before* that init container. Listed after it, as in the docs' example, it misses every
  line. That makes init-container order observable in `cka/014` q8.
- **etcd's server certificate already covers the node IP**, so moving
  `--listen-client-urls` off loopback is a coherent "intended" change. The API server then
  works against `https://<node-ip>:2379`, and the seeded fault is the peer port `2380`.
  Keep backups of the manifests off the node: a copy of the original manifest is the answer.
- **Removing Calico from the aux cluster is `kubectl delete -f calico.yaml` plus removing
  `/etc/cni/net.d/10-calico.conflist` and `calico-kubeconfig`.** The node goes NotReady
  within seconds, the Calico images stay in the node's containerd cache, and a re-install
  works offline.
- **Pod Security admission admits the Deployment and refuses its Pods.** The only evidence is
  `FailedCreate` on the *ReplicaSet*, so "0/3 and no Pods at all" is the symptom a
  troubleshooting prompt can state without naming the cause.
- Measured on the first run: warm-up **~185s** (four kubeadm nodes, the aux cluster, seventeen
  setup scripts), unsolved **0/100** in 85s, `answers.sh` 156s, solved **100/100** in 23s.

## Infrastructure gotchas

- `kind-cluster/` builds the image for **both** flavours. It ran kind originally, then k3d only, and now serves either depending on a lab's `clusterType` — see **Cluster flavours** above. A full cluster delete + recreate is the reset between attempts.
- **Gateway API depends on the cluster image being built from this repo.** The Traefik `HelmChartConfig` that turns on the `kubernetesGateway` provider (and moves the entryPoints to 80/443) lives in `kind-cluster/scripts/env-setup`, which ships *inside* the `k8s-api-server` image; `jumphost/scripts/prepare-exam-env.sh` runs that copy over SSH. The GHCR image has it; the old public `nishanb/…:latest` never did, and an image pulled before the relevant CI push doesn't either. Symptom of an outdated image: `kubectl get gatewayclass` → `the server doesn't have a resource type`, and `kubectl get helmchartconfig -A` → empty. The `cka/004` q11 setup detects this, writes `/tmp/exam/gateway-api-unavailable` so q12–q17 skip their waits, and prints a warning naming the fix (`--rebuild`; `--restart` after CI has pushed does the same); `cka/005` does the same probe from `q0_setup.sh` for its q16–q18.
- **The `jumphost` and `webapp` images have to be this repo's, too.** `prepare-exam-env` forwards a lab's `clusterType` to `env-setup`, and `~/.ssh/config` carries the node aliases the kubeadm flavour needs; an outdated jumphost makes a `"clusterType": "kind"` lab come up silently as k3d with no shell on the nodes — `cka/006`'s `q0_setup.sh` detects it and prints the rebuild command, which is the symptom to recognise. An outdated webapp still has the results page giving up on evaluation after 100 seconds and a Retry button that sends the click event where the exam id belongs (`/exams/[object PointerEvent]/result` → 404), so a slow lab looks like it never produced a result. Both were reasons the old `start.sh` built those services locally; now that the registry is built from this repo they are reasons to keep CI green and `--restart` after it pushes.
- `KUBECTL_VERSION` in `jumphost/Dockerfile` and `K3S_VERSION` in `kind-cluster/Dockerfile` are pinned to the same minor on purpose (client/server skew) — bump them together. `HELM_VERSION` is pinned to Helm 3 because Helm 4's output breaks `helm repo list | awk` parsing in the Helm lab.
- Container `ENV` doesn't reach sshd sessions, which is why versions are mirrored into `/etc/ck-x-versions`. Keep that pattern for anything the SSH-invoked scripts need.
- **`.github/workflows/images.yml` pushes all seven images to `ghcr.io/jrocha25/ck-x-simulator-<component>`** (`master` → `:latest` for changed contexts, a `v*` tag → `:<tag>` plus `:latest`, every image; *Run workflow* → every image). That is what `docker-compose.yaml` names and what a plain `./start.sh` pulls. It logs in with `GITHUB_TOKEN`, so it needs no secrets, but GHCR creates a new package **private**: after the first run each package has to be made Public by hand, or every `./start.sh` fails with the `docker login` hint. It builds with BuildKit on purpose — `jumphost/Dockerfile` and `kind-cluster/Dockerfile` branch on `ARG TARGETARCH` with no `else`, and BuildKit fills it in; a builder that leaves it empty ships a jumphost with no `kubectl`. `remote-desktop/` builds on the public `nishanb/ck-x-simulator-vnc-base:v3`, pinned by digest, which is not built here. `scripts/house-keeping/build-and-push.sh` is the interactive Docker Hub equivalent and stays as it is.
- **The remote desktop's Firefox is Mozilla's ESR, not the base image's.** `vnc-base:v3` is consol's 2018 `ubuntu-xfce-vnc` (Ubuntu 16.04), whose last Firefox is 88. That build runs an inline `<script type=module async>` ahead of the classic scripts after it, and kubernetes.io puts its mermaid theme hook (a `MutationObserver` on `<html data-bs-theme>` that calls `location.reload()`) before `main.min.js`, which writes that attribute on load — so every page with a mermaid diagram (the HPA concept page, for one) reloaded about once a second, forever. `remote-desktop/Dockerfile` purges it and installs a pinned `FIREFOX_VERSION`/`FIREFOX_SHA256` tarball into `/opt/firefox`; `firefox-policies.json` turns off updates, telemetry and the first-run/Terms-of-Use dialog. Firefox 153 runs on that glibc 2.23/GTK 3.18 base with only cosmetic GTK warnings. Its profile lives under `~/.config/mozilla/firefox` (XDG), not `~/.mozilla`, and the main process is `firefox-bin` — `pkill -x firefox` matches nothing. One docs tab takes ~600M, hence the 2G cap in `docker-compose.yaml`. A *second* Firefox window paints solid black under this Xvnc — Firefox 88 does the same — so tabs work and new windows do not.
- The facilitator API prefix `/api/v1/assements` is misspelled and load-bearing — the webapp calls that exact path.
- Auth is deliberately disabled throughout (empty SSH passwords, hardcoded VNC password `bakku-the-wizard`). Don't "fix" it; don't expose the port beyond localhost.

## Repo etiquette

Don't run git commit, branch, or push unless asked. Contribution flow: @docs/CONTRIBUTING.md
