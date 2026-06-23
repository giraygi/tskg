#!/bin/bash
# =============================================================================
# prep.sh
#
# Ontology preparation pipeline. Runs as the `ontology-prep` service in
# docker-compose and exits with code 0 on success.
#
# The `qlever` service depends on this completing successfully before it
# attempts to index and start the SPARQL server.
#
# Steps:
#   1. Collect Matomo action counts
#   2. Download ontologies declared in ontologies.json
#   3. Convert OWL/RDF/XML → Turtle with ROBOT
#   4. Copy pre-existing .ttl files
#   5. Merge versions and produce .nq files (merge_versions.sh + RIOT)
#   6. Write a completion marker so downstream services know data is ready
# =============================================================================

set -euo pipefail

CONVERTED_DIR="/data/ontologies/converted"
MARKER="/data/.prep_done"

mkdir -p /data/ontologies "$CONVERTED_DIR"
if [[ -d "/data/terminology" ]]; then
    echo "=== [prep 0/4] adapting paths of local terminologies ==="
    #mkdir -p /opt/ols/dataload/terminology
    #cp -R /data/terminology/. /opt/ols/dataload/terminology/
    sed -i 's@opt/ols/dataload/terminology/vocabularies@data/terminology/vocabularies@g' /app/ontologies.json
fi

# ---------------------------------------------------------------------------
# Step 1 — Matomo stats
# ---------------------------------------------------------------------------
echo "=== [prep 1/4] collecting Matomo ontology stats ==="
cd /data
python3 /app/matomo_ontology_stats.py --min-actions $MIN_ACTIONS --token $TOKEN --date $DATE

# ---------------------------------------------------------------------------
# Step 2 — Download ontologies
# ---------------------------------------------------------------------------
echo ""
echo "=== [prep 2/4] downloading ontologies ==="
python3 /app/download_ontologies.py \
    --json-file /app/ontologies.json \
    --output-dir /data/ontologies \
    --ontology-action-counts /data/ontology_action_counts.json

# ---------------------------------------------------------------------------
# Step 3 & 4 — Convert to Turtle, copy existing .ttl files
#
# Dedup: after converting/copying, compare the SHA-256 of the new file
# against the most recently written version for that ontology in converted/.
# If they match the content is unchanged — discard the new file to avoid
# creating a redundant extra version on every consecutive run.
# ---------------------------------------------------------------------------
echo ""
echo "=== [prep 3/4] converting to Turtle ==="
cd /data/ontologies

# Helper: returns the SHA-256 hex digest of a file
sha256_of() { sha256sum "$1" | awk '{print $1}'; }

# Helper: given an ontology stem (e.g. "efo_12-06-2025--10-00-00"),
# find the most-recently-modified existing .ttl in CONVERTED_DIR whose
# filename starts with the same prefix (everything before the first "_").
latest_existing_ttl() {
    local stem="$1"                          # e.g. efo_12-06-2025--10-00-00
    local prefix="${stem%%_*}"               # e.g. efo
    # Sort by modification time descending; take the first hit
    ls -t "$CONVERTED_DIR"/${prefix}_*.ttl 2>/dev/null | head -1 || true
}

# Helper: convert or copy a file into CONVERTED_DIR, skipping if content
# is identical to the latest existing version.
#   $1  source file path (in /data/ontologies)
#   $2  destination stem name (without .ttl extension)
#   $3  "convert" | "copy"
dedup_install() {
    local src="$1"
    local stem="$2"      # e.g. efo_12-06-2025--10-00-00
    local mode="$3"
    local dest="$CONVERTED_DIR/${stem}.ttl"
    local tmp="$CONVERTED_DIR/${stem}.ttl.tmp"

    # Produce the candidate file into a .tmp path first
    if [[ "$mode" == "convert" ]]; then
        robot convert --input "$src" --format ttl --output "$tmp"
    else
        cp "$src" "$tmp"
    fi

    # Check whether an identical version already exists
    local existing
    existing=$(latest_existing_ttl "$stem")
    if [[ -n "$existing" ]]; then
        local hash_new hash_old
        hash_new=$(sha256_of "$tmp")
        hash_old=$(sha256_of "$existing")
        if [[ "$hash_new" == "$hash_old" ]]; then
            echo "    [DEDUP] ${stem%%_*}: content unchanged — discarding new copy"
            rm "$tmp"
            return
        fi
    fi

    mv "$tmp" "$dest"
    echo "    [NEW]   $dest"
}

for f in ./*.owl ./*.rdf ./*.xml; do
    [ -e "$f" ] || continue
    base="${f%.*}"
    stem="${base##*/}"
    echo "  robot convert: $f"
    dedup_install "$f" "$stem" convert
done

for f in ./*.ttl; do
    [ -e "$f" ] || continue
    stem="${f%.*}"
    stem="${stem##*/}"
    echo "  copying ttl: $f"
    dedup_install "$f" "$stem" copy
done

# ---------------------------------------------------------------------------
# Step 5 — Merge versions → .nq
# ---------------------------------------------------------------------------
echo ""
echo "=== [prep 4/4] merging versions → .nq ==="
cd "$CONVERTED_DIR"
merge_versions.sh

# ---------------------------------------------------------------------------
# Step 6 — Write completion marker
# ---------------------------------------------------------------------------
touch "$MARKER"
echo ""
echo "=== Preparation complete. Data is ready for indexing. ==="
