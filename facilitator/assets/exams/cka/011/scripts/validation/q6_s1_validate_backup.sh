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

BACKUP="/tmp/exam/q6/coredns-backup.yaml"

if [[ ! -s "$BACKUP" ]]; then
    echo "❌ '$BACKUP' is missing or empty"
    exit 1
fi

# Parsed through kubectl rather than a YAML library: the jumphost ships jq and
# python3 but no PyYAML.
#
# "create --dry-run=client" and NOT "apply --dry-run=client". Apply merges the
# file with the live object and prints the result, so it reports the cluster's
# current Corefile no matter what the file says -- which made an earlier version
# of this check pass for any file that merely named the ConfigMap. Create
# renders the file and nothing else.
#
# It is also not --dry-run=server: a backup taken the obvious way, with
# "kubectl get -o yaml", carries the object's resourceVersion, and applying that
# over an object that has changed since is refused with a Conflict. That is true
# of a perfectly good backup -- restoring one is a delete followed by an apply.
JSON=$(kubectl create --dry-run=client -f "$BACKUP" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ '$BACKUP' is not something 'kubectl apply -f' would accept"
    exit 1
fi

# A multi-document file comes back wrapped in a List rather than as a stream.
DOCS=$(jq -c 'if .kind == "List" then .items[] else . end' <<<"$JSON" 2>/dev/null || true)
if [[ -z "$DOCS" ]]; then
    echo "❌ '$BACKUP' holds no Kubernetes objects"
    exit 1
fi

COREFILE=$(jq -r 'select(.kind == "ConfigMap"
                     and .metadata.name == "coredns"
                     and (.metadata.namespace // "kube-system") == "kube-system")
                  | .data.Corefile // empty' <<<"$DOCS" | head -c 20000)

if [[ -z "$COREFILE" ]]; then
    echo "❌ '$BACKUP' does not contain the 'coredns' ConfigMap of kube-system with a Corefile"
    exit 1
fi

if ! grep -q "cluster.local" <<<"$COREFILE"; then
    echo "❌ The Corefile in '$BACKUP' does not mention 'cluster.local', so it is not the cluster's DNS configuration"
    exit 1
fi

echo "✅ The CoreDNS backup was captured and could be applied back"
exit 0
