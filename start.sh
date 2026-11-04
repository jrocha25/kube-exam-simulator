#!/usr/bin/env bash
#
# ===============================================================================
#
#   ██████╗██╗  ██╗ █████╗ ██████╗     ███████╗██╗███╗   ███╗██╗   ██╗██╗      █████╗ ████████╗ ██████╗ ██████╗
#  ██╔════╝██║ ██╔╝██╔══██╗██╔══██╗    ██╔════╝██║████╗ ████║██║   ██║██║     ██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗
#  ██║     █████╔╝ ███████║██║  ██║    ███████╗██║██╔████╔██║██║   ██║██║     ███████║   ██║   ██║   ██║██████╔╝
#  ██║     ██╔═██╗ ██╔══██║██║  ██║    ╚════██║██║██║╚██╔╝██║██║   ██║██║     ██╔══██║   ██║   ██║   ██║██╔══██╗
#  ╚██████╗██║  ██╗██║  ██║██████╔╝    ███████║██║██║ ╚═╝ ██║╚██████╔╝███████╗██║  ██║   ██║   ╚██████╔╝██║  ██║
#   ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝     ╚══════╝╚═╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
#
# ===============================================================================
#  Start CK-X Simulator. One command, no configuration needed.
#
#    ./start.sh              start everything and open the browser
#    ./start.sh --help       show all options
#
#  Safe to run as many times as you like.
# ===============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Always work from the project directory, no matter where we were called from.
# ------------------------------------------------------------------------------
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do
  LINK_DIR=$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE="$LINK_DIR/$SOURCE"
done
PROJECT_DIR=$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)
cd "$PROJECT_DIR"

# ------------------------------------------------------------------------------
# Appearance (colours only when attached to a terminal)
# ------------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'
  CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; GRAY=''; BOLD=''; NC=''
fi

say()      { echo -e "$*"; }
step()     { echo -e "\n${BOLD}${CYAN}==>${NC} ${BOLD}$*${NC}"; }
ok()       { echo -e "  ${GREEN}✓${NC} $*"; }
info()     { echo -e "  ${BLUE}ℹ${NC} $*"; }
warn()     { echo -e "  ${YELLOW}!${NC} ${YELLOW}$*${NC}"; }
detail()   { echo -e "    ${GRAY}$*${NC}"; }

# A friendly, actionable error. Never prints a stack trace or raw docker noise.
fail() {
  echo -e "\n${RED}${BOLD}Sorry — CK-X could not start.${NC}\n" >&2
  echo -e "${BOLD}$1${NC}\n" >&2
  shift || true
  for line in "$@"; do
    echo -e "  $line" >&2
  done
  echo -e "\n${GRAY}Still stuck? Open an issue with the output above:${NC}" >&2
  echo -e "${GRAY}https://github.com/jrocha25/kube-exam-simulator/issues${NC}\n" >&2
  exit 1
}

# ------------------------------------------------------------------------------
# Settings
# ------------------------------------------------------------------------------
DEFAULT_PORT=30080
ENV_FILE="$PROJECT_DIR/.env"

# Services that must be healthy before the site is usable.
CORE_SERVICES="nginx webapp facilitator redis"
# The Kubernetes cluster: much slower, and only needed once an exam is started.
CLUSTER_SERVICE="k8s-api-server"
# Every image comes prebuilt from the registry named in docker-compose.yaml
# (GHCR), where .github/workflows/images.yml pushes what it builds from this
# repository. Nothing is built here unless --rebuild is given, so a local edit -- an exam added under
# facilitator/assets/exams included -- is invisible until CI has pushed a new
# :latest and the stack is restarted, or until ./start.sh --rebuild.

CORE_TIMEOUT=240
# A kubeadm (kind) lab has to pull a node image, bootstrap three nodes and install
# Calico before it reports ready, which takes appreciably longer than k3d. A lab
# that also asks for an auxiliary cluster builds it in parallel with the primary
# one, so it adds contention rather than a second full bootstrap -- but it does
# add some.
CLUSTER_TIMEOUT=900

ACTION=start
BUILD_MODE=pull      # pull | all
OPEN_BROWSER=yes
REQUESTED_PORT=""

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}CK-X Simulator${NC} — practice for the CKA, CKAD and CKS exams.

${BOLD}Usage:${NC}
  ./start.sh [options]

