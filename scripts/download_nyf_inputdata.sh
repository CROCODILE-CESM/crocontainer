#!/usr/bin/env bash
# Download NYF CESM inputdata for use with crocontainer.
#
# Usage:
#   download_nyf_inputdata.sh [output-dir] [parallel]
#   download_nyf_inputdata.sh [output-dir] --from-glade user@derecho.hpc.ucar.edu
#
# Arguments:
#   output-dir      Where to write the inputdata tree. Default: ./cesm_nyf_inputdata
#   parallel        Number of concurrent transfers. Default: 4
#   --from-glade    Pull via rsync from GLADE campaign storage instead of SVN.
#                   Requires SSH access to the given host. Key/agent auth recommended.
#
# The file list is read from nyf_inputdata_list.txt (same directory as this script).
# Files already present in output-dir are skipped — safe to resume after interruption.
#
# Speed: aria2c is used automatically if installed (brew install aria2 on Mac),
# splitting each file into 4 concurrent chunks. Falls back to wget otherwise.
set -euo pipefail

SVN_BASE="https://svn-ccsm-inputdata.cgd.ucar.edu/trunk/inputdata"
GLADE_BASE="/glade/campaign/cesm/cesmdata/inputdata"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE_LIST="$SCRIPT_DIR/nyf_inputdata_list.txt"

OUTPUT_DIR="./cesm_nyf_inputdata"
PARALLEL=4
GLADE_HOST=""

# Parse args: --from-glade takes the next argument as user@host
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-glade)
            shift
            GLADE_HOST="${1:-}"
            [[ -z "$GLADE_HOST" ]] && { echo "Error: --from-glade requires user@host"; exit 1; }
            ;;
        --*) echo "Unknown flag: $1"; exit 1 ;;
        [0-9]*) PARALLEL="$1" ;;
        *) OUTPUT_DIR="$1" ;;
    esac
    shift
done

mkdir -p "$OUTPUT_DIR"

# Pre-create directory tree to avoid races during parallel operations
while IFS= read -r rel_path || [[ -n "$rel_path" ]]; do
    [[ -z "$rel_path" || "$rel_path" == \#* ]] && continue
    mkdir -p "$OUTPUT_DIR/$(dirname "$rel_path")"
done < "$FILE_LIST"

if [[ -n "$GLADE_HOST" ]]; then
    echo "Pulling NYF inputdata from $GLADE_HOST via rsync (${PARALLEL} parallel)..."

    pull_one() {
        local rel_path="$1"
        local dest="$OUTPUT_DIR/$rel_path"
        if [[ -f "$dest" ]]; then
            echo "  skip (exists): $rel_path"
            return
        fi
        echo "  pulling: $rel_path"
        rsync -az "$GLADE_HOST:$GLADE_BASE/$rel_path" "$dest" \
            || { echo "  FAILED: $rel_path"; rm -f "$dest"; return 1; }
    }
    export -f pull_one
    export GLADE_HOST GLADE_BASE OUTPUT_DIR

    grep -v '^\s*#' "$FILE_LIST" | grep -v '^\s*$' \
        | xargs -P "$PARALLEL" -I{} bash -c 'pull_one "$@"' _ {}
else
    echo "Downloading NYF inputdata to $OUTPUT_DIR (${PARALLEL} parallel connections)..."

    download_one() {
        local rel_path="$1"
        local dest="$OUTPUT_DIR/$rel_path"
        if [[ -f "$dest" ]]; then
            echo "  skip (exists): $rel_path"
            return
        fi
        echo "  downloading: $rel_path"
        if command -v aria2c &>/dev/null; then
            aria2c -x 4 -s 4 -q -d "$(dirname "$dest")" -o "$(basename "$dest")" \
                "$SVN_BASE/$rel_path" || { echo "  FAILED: $rel_path"; rm -f "$dest"; return 1; }
        else
            wget -q -O "$dest" "$SVN_BASE/$rel_path" \
                || { echo "  FAILED: $rel_path"; rm -f "$dest"; return 1; }
        fi
    }
    export -f download_one
    export SVN_BASE OUTPUT_DIR

    grep -v '^\s*#' "$FILE_LIST" | grep -v '^\s*$' \
        | xargs -P "$PARALLEL" -I{} bash -c 'download_one "$@"' _ {}
fi

echo ""
echo "Done. Mount with:"
echo "  Apptainer: --bind $(realpath "$OUTPUT_DIR"):/root/cesm/inputdata"
echo "  Podman:    -v $(realpath "$OUTPUT_DIR"):/root/cesm/inputdata"
