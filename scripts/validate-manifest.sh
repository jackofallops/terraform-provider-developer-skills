#!/usr/bin/env bash
set -euo pipefail

MANIFEST="apm.yml"

if [ ! -f "$MANIFEST" ]; then
  echo "Error: $MANIFEST not found in current directory."
  exit 1
fi

echo "Validating capabilities in $MANIFEST..."

# Read paths using yq and check if directories exist
while IFS= read -r p; do
  if [ -n "$p" ] && [ ! -d "$p" ]; then
    echo "Error: Directory '$p' declared in $MANIFEST does not exist."
    exit 1
  fi
done < <(yq e '.capabilities[].path' "$MANIFEST")

echo "Success: All capability paths exist."