${BOLD}Everyday use:${NC}
  ./start.sh                 Start CK-X and open it in your browser.
                             Safe to run again at any time.
  ./start.sh --stop          Stop CK-X. Your setup is kept for next time.
  ./start.sh --restart       Stop, then start again.
  ./start.sh --status        Show whether CK-X is running.
  ./start.sh --logs          Show live logs (press Ctrl+C to stop watching).

${BOLD}Options:${NC}
  --port N                   Serve CK-X on port N instead of $DEFAULT_PORT.
                             Remembered for next time.
  --no-browser               Do not open the browser automatically.
  --rebuild                  Build every component from local source instead
                             of pulling it. Much slower; for developers.
  -h, --help                 Show this help.

${BOLD}First run:${NC}
  Downloads several GB of components and takes a while. Later runs are quick.

${BOLD}Requirements:${NC}
  Docker, 4 GB RAM (8 GB recommended), 10 GB free disk, internet access.
EOF
}

# ------------------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --stop)       ACTION=stop ;;
    --restart)    ACTION=restart ;;
    --status)     ACTION=status ;;
    --logs)       ACTION=logs ;;
    --rebuild)    BUILD_MODE=all ;;
    --no-browser) OPEN_BROWSER=no ;;
    --port)
      shift
      [ $# -gt 0 ] || fail "--port needs a number, for example: ./start.sh --port 8080"
      REQUESTED_PORT="$1"
      ;;
    --port=*)     REQUESTED_PORT="${1#*=}" ;;
    -h|--help)    usage; exit 0 ;;
    *)
      say "${RED}Unknown option: $1${NC}\n"
      usage
      exit 1
      ;;
  esac
  shift
done

if [ -n "$REQUESTED_PORT" ]; then
  case "$REQUESTED_PORT" in
    ''|*[!0-9]*) fail "\"$REQUESTED_PORT\" is not a valid port number." \
                      "Pick a number between 1024 and 65535, for example: ./start.sh --port 8080" ;;
  esac
  if [ "$REQUESTED_PORT" -lt 1024 ] || [ "$REQUESTED_PORT" -gt 65535 ]; then
    fail "Port $REQUESTED_PORT cannot be used." \
         "Pick a number between 1024 and 65535, for example: ./start.sh --port 8080"
  fi
fi

# ------------------------------------------------------------------------------
# Port handling
#
# The compose file publishes "\${CKX_PORT:-30080}:80". We remember a chosen port
# in .env (gitignored) so plain "docker compose" commands agree with us.
# ------------------------------------------------------------------------------
read_saved_port() {
  if [ -f "$ENV_FILE" ]; then
    local saved
    saved=$(grep -E '^CKX_PORT=' "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2 | tr -d '[:space:]') || true
    if [ -n "${saved:-}" ]; then
      echo "$saved"
      return
    fi
  fi
  echo "$DEFAULT_PORT"
}

save_port() {
  local port=$1 tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/ckx-env.XXXXXX")
  if [ -f "$ENV_FILE" ]; then
    grep -vE '^CKX_PORT=' "$ENV_FILE" > "$tmp" 2>/dev/null || true
  fi
  if [ "$port" != "$DEFAULT_PORT" ]; then
    echo "CKX_PORT=$port" >> "$tmp"
  fi
  if [ -s "$tmp" ]; then
    mv "$tmp" "$ENV_FILE"
  else
    rm -f "$tmp" "$ENV_FILE"
  fi
}

if [ -n "$REQUESTED_PORT" ]; then
  PORT="$REQUESTED_PORT"
else
  PORT=$(read_saved_port)
fi
export CKX_PORT="$PORT"
URL="http://localhost:${PORT}"

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

dc() { docker compose "$@"; }

# Health of one service: healthy | unhealthy | starting | running | stopped | missing
service_state() {
  local svc=$1 cid
  cid=$(dc ps -q "$svc" 2>/dev/null | head -n1) || true
  if [ -z "${cid:-}" ]; then
    echo missing
    return
  fi
  # Deliberately not `docker compose ps --format json`: its shape has changed
  # between Compose releases. `docker inspect` is stable.
  docker inspect \
    --format '{{if .State.Health}}{{.State.Health.Status}}{{else if .State.Running}}running{{else}}stopped{{end}}' \
    "$cid" 2>/dev/null || echo missing
}

service_ok() {
  case "$(service_state "$1")" in
    healthy|running) return 0 ;;
    *) return 1 ;;
  esac
}

