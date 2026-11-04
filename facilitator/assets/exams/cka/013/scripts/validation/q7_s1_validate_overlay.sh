#!/bin/bash
set -e

DIR=/tmp/exam/q7/tidereader

if ! (cd "$DIR" && sha256sum --quiet -c /tmp/exam/q7/.base.sha256) >/dev/null 2>&1; then
    echo "❌ Files in the base were modified"
    exit 1
fi
if [[ "$(awk '{print $2}' /tmp/exam/q7/.base.sha256 | sort)" != "$(cd "$DIR" && find base -type f | sort)" ]]; then
    echo "❌ Files were added to the base"
    exit 1
fi

RENDERED=$(kubectl kustomize "$DIR/overlays/prod" 2>/dev/null || true)
if [[ -z "$RENDERED" ]]; then
    echo "❌ The prod overlay does not build"
    exit 1
fi

HPAS=$(kubectl create --dry-run=client -o json -f - <<<"$RENDERED" 2>/dev/null \
    | jq -s '[.[] | if .kind == "List" then .items[] else . end | select(.kind == "HorizontalPodAutoscaler")] | length')
if [[ "$HPAS" != "1" ]]; then
    echo "❌ The prod overlay renders $HPAS HorizontalPodAutoscalers, expected 1"
    exit 1
fi

echo "✅ The prod overlay renders the HPA and the base is unchanged"
exit 0
