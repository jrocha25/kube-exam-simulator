#!/bin/bash
set -e

# Staged on the auxiliary cluster, so this script drives that one rather than the
# lab's own. The caller exports KUBECONFIG for the primary cluster before every
# validation script; re-exporting here overrides it for this process only.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

if [[ -f /tmp/exam/aux-cluster-unavailable ]]; then
    echo "❌ The auxiliary cluster was not available when the lab warmed up, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

# Bounded retry: rolling CoreDNS out on a single-node cluster briefly disturbs
# everything that resolves names there, and a candidate who finished a moment
# ago should not lose the question to that.
AUX_UP=no
for _ in 1 2 3 4; do
    kubectl --request-timeout=10s get nodes >/dev/null 2>&1 && { AUX_UP=yes; break; }
    sleep 5
done
if [[ "$AUX_UP" != yes ]]; then
    echo "❌ The auxiliary cluster is unreachable, so this question cannot be graded."
    exit 1
fi

# Guarded on the candidate having done the work. "cluster.local still resolves"
# is true of an untouched cluster, so without this the step would award three
# marks for changing nothing. Reading the live Corefile is what makes it mean
# "you added the new domain and did not break the old one".
COREFILE=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' 2>/dev/null || true)
if ! grep -q "airops.internal" <<<"$COREFILE"; then
    echo "❌ The CoreDNS configuration does not mention 'airops.internal' yet"
    echo "   This step credits keeping cluster.local working while adding the new domain."
    exit 1
fi

NAMESPACE="dns-tower"
POD="probe"
NAME="tower.dns-tower.svc.cluster.local"

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ The '$POD' Pod is missing from namespace '$NAMESPACE' on the auxiliary cluster"
    exit 1
fi

# The expected answer is the Service's live cluster IP, read now rather than
# hardcoded, so the check cannot be satisfied by a stale or invented value.
EXPECTED=$(kubectl get service tower -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$EXPECTED" ]]; then
    echo "❌ Service 'tower' has no cluster IP on the auxiliary cluster"
    exit 1
fi

# The trailing dot makes the name absolute. busybox's nslookup ignores the
# search list anyway, but glibc resolvers do not, and an absolute name is the
# only way to be sure a search domain did not answer instead.
for _ in $(seq 1 8); do
    OUT=$(kubectl exec -n "$NAMESPACE" "$POD" -- nslookup "${NAME}." 2>&1 || true)
    grep -q "$EXPECTED" <<<"$OUT" && break
    sleep 5
done

if ! grep -q "$EXPECTED" <<<"$OUT"; then
    echo "❌ '${NAME}' does not resolve to ${EXPECTED} from the '$POD' Pod"
    echo "   Last output: $(head -c 300 <<<"$OUT" | tr '\n' ' ')"
    exit 1
fi

echo "✅ Names still resolve under cluster.local"
exit 0