all_ok() {
  local svc
  for svc in $1; do
    service_ok "$svc" || return 1
  done
  return 0
}

human_time() {
  local s=$1
  if [ "$s" -lt 60 ]; then
    echo "${s}s"
  else
    echo "$((s / 60))m $((s % 60))s"
  fi
}

open_browser() {
  local url=$1
  if have xdg-open; then
    (xdg-open "$url" >/dev/null 2>&1 &) && return 0
  fi
  if have open; then
    (open "$url" >/dev/null 2>&1 &) && return 0
  fi
  if have python3; then
    (python3 -m webbrowser "$url" >/dev/null 2>&1 &) && return 0
  fi
  return 1
}

# ------------------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------------------
check_docker() {
  if ! have docker; then
    local hint="Install Docker Desktop from https://docs.docker.com/get-docker/"
    case "$(uname -s)" in
      Linux) hint="Install Docker from https://docs.docker.com/engine/install/ (or use your package manager)." ;;
      Darwin) hint="Install Docker Desktop for Mac from https://docs.docker.com/desktop/install/mac-install/" ;;
    esac
    fail "Docker is not installed." \
         "CK-X runs inside Docker, so that is the one thing you need first." \
         "" \
         "$hint" \
         "Then run ${BOLD}./start.sh${NC} again."
  fi

  local err
  if ! err=$(docker info 2>&1); then
    if echo "$err" | grep -qi "permission denied"; then
      fail "Docker is installed, but this user is not allowed to use it." \
           "Pick one of these:" \
           "" \
           "  ${BOLD}sudo ./start.sh${NC}                              (quick, one time)" \
           "  ${BOLD}sudo usermod -aG docker \$USER${NC}                (permanent — then log out and back in)"
    fi
    case "$(uname -s)" in
      Darwin)
        fail "Docker is installed, but it is not running." \
             "Open ${BOLD}Docker Desktop${NC} and wait until it says it is running," \
             "then run ${BOLD}./start.sh${NC} again."
        ;;
      *)
        fail "Docker is installed, but it is not running." \
             "Start it with:" \
             "" \
             "  ${BOLD}sudo systemctl start docker${NC}" \
             "" \
             "(On Windows or Mac, open Docker Desktop instead.)" \
             "Then run ${BOLD}./start.sh${NC} again."
        ;;
    esac
  fi
  ok "Docker is running"

  # Test the command itself; do not parse a version number.
  if ! docker compose version >/dev/null 2>&1; then
    fail "Docker Compose is missing." \
         "CK-X needs the Compose plugin (the ${BOLD}docker compose${NC} command)." \
         "" \
         "Install it: https://docs.docker.com/compose/install/" \
         "" \
         "${GRAY}Note: the older, separate \"docker-compose\" command is not enough.${NC}"
  fi
  ok "Docker Compose is available"

  if docker info --format '{{join .SecurityOptions ","}}' 2>/dev/null | grep -q rootless; then
    warn "Docker is running in rootless mode."
    detail "CK-X needs privileged containers for its Kubernetes cluster and may not work."
    detail "If exams fail to start, try a standard (rootful) Docker installation."
  fi
}

check_resources() {
  local mem_gb="" disk_gb=""

  case "$(uname -s)" in
    Linux)
      if [ -r /proc/meminfo ]; then
        local kb
        kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null) || true
        [ -n "${kb:-}" ] && mem_gb=$((kb / 1024 / 1024))
      fi
      ;;
    Darwin)
      local bytes
      bytes=$(sysctl -n hw.memsize 2>/dev/null) || true
      [ -n "${bytes:-}" ] && mem_gb=$((bytes / 1024 / 1024 / 1024))
      ;;
  esac

  disk_gb=$(df -k . 2>/dev/null | awk 'NR==2 {print int($4 / 1024 / 1024)}') || true

  if [ -n "${mem_gb:-}" ] && [ "$mem_gb" -gt 0 ]; then
    if [ "$mem_gb" -lt 4 ]; then
      warn "This machine has about ${mem_gb} GB of memory; CK-X needs 4 GB at a minimum."
      detail "It may start but run out of memory once an exam begins."
    elif [ "$mem_gb" -lt 8 ]; then
      warn "This machine has about ${mem_gb} GB of memory (8 GB is recommended)."
      detail "Close heavy applications before starting an exam."
    else
      ok "Memory: ${mem_gb} GB"
    fi
  fi

  if [ -n "${disk_gb:-}" ] && [ "$disk_gb" -gt 0 ]; then
    if [ "$disk_gb" -lt 10 ]; then
      warn "Only about ${disk_gb} GB of disk space is free; CK-X needs around 10 GB."
      detail "Free some space, or the download may fail part way through."
    else
      ok "Disk space: ${disk_gb} GB free"
    fi
  fi
}

