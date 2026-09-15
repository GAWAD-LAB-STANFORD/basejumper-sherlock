# Migration notes: old Sherlock Basejumper patch → this layer

Written 2026-09-14 from a review of `/oak/stanford/groups/cgawad/Scripts/Basejumper/` (the
`bj-*` 2025 copies with the lab's Sherlock patch) against BioSkryb's current public release.

## The old setup, in one paragraph

Six BioSkryb repos (`bj-dna-qc` 2.0.9, `bj-wgs`, `bj-wes`, `bj-cnv`, `bj-somatic-variantcalling`,
`bj-expression`) plus `nf-core-methylseq`, each patched by `bin/patch_pipelines.py`: it copied
`environment/slurm/sherlock/clean.config` from `bj-dna-qc/nf-bioskryb-utils/conf/` into the other
pipelines and rewrote every AWS queue name to `cgawad`. `environment.config` carried the real
Sherlock adaptation (executor `slurm`, queue `cgawad`, `beforeScript` module loads, Sentieon
license passed into the container via `containerOptions --env`, OAK cache/tmp), and
`sherlock_overrides.config` capped the heavy processes for the partition. `bin/run_bj.sh` drove
runs (`nextflow/24.10.4` module, `-profile singularity`, `--input_csv`, `--publish_dir`).

## Review findings on the old patch (kept for the record)

1. **Dead configs.** `slurm.config` and `sherlock.config` were only reachable through
   `sherlock.config`, which no `nextflow.config` included. The `executor { queueSize = 50;
   submitRateLimit = '5 sec' }` block, `process.scratch`, and `params.vep_cache` therefore never
   applied (Nextflow defaults: queueSize 100, no rate limit; VEP cache unset for somatic runs).
2. **Overrides not propagated.** `sherlock_overrides.config` was not in `patch_pipelines.py`'s
   `SHERLOCK_CONFIGS` list, so only `bj-dna-qc` had the partition-sized resource caps.
3. **GPU requests on a GPU-less partition.** `modules.config` still gave
   `DEEPVARIANT_CALL_VARIANTS.*` `containerOptions = '--gpus all'` and `accelerator = 1`;
   the overrides file only covered the `GOOGLE_DEEPVARIANT_*`/`PARABRICKS_*` names.
4. **Silent sample loss.** `errorStrategy = { task.attempt <= 2 ? 'retry' : 'ignore' }` drops a
   sample that fails twice without failing the run.
5. **Nextflow version.** The module `nextflow/24.10.4` cannot run the new pipelines (finalized
   `output {}` / `publish:` syntax; upstream CI pins 25.10.2).
6. **Index format.** The bundle in `genomic_references/` carries the BWA 0.7 index the Sentieon
   path used; the open-source aligner needs a BWA-MEM2 index (`Sequence_bwamem2/`).
7. **Sentieon plumbing** (`SENTIEON_LICENSE=srcc-license-srcf.stanford.edu:8990` exported and
   passed with `--env` into Singularity, `module load biology sentieon`) is only needed for
   `--pipeline_tool sentieon`; the default path no longer requires it.

## What carries over unchanged

- Partition and sizing: `cgawad`, 4 nodes × 24 CPU × 384 GB × 7 d, no GPUs → 20 CPU / 350 GB / 72 h.
- OAK locations: `singularity_cache/`, `tmp/`, and `genomes_base =
  Scripts/Basejumper/genomic_references` (same `genomes/Homo_sapiens/NCBI/GRCh38/...` layout).
- Driver ergonomics of `run_bj.sh` (`--pipeline/--input/--outdir/--submit/--dry-run/--extra`).

## Parameter renames to remember

| old | new |
|---|---|
| `--publish_dir` | `--outputDir` (also drives `workflow_outputs/<workspace>/<workflow_id>/...`) |
| (implicit) | `--workspace`, `--workflow_id` — stable ids for output paths and resume |
| `read_length` default 150 | default **50** (selects the Ginkgo reference); pass 150 for 150-bp reads |
| `bj-wes` | `basej-wgs --mode exome` |
| `-c conf/nf_test.config` style profiles | `-profile singularity -c conf/sherlock.config` |

## Using the Sentieon path anyway

Pass `--pipeline_tool sentieon` and add, in a small extra `-c` file:
`process.containerOptions = '--env SENTIEON_LICENSE=srcc-license-srcf.stanford.edu:8990 --env SENTIEON_LICENSE_SERVER=srcc-license-srcf.stanford.edu:8990'`
plus `module load biology sentieon` in `process.beforeScript`. The Sentieon container is BioSkryb's
private ECR image and is not mirrored here.

## Retiring the old tree

- `Basejumper/pipelines/bj-*` → move to `Basejumper/_legacy/` (keeps the June-2026 runs reproducible).
- `Basejumper/_archive/` holds hundreds of GB of Nextflow `work/` dirs and staged genomes
  (many duplicate `genome.fa`/`.bwt` copies) — delete once the corresponding outputs are
  confirmed published. Lab decision; nothing here touches it.
- GitHub: archive the org's `bj-dna-qc` fork (superseded by `basej-dnaqc`).
