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
# ---------------------------------------------------------------------------
echo ""
echo "=== [prep 3/4] converting to Turtle ==="
cd /data/ontologies

for f in ./*.owl ./*.rdf ./*.xml; do
    [ -e "$f" ] || continue
    base="${f%.*}"
    echo "  robot convert: $f"
    robot convert --input "$f" --format ttl --output "$CONVERTED_DIR/${base##*/}.ttl"
done

for f in ./*.ttl; do
    [ -e "$f" ] || continue
    echo "  copying ttl: $f"
    cp "$f" "$CONVERTED_DIR/"
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
