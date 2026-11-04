#!/bin/bash
set -e

FILE=/tmp/exam/q17/token.txt
STATE_FILE=/tmp/exam/q17/.token.sha256

if [[ ! -s "$FILE" ]]; then
    echo "❌ $FILE is missing or empty"
    exit 1
fi

# Surrounding whitespace and a trailing newline are fine; anything else is not.
SUM=$(tr -d '[:space:]' < "$FILE" | sha256sum | awk '{print $1}')
if [[ "$SUM" != "$(cat "$STATE_FILE" 2>/dev/null)" ]]; then
    echo "❌ $FILE does not hold the value of LIGHT_TOKEN, and nothing else"
    exit 1
fi

echo "✅ $FILE holds the credential"
exit 0