# Is the port held by something that is not our own nginx?
port_in_use_by_other() {
  local port=$1

  if have ss; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$" && return 0
    return 1
  fi
  if have lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    return 1
  fi
  if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
    exec 3>&- 2>/dev/null || true
    return 0
  fi
  return 1
}

# Find a port that is actually free, so we never suggest one that just failed.
suggest_free_port() {
  local candidate
  for candidate in 8080 8090 9090 18080 30081 30090; do
    [ "$candidate" = "$PORT" ] && continue
    if ! port_in_use_by_other "$candidate"; then
      echo "$candidate"
      return
    fi
  done
  echo ""
}

describe_port_holder() {
  local port=$1
  if have lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1" (process "$2")"}'
  elif have ss; then
    ss -ltnp 2>/dev/null | grep -E "[:.]${port}\b" | grep -oE 'users:\(\("[^"]+"' | head -n1 | sed 's/users:((//; s/"//g'
  fi
}

check_port() {
  # CK-X's own nginx already holding the port is success, not a conflict. This
  # is what makes re-running safe. Only trust it when the port is unchanged.
  if service_ok nginx && [ "$PORT" = "$(read_saved_port)" ]; then
    ok "Port ${PORT} is already served by CK-X"
    return 0
  fi

  if port_in_use_by_other "$PORT"; then
    local holder
    holder=$(describe_port_holder "$PORT" 2>/dev/null) || true
    local holder_line="Something else on this machine is already using port ${PORT}."
    [ -n "${holder:-}" ] && holder_line="Port ${PORT} is already used by: ${BOLD}${holder}${NC}"

    local suggestion
    suggestion=$(suggest_free_port)
    if [ -n "$suggestion" ]; then
      fail "Port ${PORT} is not available." \
           "$holder_line" \
           "" \
           "The easiest fix is to let CK-X use a different port:" \
           "" \
           "  ${BOLD}./start.sh --port ${suggestion}${NC}   ${GRAY}(port ${suggestion} is free right now)${NC}" \
           "" \
           "Or stop whatever is using port ${PORT} and run ${BOLD}./start.sh${NC} again."
    fi
    fail "Port ${PORT} is not available." \
         "$holder_line" \
         "" \
         "Stop whatever is using port ${PORT}, or pick a free port yourself:" \
         "" \
         "  ${BOLD}./start.sh --port <number>${NC}"
  fi
  ok "Port ${PORT} is available"
}

# ------------------------------------------------------------------------------
# Images
# ------------------------------------------------------------------------------
# The images the compose file names, redis included. Read from the compose file
# so this script carries no copy of the registry name.
compose_images() { dc config --images 2>/dev/null; }

registry_host() { compose_images | grep / | head -n1 | cut -d/ -f1; }

local_images_present() {
  local img
  for img in $(compose_images); do
    docker image inspect "$img" >/dev/null 2>&1 || return 1
  done
  return 0
}

pull_images() {
  # --rebuild builds everything the registry would have provided; `docker
  # compose up` fetches redis on its own if it is missing.
  [ "$BUILD_MODE" = all ] && return 0

  step "Getting the CK-X components"
  info "First time around this downloads several GB — a good moment for coffee."

  if dc pull; then
    ok "All components are up to date"
    return 0
  fi

  # Piping the pull through tee would cost Compose its progress display, so
  # classify the failure afterwards with a cheap, read-only lookup that uses the
  # same credentials.
  # (|| true: under pipefail the lookup's own failure would otherwise mask grep's match.)
  if { docker manifest inspect "$(compose_images | grep / | head -n1)" 2>&1 || true; } \
      | grep -qiE "unauthorized|authentication required|no basic auth credentials|denied"; then
    fail "The image registry refused the download." \
         "The registry hosting the CK-X components asked for a login this machine does not have." \
         "" \
         "  ${BOLD}docker login $(registry_host)${NC}" \
         "" \
         "Then run ${BOLD}./start.sh${NC} again."
  fi

  if local_images_present; then
    warn "Could not check for updates (no internet connection?)."
    detail "Continuing with the components already on this machine."
    return 0
  fi

  fail "Could not download the CK-X components." \
       "This is almost always a connection problem." \
       "" \
       "  • Check that this machine is online." \
       "  • If you are behind a company proxy or VPN, Docker needs to be configured for it." \
       "" \
       "Then run ${BOLD}./start.sh${NC} again — it will pick up where it left off."
}

