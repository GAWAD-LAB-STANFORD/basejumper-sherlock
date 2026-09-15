#!/bin/bash
# run_bj.sh — launch a BioSkryb basej-* pipeline (basej-public-pipelines) on Sherlock / SLURM
#
# Usage:
#   run_bj.sh --pipeline <name> --input <csv> --outdir <dir> [options]
#
# Required:
#   --pipeline NAME     dnaqc | wgs | rnaqc | rnaproteinqc | somatic | lineage | deepvariant | methylseq
#   --input PATH        input CSV (Illumina: biosampleName,read1,read2 ; see the pipeline README)
#   --outdir PATH       output directory (passed as --outputDir)
#
# Optional:
#   --genome NAME       GRCh38 (default) | GRCm39 | GRCh38_decoy_hla
#   --genomes-base DIR  reference bundle (default: the lab's OAK genomic_references). Passed on the
#                       command line on purpose: upstream's genomes.config bakes this into the
#                       reference paths at load time, so a -c config file is too late to change it.
#   --read-length N     read length used to pick the Ginkgo CNV reference (default 150; same caveat)
#   --mode MODE         wgs pipeline only: wgs (default) | exome
#   --workspace NAME    label used inside the output tree (default: gawadlab)
#   --workflow-id ID    stable run id used in output paths (default: <pipeline>_<timestamp>)
#   --resume            pass -resume (use the same --workflow-id as the original run)
#   --workdir PATH      Nextflow work dir (default: $GROUP_SCRATCH/nextflow_work/<workflow-id>)
#   --submit            run the orchestrator as an sbatch job (recommended for real runs)
#   --time D-HH:MM:SS   orchestrator walltime (default 3-00:00:00)
#   --partition NAME    orchestrator partition (default cgawad)
#   --dry-run           print the command instead of running it
#   --extra "ARGS"      appended verbatim to `nextflow run`
#
# Layout (see bin/setup_sherlock.sh):  <ROOT>/pipelines = BioSkryb/basej-public-pipelines checkout
#                                      <ROOT>/conf      = this repo's Sherlock configs

set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PIPELINES_DIR="$ROOT/pipelines"
CONF="$ROOT/conf"
GROUP_ROOT="/oak/stanford/groups/cgawad"
SCACHE="$GROUP_ROOT/singularity_cache"
TMPDIR_BJ="$GROUP_ROOT/tmp"
NXF_VER_PIN="25.10.2"                 # the new output{} syntax needs Nextflow >= 25.x
NXF_BIN="${NXF_BIN:-$ROOT/bin/nextflow}"   # self-contained launcher fetched by setup_sherlock.sh
[ -x "$NXF_BIN" ] || NXF_BIN="nextflow"

PIPELINE=""; INPUT=""; OUTDIR=""; GENOME="GRCh38"; MODE=""; WORKSPACE="gawadlab"
GENOMES_BASE="/oak/stanford/groups/cgawad/Scripts/Basejumper/genomic_references"; READ_LENGTH="150"
WFID=""; RESUME=""; WORKDIR=""; SUBMIT=0; TIME="3-00:00:00"; PARTITION="cgawad"; DRYRUN=0; EXTRA=""

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ "$#" -eq 0 ] && usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pipeline)    PIPELINE="$2"; shift 2 ;;
    --input)       INPUT="$2"; shift 2 ;;
    --outdir)      OUTDIR="$2"; shift 2 ;;
    --genome)      GENOME="$2"; shift 2 ;;
    --genomes-base) GENOMES_BASE="$2"; shift 2 ;;
    --read-length) READ_LENGTH="$2"; shift 2 ;;
    --mode)        MODE="$2"; shift 2 ;;
    --workspace)   WORKSPACE="$2"; shift 2 ;;
    --workflow-id) WFID="$2"; shift 2 ;;
    --resume)      RESUME="-resume"; shift ;;
    --workdir)     WORKDIR="$2"; shift 2 ;;
    --submit)      SUBMIT=1; shift ;;
    --time)        TIME="$2"; shift 2 ;;
    --partition)   PARTITION="$2"; shift 2 ;;
    --dry-run)     DRYRUN=1; shift ;;
    --extra)       EXTRA="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done
[ -z "$PIPELINE" ] && { echo "ERROR: --pipeline required" >&2; usage; }
[ -z "$INPUT" ]    && { echo "ERROR: --input required"    >&2; usage; }
[ -z "$OUTDIR" ]   && { echo "ERROR: --outdir required"   >&2; usage; }
[ ! -f "$INPUT" ]  && { echo "ERROR: input not found: $INPUT" >&2; exit 2; }

