#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory this script lives in (same place as rnaseq.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RNASEQ_SH="$SCRIPT_DIR/rnaseq.sh"

usage() {
    cat <<'EOF'
Usage: batch_rnaseq.sh [OPTIONS] [base_dir]

Run nf-core/rnaseq on multiple samples, one subdirectory per sample.

Options:
  --docker       Use Docker profile
  --singularity  Use Singularity profile (default)
  --skip-done    Skip any sample that already has a run-*/output.tgz archive
  -h, --help     Show this help and exit

Arguments:
  base_dir   Root directory containing per-sample subdirectories.
             Defaults to the current directory.

Expected layout
  base_dir/
    sample_A/
      sampleA_R1_001.fastq.gz
      sampleA_R2_001.fastq.gz
    sample_B/
      sampleB.fastq.gz
    ...

Each sample folder must contain exactly 1 (single-end) or 2 (paired-end)
*.fastq.gz / *.fq.gz files.  Results are written to a run-<timestamp>/
directory created inside the sample folder.
EOF
    exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
PROFILE="singularity"
BASE_DIR=""
SKIP_DONE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker)      PROFILE="docker";      shift ;;
        --singularity) PROFILE="singularity"; shift ;;
        --skip-done)   SKIP_DONE=true;        shift ;;
        -h|--help)     usage ;;
        -*)
            echo "Error: unknown option: $1" >&2
            usage
            ;;
        *)
            if [[ -z "$BASE_DIR" ]]; then
                BASE_DIR="$1"
            else
                echo "Error: too many positional arguments." >&2
                usage
            fi
            shift
            ;;
    esac
done

# Default to cwd and resolve to an absolute path.
BASE_DIR="${BASE_DIR:-.}"
BASE_DIR="$(cd "$BASE_DIR" && pwd)"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
[[ -f "$RNASEQ_SH" ]] || { echo "Error: rnaseq.sh not found at $RNASEQ_SH" >&2; exit 1; }
[[ -x "$RNASEQ_SH" ]] || { echo "Error: rnaseq.sh is not executable — run: chmod +x $RNASEQ_SH" >&2; exit 1; }

echo "========================================"
echo "Batch nf-core/rnaseq"
echo "  Base directory : $BASE_DIR"
echo "  Profile        : $PROFILE"
echo "  Skip done      : $SKIP_DONE"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Discover sample directories (direct children only)
# ---------------------------------------------------------------------------
SAMPLE_DIRS=()
for d in "$BASE_DIR"/*/; do
    [[ -d "$d" ]] && SAMPLE_DIRS+=("${d%/}")
done

if [[ ${#SAMPLE_DIRS[@]} -eq 0 ]]; then
    echo "Error: no subdirectories found in $BASE_DIR" >&2
    exit 1
fi

echo "Found ${#SAMPLE_DIRS[@]} subdirector$([ ${#SAMPLE_DIRS[@]} -eq 1 ] && echo 'y' || echo 'ies') to scan."
echo ""

# ---------------------------------------------------------------------------
# Process each sample
# ---------------------------------------------------------------------------
SUCCESSES=()
SKIPPED=()
FAILURES=()

for SAMPLE_DIR in "${SAMPLE_DIRS[@]}"; do
    SAMPLE_NAME="$(basename "$SAMPLE_DIR")"

    # --- Skip already-processed samples ---
    if [[ "$SKIP_DONE" == true ]]; then
        ALREADY_DONE=false
        for archive in "$SAMPLE_DIR"/run-*/output.tgz; do
            [[ -f "$archive" ]] && ALREADY_DONE=true && break
        done
        if [[ "$ALREADY_DONE" == true ]]; then
            echo "Skipping $SAMPLE_NAME — output archive already exists."
            SKIPPED+=("$SAMPLE_NAME (already done)")
            echo ""
            continue
        fi
    fi

    # --- Collect FASTQ files in this directory ---
    FASTQS=()
    for f in "$SAMPLE_DIR"/*.fastq.gz "$SAMPLE_DIR"/*.fq.gz; do
        [[ -f "$f" ]] && FASTQS+=("$f")
    done

    if [[ ${#FASTQS[@]} -eq 0 ]]; then
        echo "Skipping $SAMPLE_NAME — no *.fastq.gz / *.fq.gz files found."
        SKIPPED+=("$SAMPLE_NAME (no FASTQs)")
        echo ""
        continue
    fi

    if [[ ${#FASTQS[@]} -gt 2 ]]; then
        echo "Skipping $SAMPLE_NAME — ${#FASTQS[@]} FASTQ files found (expected 1 or 2):" >&2
        for f in "${FASTQS[@]}"; do echo "  - $(basename "$f")" >&2; done
        FAILURES+=("$SAMPLE_NAME (${#FASTQS[@]} FASTQs — expected 1 or 2)")
        echo ""
        continue
    fi

    echo "----------------------------------------"
    echo "Sample  : $SAMPLE_NAME  [$(date '+%Y-%m-%d %H:%M:%S')]"
    for f in "${FASTQS[@]}"; do echo "  FASTQ : $(basename "$f")"; done
    echo "----------------------------------------"

    # Pass filenames only — rnaseq.sh is invoked from inside the sample folder
    # and resolves paths relative to cwd (which will be SAMPLE_DIR).
    FASTQ_ARGS=()
    for f in "${FASTQS[@]}"; do
        FASTQ_ARGS+=("$(basename "$f")")
    done

    # Run rnaseq.sh from within the sample directory.
    # The subshell isolates the `cd` and captures the exit code for the if-check
    # without triggering set -e on failure.
    if (
        cd "$SAMPLE_DIR"
        "$RNASEQ_SH" "--$PROFILE" "${FASTQ_ARGS[@]}"
    ); then
        SUCCESSES+=("$SAMPLE_NAME")
        echo ""
        echo "✓ $SAMPLE_NAME — done."
    else
        FAILURES+=("$SAMPLE_NAME")
        echo ""
        echo "✗ $SAMPLE_NAME — FAILED."
    fi
    echo ""
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "========================================"
echo "Batch run summary"
echo ""

echo "  ✓ Successful : ${#SUCCESSES[@]}"
if [[ ${#SUCCESSES[@]} -gt 0 ]]; then
    for s in "${SUCCESSES[@]}"; do echo "      $s"; done
fi

echo "  — Skipped    : ${#SKIPPED[@]}"
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    for s in "${SKIPPED[@]}"; do echo "      $s"; done
fi

echo "  ✗ Failed     : ${#FAILURES[@]}"
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    for s in "${FAILURES[@]}"; do echo "      $s"; done
fi

echo "========================================"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    echo "One or more samples failed — see output above for details." >&2
    exit 1
fi

echo ""
echo "All samples processed successfully."
