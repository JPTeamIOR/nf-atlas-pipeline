#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") [--docker|--singularity] <fastq1.fastq.gz> [fastq2.fastq.gz]"
    echo ""
    echo "Options:"
    echo "  --docker       Use Docker profile"
    echo "  --singularity  Use Singularity profile (default)"
    echo ""
    echo "Arguments:"
    echo "  fastq1.fastq.gz   Read 1 FASTQ file (required)"
    echo "  fastq2.fastq.gz   Read 2 FASTQ file (optional, for paired-end)"
    exit 1
}

to_abs_path() {
    echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

# --- Parse arguments ---
PROFILE="singularity"
FASTQ1=""
FASTQ2=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker)      PROFILE="docker";      shift ;;
        --singularity) PROFILE="singularity"; shift ;;
        -*)
            echo "Error: unknown option: $1"
            usage
            ;;
        *)
            if   [[ -z "$FASTQ1" ]]; then FASTQ1="$1"
            elif [[ -z "$FASTQ2" ]]; then FASTQ2="$1"
            else echo "Error: too many arguments."; usage
            fi
            shift
            ;;
    esac
done

[[ -n "$FASTQ1" ]] || { echo "Error: at least one FASTQ file is required."; usage; }

# --- Validate inputs ---
[[ -f "$FASTQ1" ]] || { echo "Error: file not found: $FASTQ1"; exit 1; }
[[ -z "$FASTQ2" ]] || [[ -f "$FASTQ2" ]] || { echo "Error: file not found: $FASTQ2"; exit 1; }

FASTQ1_ABS="$(to_abs_path "$FASTQ1")"
FASTQ2_ABS=""
[[ -z "$FASTQ2" ]] || FASTQ2_ABS="$(to_abs_path "$FASTQ2")"

# --- Validate reference files ---
REFS_DIR="$SCRIPT_DIR/refs"
[[ -f "$REFS_DIR/GRCh38.primary_assembly.genome.fa.gz" ]] || \
    { echo "Error: reference genome not found. Run setup.sh first."; exit 1; }
[[ -f "$REFS_DIR/gencode.v39.annotation.gtf.gz" ]] || \
    { echo "Error: GTF annotation not found. Run setup.sh first."; exit 1; }

# --- Derive sample name from first file ---
SAMPLE_NAME="$(basename "$FASTQ1_ABS" .fastq.gz)"
for suffix in "_R1_001" "_R2_001" "_R1" "_R2" "_1" "_2"; do
    if [[ "$SAMPLE_NAME" == *"$suffix" ]]; then
        SAMPLE_NAME="${SAMPLE_NAME%$suffix}"
        break
    fi
done

# --- Set up run directory ---
TIMESTAMP="$(date +%Y-%m-%dT%H%M%S)"
RUN_DIR="$(pwd)/run-$TIMESTAMP"
OUT_DIR="$RUN_DIR/out"
LOGS_DIR="$RUN_DIR/logs"
WORK_DIR="$RUN_DIR/work"

mkdir -p "$OUT_DIR" "$LOGS_DIR"

echo "Run directory : $RUN_DIR"
echo "Sample name   : $SAMPLE_NAME"
echo "Profile       : $PROFILE"
[[ -n "$FASTQ2_ABS" ]] && echo "Mode          : paired-end" || echo "Mode          : single-end"

# --- Generate samplesheet ---
SAMPLESHEET="$RUN_DIR/samplesheet.csv"
echo "sample,fastq_1,fastq_2,strandedness" > "$SAMPLESHEET"
echo "$SAMPLE_NAME,$FASTQ1_ABS,$FASTQ2_ABS,auto" >> "$SAMPLESHEET"

echo ""
echo "Samplesheet:"
cat "$SAMPLESHEET"
echo ""

# --- Run nextflow (from RUN_DIR so .nextflow/ lands there) ---
echo "Running nf-core/rnaseq ..."
(
    cd "$RUN_DIR"
    nextflow \
        -log "$LOGS_DIR/${TIMESTAMP}.nextflow.log" \
        run nf-core/rnaseq \
        -r 3.17.0 \
        -c "$SCRIPT_DIR/rnaseq.config" \
        -w "$WORK_DIR" \
        --input "$SAMPLESHEET" \
        --outdir "$OUT_DIR" \
        --fasta "$REFS_DIR/GRCh38.primary_assembly.genome.fa.gz" \
        --gtf "$REFS_DIR/gencode.v39.annotation.gtf.gz" \
        --aligner star_salmon \
        --skip_multiqc \
        --skip_preseq \
        --skip_biotype_qc \
        --skip_qualimap \
        --skip_dupradar \
        --skip_rseqc \
        --skip_deseq2_qc \
        --skip_markduplicates \
        --skip_stringtie \
        --skip_bigwig \
        -profile "$PROFILE"
)

# --- Relocate pipeline_info to logs (not included in archive) ---
if [[ -d "$OUT_DIR/pipeline_info" ]]; then
    mv "$OUT_DIR/pipeline_info" "$LOGS_DIR/pipeline_info"
fi

# --- Promote target TSV files from star_salmon/ to out/ root ---
TARGET_FILES=(
    "salmon.merged.transcript_counts.tsv"
    "salmon.merged.gene_counts.tsv"
    "salmon.merged.transcript_lengths.tsv"
    "salmon.merged.gene_lengths.tsv"
    "salmon.merged.transcript_tpm.tsv"
    "salmon.merged.gene_tpm.tsv"
)

echo "Moving result files ..."
for f in "${TARGET_FILES[@]}"; do
    mv "$OUT_DIR/star_salmon/$f" "$OUT_DIR/$f"
done

# --- Remove everything in out/ except the 6 TSV files ---
echo "Cleaning up output directory ..."
for item in "$OUT_DIR"/*; do
    name="$(basename "$item")"
    keep=false
    for f in "${TARGET_FILES[@]}"; do
        [[ "$name" == "$f" ]] && keep=true && break
    done
    if [[ "$keep" == false ]]; then
        echo "  Removing: $name"
        rm -rf "$item"
    fi
done

# --- Delete nextflow work directory ---
echo "Deleting work directory ..."
rm -rf "$WORK_DIR"

# --- Create archive (mirrors original: tar ./out from RUN_DIR) ---
echo "Creating output archive ..."
tar -czf "$RUN_DIR/output.tgz" -C "$RUN_DIR" ./out

echo ""
echo "Done."
echo "  Archive : $RUN_DIR/output.tgz"
echo "  TSV files: $OUT_DIR/"
echo "  Logs     : $LOGS_DIR/"
