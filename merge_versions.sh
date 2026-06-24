#!/bin/bash

prefixes=$(ls *.ttl | grep '_' | sed 's/_.*//' | sort -u)

echo "Found prefixes: $prefixes"

for prefix in $prefixes; do
    files=$(ls ${prefix}_*.ttl 2>/dev/null)
    count=$(echo "$files" | wc -w)

    if [ "$count" -lt 2 ]; then
        ttl_file=$files
        VERSION_IRI=$(riot --output=nt "$ttl_file" | grep "owl#versionIRI" | awk '{print $3}' | tr -d '<>')
        output="${ttl_file%.ttl}.nq"

        if [ -z "$VERSION_IRI" ]; then
            echo "  WARNING: No versionIRI found in $ttl_file, using filename as graph URI"
            VERSION_IRI="http://example.org/ontologies/${ttl_file%.ttl}"
        fi

        echo "Single file for prefix '$prefix': $ttl_file → $output (graph: $VERSION_IRI)"
        riot --output=nt "$ttl_file" \
            | awk -v g="<$VERSION_IRI>" '{sub(/ \.$/, " " g " ."); print}' > "$output"
        continue
    fi

    output="${prefix}_merged.nq"
    > "$output"
    echo "Merging files for prefix '$prefix' into $output"

    for ttl_file in $files; do
        VERSION_IRI=$(riot --output=nt "$ttl_file" | grep "owl#versionIRI" | awk '{print $3}' | tr -d '<>')

        if [ -z "$VERSION_IRI" ]; then
            echo "  WARNING: No versionIRI found in $ttl_file, skipping"
            continue
        fi

        echo "  $ttl_file → $VERSION_IRI"
        riot --output=nt "$ttl_file" \
            | awk -v g="<$VERSION_IRI>" '{sub(/ \.$/, " " g " ."); print}' >> "$output"
    done

    echo "  Done. Output: $output"
    echo ""
done

# Convert standalone files (no underscore) to nq individually
echo "Converting standalone files to nq:"
for ttl_file in $(ls *.ttl | grep -v '_'); do
    VERSION_IRI=$(riot --output=nt "$ttl_file" | grep "owl#versionIRI" | awk '{print $3}' | tr -d '<>')
    output="${ttl_file%.ttl}.nq"

    if [ -z "$VERSION_IRI" ]; then
        echo "  WARNING: No versionIRI found in $ttl_file, using filename as graph URI"
        VERSION_IRI="http://example.org/ontologies/${ttl_file%.ttl}"
    fi

    echo "  $ttl_file → $output (graph: $VERSION_IRI)"
    riot --output=nt "$ttl_file" \
        | awk -v g="<$VERSION_IRI>" '{sub(/ \.$/, " " g " ."); print}' > "$output"
done

echo ""
echo "All done!"
