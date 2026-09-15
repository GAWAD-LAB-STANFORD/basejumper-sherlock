#!/bin/bash
#SBATCH --job-name=bwamem2_index
#SBATCH --partition=cgawad
#SBATCH --cpus-per-task=8
#SBATCH --mem=120G
#SBATCH --time=08:00:00
#SBATCH --output=bwamem2_index_%j.log
#
# Builds the BWA-MEM2 index that the open-source basej-dnaqc / basej-wgs path requires
# (conf/genomes.config: bwamem2_reference = .../GATK_bundle/Sequence_bwamem2). The old
# Sentieon-era bundle only has the BWA 0.7 index (.bwt/.pac/.sa), which BWA-MEM2 cannot use.
# Uses the pipeline's own bwa-mem2 container so the index matches the aligner build.
# GRCh38 needs ~90 GB RAM and roughly 1-2 h.
set -euo pipefail
GENOMES="${GENOMES:-/oak/stanford/groups/cgawad/Scripts/Basejumper/genomic_references}"
SEQ="$GENOMES/genomes/Homo_sapiens/NCBI/GRCh38/Annotation/GATK_bundle/Sequence"
OUT="$GENOMES/genomes/Homo_sapiens/NCBI/GRCh38/Annotation/GATK_bundle/Sequence_bwamem2"
IMG="${IMG:-docker://ghcr.io/gawad-lab-stanford/basejumper_bwamem2_samtools_2.2.1}"
export APPTAINER_CACHEDIR=/oak/stanford/groups/cgawad/singularity_cache
export APPTAINER_TMPDIR=/oak/stanford/groups/cgawad/tmp

[ -s "$SEQ/genome.fa" ] || { echo "reference FASTA not found: $SEQ/genome.fa" >&2; exit 1; }
mkdir -p "$OUT"
# The pipeline points at the directory and appends genome.fa as the prefix; keep the FASTA
# (and .fai/.dict when present) reachable under the same name.
for f in genome.fa genome.fa.fai genome.dict; do [ -e "$SEQ/$f" ] && ln -sf "$SEQ/$f" "$OUT/$f"; done

echo "indexing $SEQ/genome.fa -> $OUT/genome.fa.* ($(date))"
apptainer exec -B /oak/stanford/groups/cgawad "$IMG" \
  bwa-mem2 index -p "$OUT/genome.fa" "$SEQ/genome.fa"
echo "done $(date)"; ls -lh "$OUT"
