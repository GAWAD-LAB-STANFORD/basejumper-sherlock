#!/bin/bash
# setup_sherlock.sh — one-time (or update) setup of the Gawad Lab Basejumper v2 layout on Sherlock.
#
#   git clone https://github.com/GAWAD-LAB-STANFORD/basejumper-sherlock \
#       /oak/stanford/groups/cgawad/Scripts/Basejumper/v2
#   bash /oak/stanford/groups/cgawad/Scripts/Basejumper/v2/bin/setup_sherlock.sh
#
# What it does: checks out BioSkryb/basej-public-pipelines at the pinned commit into <ROOT>/pipelines,
# fetches the self-contained Nextflow launcher into <ROOT>/bin, creates the shared cache/tmp/work
# directories, and reports what the reference bundle is still missing. Read-only otherwise.
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
UPSTREAM_REPO="https://github.com/BioSkryb/basej-public-pipelines"
UPSTREAM_REF="${UPSTREAM_REF:-be348188cee1}"     # pinned 2026-09-14; bump deliberately
GROUP_ROOT="/oak/stanford/groups/cgawad"
GENOMES="${GENOMES:-$GROUP_ROOT/Scripts/Basejumper/genomic_references}"
type module >/dev/null 2>&1 || source /etc/profile.d/lmod.sh 2>/dev/null || true

echo "== 1. upstream pipelines -> $ROOT/pipelines @ $UPSTREAM_REF"
if [ -d "$ROOT/pipelines/.git" ]; then git -C "$ROOT/pipelines" fetch -q origin
else git clone -q "$UPSTREAM_REPO" "$ROOT/pipelines"; fi
git -C "$ROOT/pipelines" checkout -q "$UPSTREAM_REF" && git -C "$ROOT/pipelines" log -1 --format='   at %h %ad %s' --date=short

echo "== 2. Nextflow launcher (NXF_VER is set per run by run_bj.sh)"
if [ ! -x "$ROOT/bin/nextflow" ]; then (cd "$ROOT/bin" && curl -fsSL https://get.nextflow.io | bash >/dev/null 2>&1) || echo "   launcher download failed — install nextflow on PATH instead"; fi
[ -x "$ROOT/bin/nextflow" ] && echo "   $ROOT/bin/nextflow"

echo "== 3. shared directories"
for d in "$GROUP_ROOT/singularity_cache" "$GROUP_ROOT/tmp" "${GROUP_SCRATCH:-/scratch/groups/cgawad}/nextflow_work"; do
  mkdir -p "$d" 2>/dev/null && echo "   ok $d" || echo "   cannot create $d"
done

echo "== 4. prerequisites"
echo -n "   container runtime: "; (which apptainer || which singularity) 2>/dev/null || echo "NONE on PATH — check 'ml spider apptainer'"
echo -n "   java (Nextflow 25 needs 17-24): "; (module load java/17.0.4 2>/dev/null || module load java 2>/dev/null); java -version 2>&1 | head -1 || echo "none — check 'ml spider java'"
echo -n "   nextflow ${NXF_VER:-25.10.2}: "; NXF_VER="${NXF_VER:-25.10.2}" "$ROOT/bin/nextflow" -version 2>/dev/null | grep -m1 -E 'version' || echo "could not start (java?)"

echo "== 5. reference bundle: $GENOMES"
B="genomes/Homo_sapiens/NCBI/GRCh38/Annotation"
for p in "$B/GATK_bundle/Sequence/genome.fa" "$B/GATK_bundle/Sequence_bwamem2" "$B/Intervals/wgs_intervals.bed" "$B/GATK_bundle/wgs_coverage_regions.interval_list"; do
  [ -e "$GENOMES/$p" ] && echo "   ok      $p" || echo "   MISSING $p"
done
echo "   (Sequence_bwamem2 missing => sbatch $ROOT/bin/build_bwamem2_index.sbatch)"
echo "   Ginkgo refs expected under the genomes.config ginko_ref_dir keys (bin_size x read_length);"
echo "   list what exists:"; ls "$GENOMES/dev-resources" 2>/dev/null | sed 's/^/     /' | head -20
echo "== done"