# Resolve pipeline directory + extra config layers
EXTRA_CONF=""
case "$PIPELINE" in
  dnaqc|wgs|rnaqc|rnaproteinqc|somatic|lineage) PDIR="$PIPELINES_DIR/basej-$PIPELINE" ;;
  deepvariant) PDIR="$PIPELINES_DIR/basej-google-deepvariant"; EXTRA_CONF="-c $CONF/deepvariant.config" ;;
  methylseq)   PDIR="$PIPELINES_DIR/nf-core-methylseq" ;;
  *) echo "ERROR: unknown pipeline '$PIPELINE' (dnaqc|wgs|rnaqc|rnaproteinqc|somatic|lineage|deepvariant|methylseq)" >&2; exit 2 ;;
esac
[ -f "$PDIR/main.nf" ] || { echo "ERROR: $PDIR/main.nf missing — run bin/setup_sherlock.sh" >&2; exit 2; }

mkdir -p "$OUTDIR"
INPUT="$(readlink -f "$INPUT")"; OUTDIR="$(readlink -f "$OUTDIR")"
STAMP=$(date +%y%m%d_%H%M%S)
[ -z "$WFID" ] && WFID="${PIPELINE}_${STAMP}"
[ -z "$WORKDIR" ] && WORKDIR="${GROUP_SCRATCH:-/scratch/groups/cgawad}/nextflow_work/${WFID}"
MODE_ARG=""; [ -n "$MODE" ] && MODE_ARG="--mode ${MODE}"

if [ "$PIPELINE" = "methylseq" ]; then
  NF_CMD="$NXF_BIN run $PDIR/main.nf -profile singularity -c $PDIR/conf/sherlock.config \
    --input $INPUT --outdir $OUTDIR --genome $GENOME -work-dir $WORKDIR $RESUME $EXTRA"
else
  NF_CMD="$NXF_BIN run $PDIR/main.nf -profile singularity -c $CONF/sherlock.config $EXTRA_CONF \
    --input_csv $INPUT --outputDir $OUTDIR --genome $GENOME $MODE_ARG \
    --genomes_base $GENOMES_BASE --read_length $READ_LENGTH \
    --workspace $WORKSPACE --workflow_id $WFID -work-dir $WORKDIR $RESUME $EXTRA"
fi

BODY=$(cat <<EOF
set -euo pipefail
type module >/dev/null 2>&1 || source "\${LMOD_PKG:-/share/software/user/open/lmod/lmod}/init/bash" 2>/dev/null || true
module purge
module load java/17.0.4 2>/dev/null || module load java
export NXF_VER=${NXF_VER_PIN}
export NXF_HOME=${ROOT}/.nextflow
export NXF_TEMP=${TMPDIR_BJ}
export NXF_SINGULARITY_CACHEDIR=${SCACHE}
export APPTAINER_CACHEDIR=${SCACHE} SINGULARITY_CACHEDIR=${SCACHE}
export APPTAINER_TMPDIR=${TMPDIR_BJ} SINGULARITY_TMPDIR=${TMPDIR_BJ}
mkdir -p \$NXF_HOME \$NXF_TEMP ${SCACHE} ${WORKDIR}
cd ${PDIR}
echo "=== ${PIPELINE} (${WFID}) started \$(date) on \$(hostname)"
echo "Input:   ${INPUT}"
echo "Outdir:  ${OUTDIR}"
echo "Workdir: ${WORKDIR}"
echo "Cmd:     ${NF_CMD}"
${NF_CMD}
echo "=== ${PIPELINE} (${WFID}) finished \$(date)"
EOF
)

if [ "$DRYRUN" -eq 1 ]; then echo "=== DRY RUN — would execute:"; echo "$BODY"; exit 0; fi
if [ "$SUBMIT" -eq 1 ]; then
  LOG="${OUTDIR}/run_${WFID}.log"
  echo "Submitting orchestrator job (log: $LOG)"
  sbatch --job-name="nf_${PIPELINE}" --partition="$PARTITION" --time="$TIME" \
         --cpus-per-task=2 --mem=8G --output="$LOG" --error="$LOG" --wrap="$BODY"
else
  echo "Running inline (use --submit for real runs)"
  eval "$BODY"
fi
