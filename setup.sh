#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFS_DIR="$SCRIPT_DIR/refs"
S3_BASE="https://pipelinejobs.s3.amazonaws.com/PUBLIC_USER"

echo "Setting up nf-atlas-pipeline reference files in $REFS_DIR"
mkdir -p "$REFS_DIR"

download_if_missing() {
    local url="$1"
    local dest="$2"
    local name
    name="$(basename "$dest")"
    if [[ -f "$dest" ]]; then
        echo "Already present: $name — skipping."
    else
        echo "Downloading $name ..."
        curl --fail -L -o "$dest" "$url"
        echo "Done: $name"
    fi
}

download_if_missing \
    "$S3_BASE/GRCh38.primary_assembly.genome.fa.gz" \
    "$REFS_DIR/GRCh38.primary_assembly.genome.fa.gz"

download_if_missing \
    "$S3_BASE/gencode.v39.annotation.gtf.gz" \
    "$REFS_DIR/gencode.v39.annotation.gtf.gz"

echo ""
echo "Setup complete. Reference files are in $REFS_DIR"
