# Local Setup Guide for CK-X Simulator

## Quick Setup

1. Clone the repository:
```bash
git clone https://github.com/jrocha25/kube-exam-simulator.git
cd kube-exam-simulator
```

2. Start it:
```bash
./start.sh
```

That is all. The script checks your machine, fetches the components, starts the
services, waits until they are healthy, and opens
[http://localhost:30080](http://localhost:30080) in your browser. Pick an exam
from the list and press Start.

The first run downloads several GB and takes a while; later runs take seconds.
You can re-run `./start.sh` at any time — if CK-X is already running it simply
opens it.

## Everyday commands

```bash
./start.sh              # start (and open in your browser)
./start.sh --stop       # stop, keeping your setup
./start.sh --restart    # stop then start
./start.sh --status     # is it running?
./start.sh --logs       # watch the logs
./start.sh --port 8080  # use a different port (remembered)
./start.sh --help       # all options
```

## After changing code or exams

A plain `./start.sh` pulls every component prebuilt from GHCR
and builds nothing, so a local change — exam content under
`facilitator/assets/exams/` included, since it is baked into the facilitator
image — is not picked up until you rebuild from source:

```bash
./start.sh --rebuild     # same as ./compose-deploy.sh
```

Once your change is on `master`, CI pushes a fresh image and a
`./start.sh --restart` pulls it; a plain `./start.sh` against a running stack
does not.

## Doing it by hand

If you would rather drive Docker Compose yourself:

```bash
docker compose pull      # fetch the prebuilt components
docker compose up -d     # start
docker compose down      # stop
```

Then open [http://localhost:30080](http://localhost:30080). Like `./start.sh`,
this uses the *published* facilitator image, so exams you added locally will not
appear until you also run `docker compose build facilitator` (which builds from
source).

This setup has been tested on Mac and Linux environments.