build_images() {
  [ "$BUILD_MODE" = all ] || return 0

  step "Building every component from source (this takes a while)"
  if ! COMPOSE_BAKE=true dc build; then
    fail "Building from source failed." \
         "The output above has the details." \
         "" \
         "To start with the prebuilt components instead:" \
         "" \
         "  ${BOLD}./start.sh${NC}"
  fi
  ok "All components built"
}

# ------------------------------------------------------------------------------
# Bring the stack up
# ------------------------------------------------------------------------------
start_containers() {
  step "Starting CK-X"
  local err
  if ! err=$(dc up -d --remove-orphans 2>&1); then
    say "$err" >&2
    if echo "$err" | grep -qiE "port is already allocated|address already in use"; then
      fail "Port ${PORT} was taken while starting up." \
           "Try a different port:" \
           "" \
           "  ${BOLD}./start.sh --port 8080${NC}"
    fi
    if echo "$err" | grep -qiE "privileged|operation not permitted"; then
      fail "This Docker installation will not allow the containers CK-X needs." \
           "CK-X runs a real Kubernetes cluster inside Docker, which needs privileged containers." \
           "" \
           "This usually means Docker is in rootless mode, or is Podman rather than Docker." \
           "A standard Docker installation is required."
    fi
    if echo "$err" | grep -qiE "no space left"; then
      fail "This machine has run out of disk space." \
           "Free up a few GB, then run ${BOLD}./start.sh${NC} again." \
           "" \
           "To reclaim space used by old Docker data:" \
           "" \
           "  ${BOLD}docker system prune${NC}"
    fi
    fail "CK-X could not be started." \
         "The output above has the details from Docker." \
         "" \
         "It is safe to just try again:" \
         "" \
         "  ${BOLD}./start.sh${NC}"
  fi
  ok "Containers started"
}

# Wait until the listed services report healthy, printing progress as we go.
wait_for() {
  local services=$1 timeout=$2 label=$3
  local waited=0 interval=5 last_report=-1

  while [ "$waited" -lt "$timeout" ]; do
    if all_ok "$services"; then
      ok "$label ready after $(human_time "$waited")"
      return 0
    fi
    # Report progress every 15s so the user knows we are alive.
    if [ "$waited" -gt 0 ] && [ $((waited % 15)) -eq 0 ] && [ "$waited" -ne "$last_report" ]; then
      local pending="" svc
      for svc in $services; do
        service_ok "$svc" || pending="$pending $svc"
      done
      [ -n "$pending" ] && detail "still waiting for:${pending} ($(human_time "$waited") elapsed)"
      last_report=$waited
    fi
    sleep "$interval"
    waited=$((waited + interval))
  done
  return 1
}

wait_for_core() {
  step "Waiting for CK-X to come up"
  if wait_for "$CORE_SERVICES" "$CORE_TIMEOUT" "Website"; then
    return 0
  fi

  local svc
  say ""
  for svc in $CORE_SERVICES; do
    warn "$svc: $(service_state "$svc")"
  done
  fail "CK-X started, but the website did not become ready in time." \
       "Something is wrong with one of the parts listed above." \
       "" \
       "See what happened:" \
       "" \
       "  ${BOLD}./start.sh --logs${NC}" \
       "" \
       "Then try again with:" \
       "" \
       "  ${BOLD}./start.sh --restart${NC}"
}

wait_for_cluster() {
  step "Preparing the Kubernetes cluster"
  info "This is the slow part on a first run. It keeps going in the background,"
  info "so you can already open the website while you wait."

  if wait_for "$CLUSTER_SERVICE" "$CLUSTER_TIMEOUT" "Kubernetes cluster"; then
    return 0
  fi

  # Not a failure: the website works, and the cluster is only needed once an
  # exam is actually started.
  warn "The Kubernetes cluster is still starting (this can take a while on a slow connection)."
  detail "You can open CK-X now; give the cluster a few more minutes before starting an exam."
  detail "To watch it: ./start.sh --logs"
}

