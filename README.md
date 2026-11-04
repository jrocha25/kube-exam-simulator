
![Master Kubernetes the Right Way (2)](https://github.com/user-attachments/assets/16edd8d8-5f96-4422-8659-3bb490b77204)

# CK-X Simulator 🚀

> **Unofficial fork** of [sailor-sh/CK-X](https://github.com/sailor-sh/CK-X), maintained independently and **not affiliated with Sailor.sh**.
> It removes the upstream telemetry and feedback collection and adds further CKA labs. Report problems with this fork [here](https://github.com/jrocha25/kube-exam-simulator/issues), not upstream.


A powerful Kubernetes certification practice environment that provides a realistic exam-like experience for kubernetess exam preparation.

## Major Features

- **Realistic exam environment** with web-based interface and remote desktop support
- Comprehensive practice labs for **CKAD, CKA, CKS**, and other Kubernetes certifications
- **Smart evaluation system** with real-time solution verification
- **Docker-based deployment** for easy setup and consistent environment
- **Timed exam mode** with real exam-like conditions and countdown timer
- **Two cluster flavours** — a fast k3s cluster by default, or a **kubeadm** cluster with SSH access to the nodes for labs that break and repair the control plane itself 
- **Auxiliary clusters** for questions that break something cluster-wide, so a DNS outage or a downed API server costs one question rather than the whole lab — and they can start a Kubernetes minor behind, for **`kubeadm upgrade`**, `kubeadm join` and etcd restore questions


## 

Watch live demo video showcasing the CK-X Simulator in action:

[![CK-X Simulator Demo](https://img.youtube.com/vi/EQVGhF8x7R4/0.jpg)](https://www.youtube.com/watch?v=EQVGhF8x7R4)

## Quick Start

You need [Docker](https://docs.docker.com/get-docker/) installed and running. Nothing else — no configuration, no environment variables, no accounts.

```bash
git clone https://github.com/jrocha25/kube-exam-simulator.git
cd kube-exam-simulator
./start.sh
```

Then wait for it to finish (the first run downloads several GB, later runs take seconds), and your browser opens on **http://localhost:30080**. Pick an exam from the list, press Start, and you are in.

> The first exam you start takes a few minutes to prepare its Kubernetes cluster. That is normal.

> The heaviest labs build a four-node kubeadm cluster, and several of them build a second
> cluster alongside it, so allow Docker roughly **8 CPUs and 13 GB of memory**. Lighter
> k3s labs need far less.

`./start.sh` is safe to run again at any time — if CK-X is already running it just opens it.

| Command | What it does |
| --- | --- |
| `./start.sh` | Start CK-X and open it in your browser |
| `./start.sh --stop` | Stop CK-X (your setup is kept) |
| `./start.sh --status` | Check whether CK-X is running |
| `./start.sh --logs` | Watch the logs |
| `./start.sh --port 8080` | Use a different port, if 30080 is taken |
| `./start.sh --help` | Show all options |

Exams you add yourself under `facilitator/assets/exams/` appear automatically — see the [Lab Creation Guide](docs/how-to-add-new-labs.md).

## Installation

Prefer a one-liner without cloning the repository? These download and run CK-X in a new `ck-x-simulator` directory, using only the published exams.

#### Linux & macOS
```bash
curl -fsSL https://raw.githubusercontent.com/jrocha25/kube-exam-simulator/master/scripts/install.sh | bash
```

#### Windows ( make sure WSL2 is enabled in the docker desktop )
```powershell
irm  https://raw.githubusercontent.com/jrocha25/kube-exam-simulator/master/scripts/install.ps1 | iex
```

### Manual Installation
For detailed installation instructions, please refer to our [Deployment Guide](scripts/COMPOSE-DEPLOY.md).

### Building the images in CI

`.github/workflows/images.yml` builds all seven images (`ck-x-simulator-{webapp,facilitator,nginx,remote-terminal,remote-desktop,jumphost,cluster}`) and pushes them to GHCR as `ghcr.io/jrocha25/ck-x-simulator-<component>`. A push to `master` rebuilds `:latest` for whichever images' sources changed; a `v*` tag builds every image as `:<tag>` and moves `:latest` with it; *Run workflow* rebuilds them all. It needs no secrets — it logs in with the workflow's own `GITHUB_TOKEN`. GHCR is what `docker-compose.yaml` names and what a plain `./start.sh` pulls; nothing is built locally unless you pass `--rebuild`.

In a fork of this repository, replace `jrocha25` in `docker-compose.yaml`, and after the first run set each `ck-x-simulator-*` package to **Public** in the package settings — GHCR creates new packages private.

## Community & Support

- Questions and bug reports go to this repository's [issues](https://github.com/jrocha25/kube-exam-simulator/issues)
- Feature requests and pull requests are welcome

## Adding New Labs

Check our [Lab Creation Guide](docs/how-to-add-new-labs.md) for instructions on adding new labs.

A lab chooses its cluster with `clusterType` in its `config.json`:

- `k3d` (the default) — k3s in Docker. Fast to start, enforces NetworkPolicies and ships the Gateway API.
- `kind` — kubeadm-bootstrapped nodes with real static pod manifests under `/etc/kubernetes/manifests`, `crictl`, `etcdctl`, a kubelet unit, and `ssh controlplane` / `ssh node01` from the exam jumphost. Needed for questions about a broken control plane, kubelet configuration or etcd backups. See [Choosing a cluster type](docs/how-to-add-new-labs.md#choosing-a-cluster-type). With `auxCluster` and `auxNodeImage` a lab also gets a second, single-node cluster on an older minor to upgrade with `kubeadm` — see [Questions that upgrade a cluster](docs/how-to-add-new-labs.md#questions-that-upgrade-a-cluster).

## Contributing

We welcome contributions! Whether you want to:
- Add new practice labs
- Improve existing features
- Fix bugs
- Enhance documentation


## Disclaimer

CK-X is an independent tool, not affiliated with CNCF, Linux Foundation, or PSI. We do not guarantee exam success. CK-X runs entirely on your machine and contains no telemetry or analytics — see our [Privacy Policy](docs/PRIVACY_POLICY.md) and [Terms of Service](docs/TERMS_OF_SERVICE.md) for details and limitations.

## Acknowledgments

- [DIND](https://www.docker.com/)
- [K3D](https://k3d.io/stable/)
- [Node](https://nodejs.org/en)
- [Nginx](https://nginx.org/)
- [ConSol-Vnc](https://github.com/ConSol/docker-headless-vnc-container/)

## License

This project is licensed under the Business Source License 1.1 (BSL 1.1). Personal, educational, research, and non-production use is allowed, but commercial/production usage and SaaS monetization require a separate commercial license from Sailor.sh. See the `LICENSE` file for full terms.