# ------------------------------------------------------------------------------
# Reporting
# ------------------------------------------------------------------------------
print_ready() {
  say ""
  say "${GREEN}${BOLD}  CK-X is ready.${NC}"
  say ""
  say "  ${BOLD}Open:${NC}  ${BOLD}${CYAN}${URL}${NC}"
  say ""
  say "  ${GRAY}Then: pick an exam from the list and press Start.${NC}"
  say "  ${GRAY}The first exam you start takes a few minutes to prepare its cluster.${NC}"
  say ""
  say "  ${GRAY}Stop CK-X:${NC}      ./start.sh --stop"
  say "  ${GRAY}Check status:${NC}   ./start.sh --status"
  say "  ${GRAY}See logs:${NC}       ./start.sh --logs"
  say ""
}

show_status() {
  local svc state colour
  say "\n${BOLD}CK-X status${NC}\n"
  local any=no
  for svc in $CORE_SERVICES $CLUSTER_SERVICE jumphost remote-desktop remote-terminal; do
    state=$(service_state "$svc")
    case "$state" in
      healthy|running) colour=$GREEN; any=yes ;;
      starting)        colour=$YELLOW; any=yes ;;
      missing)         colour=$GRAY ;;
      *)               colour=$RED; any=yes ;;
    esac
    printf "  %-18s ${colour}%s${NC}\n" "$svc" "$state"
  done
  say ""
  if [ "$any" = yes ] && service_ok nginx; then
    say "  Open ${BOLD}${CYAN}${URL}${NC}\n"
  elif [ "$any" = no ]; then
    say "  ${GRAY}CK-X is not running. Start it with:${NC} ${BOLD}./start.sh${NC}\n"
  fi
}

do_stop() {
  step "Stopping CK-X"
  # No --volumes: the shared kube-config volume is kept so the next start is
  # quicker and nothing is silently thrown away.
  if dc down --remove-orphans; then
    ok "CK-X is stopped. Your setup is kept for next time."
    say "\n  ${GRAY}Start it again with:${NC} ${BOLD}./start.sh${NC}\n"
  else
    fail "Could not stop CK-X cleanly." \
         "The output above has the details from Docker."
  fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
case "$ACTION" in
  status)
    # Subshell: check_docker exits on failure, and we want to report it ourselves.
    if ! ( check_docker ) >/dev/null 2>&1; then
      fail "Docker is not available, so CK-X cannot be running." \
           "Start Docker, then run ${BOLD}./start.sh${NC}"
    fi
    show_status
    exit 0
    ;;
  logs)
    say "${GRAY}Showing live logs. Press Ctrl+C to stop watching (CK-X keeps running).${NC}\n"
    exec docker compose logs -f --tail=100
    ;;
  stop)
    check_docker >/dev/null
    do_stop
    exit 0
    ;;
  restart)
    check_docker >/dev/null
    do_stop
    ACTION=start
    ;;
esac

START_TIME=$(date +%s)

say ""
say "${BOLD}${CYAN}  CK-X Simulator${NC} ${GRAY}— Kubernetes exam practice${NC}"
say "${GRAY}  Setting everything up. No configuration needed.${NC}"

step "Checking this machine"
check_docker
check_resources
check_port

# Already running and healthy? Then there is nothing to do.
if all_ok "$CORE_SERVICES" && [ -z "$REQUESTED_PORT" ] && [ "$BUILD_MODE" != all ]; then
  ok "CK-X is already running"
  save_port "$PORT"
  print_ready
  if [ "$OPEN_BROWSER" = yes ]; then
    open_browser "$URL" || detail "Open the address above in your browser."
  fi
  exit 0
fi

save_port "$PORT"

pull_images
build_images
start_containers
wait_for_core
wait_for_cluster

TOTAL=$(( $(date +%s) - START_TIME ))
print_ready
detail "Ready in $(human_time "$TOTAL")."
say ""

if [ "$OPEN_BROWSER" = yes ]; then
  if open_browser "$URL"; then
    detail "Opening your browser..."
  else
    detail "Open the address above in your browser to begin."
  fi
  say ""
fi
