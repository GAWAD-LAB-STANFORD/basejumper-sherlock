# basejumper-sherlock

Gawad Lab layer for running BioSkryb's **BaseJumper public pipelines**
([BioSkryb/basej-public-pipelines](https://github.com/BioSkryb/basej-public-pipelines)) on
Stanford **Sherlock** (SLURM + Apptainer, `cgawad` partition). Upstream code is not copied
here; this repo holds only what Sherlock needs on top of it.

> **Status (2026-09-14):** written against upstream commit `be348188cee1` from the public
> sources and the lab's previous Sherlock setup. Not yet exercised on Sherlock — see
> [Validation checklist](#validation-checklist) before the first real run.

## What changed upstream (and why this layer is new)

BioSkryb consolidated and renamed the pipelines and made them **open-source by default**
(`pipeline_tool = opensource`: BWA-MEM2, samtools markdup, Picard, preseq, Ginkgo). No Sentieon
license is needed, which removes most of the plumbing the old lab patch existed for.

| Lab's previous copy | Upstream now | Notes |
|---|---|---|
| `bj-dna-qc` 2.0.9 | **`basej-dnaqc`** | low-pass single-cell DNA QC; Ginkgo CNV folded in (no separate `bj-cnv`) |
| `bj-wgs` + `bj-wes` | **`basej-wgs`** | one pipeline, `--mode wgs` or `--mode exome` |
| `bj-expression` | **`basej-rnaqc`** | plus **`basej-rnaproteinqc`** for ResolveDOGMA RNA + ADT |
| `bj-somatic-variantcalling` | **`basej-somatic`** + **`basej-lineage`** | somatic filtering (VCF-start, no license) and phylogeny/signatures split out |
| — | **`basej-google-deepvariant`** | germline calling with BioSkryb's PTA-trained model (CPU on Sherlock) |
| `nf-core-methylseq` | unchanged | still launched through `run_bj.sh --pipeline methylseq` |

The new pipelines use Nextflow's finalized workflow-output syntax and therefore need
**Nextflow ≥ 25.x** (upstream CI pins 25.10.2); Sherlock's `nextflow/24.10.4` module is too old,
so the driver runs a self-contained launcher with `NXF_VER=25.10.2` (needs Java 17–24).

## Layout

```
conf/sherlock.config          SLURM executor, cgawad caps, Apptainer, x86, GHCR image registry
conf/deepvariant.config       CPU-only DeepVariant (cgawad has no GPUs)
conf/containers_dnaqc.config  optional explicit image map (pull ECR-hosted images directly)
bin/run_bj.sh                 one driver for every pipeline (inline or sbatch orchestrator)
bin/setup_sherlock.sh         checkout upstream at the pinned commit, fetch Nextflow, check prerequisites
bin/build_bwamem2_index.sbatch  one-time BWA-MEM2 index for the open-source aligner
.github/workflows/mirror-images.yml  publishes the 20 basejumper_* images to GHCR
docs/MIGRATION.md             what the old Sherlock patch did, what carries over, what to retire
```

On Sherlock the intended home is `/oak/stanford/groups/cgawad/Scripts/Basejumper/v2/`
(the previous setup stays untouched beside it).

## Quick start

```bash
# 1. clone the layer and check out upstream next to it
git clone https://github.com/GAWAD-LAB-STANFORD/basejumper-sherlock /oak/stanford/groups/cgawad/Scripts/Basejumper/v2
bash /oak/stanford/groups/cgawad/Scripts/Basejumper/v2/bin/setup_sherlock.sh

# 2. container images: run the "Mirror BaseJumper container images to GHCR" workflow once
#    (GitHub -> Actions). Packages must be public for anonymous Apptainer pulls.

# 3. BWA-MEM2 index (one time, ~90 GB RAM, 1-2 h)
sbatch /oak/stanford/groups/cgawad/Scripts/Basejumper/v2/bin/build_bwamem2_index.sbatch

# 4. run
/oak/stanford/groups/cgawad/Scripts/Basejumper/v2/bin/run_bj.sh \
    --pipeline dnaqc --input samples.csv --outdir /oak/stanford/groups/cgawad/results/dnaqc_run1 --submit

# resume a run: same --workflow-id as the original, plus --resume
```

Input CSV (Illumina): `biosampleName,read1,read2` — multi-lane files joined with `|`.
Ultima CRAM: `biosampleName,cram`. See each pipeline's upstream README for options.

## How the Sherlock layer works

- `process.executor = 'slurm'`, `queue = 'cgawad'`, orchestrator submitted with `sbatch --wrap`.
- Per-process ceiling **20 CPU / 350 GB / 72 h** set explicitly via `resourceLimits`
  (environment.config evaluates `params.max_*` at load time, so params alone don't cap it).
- `architecture = "x86"` (upstream default is `arm`) and `BWAMEM2_BIN=bwa-mem2.avx2` (avoids the
  AVX-512 dispatch failure upstream CI also guards against).
- Images: upstream names its custom images `basejumper_<tag>` with no registry.
  `singularity.registry = 'ghcr.io/gawad-lab-stanford'` makes Nextflow pull them from the lab's
  mirror; 13 are unmodified pull-throughs of BioSkryb's public ECR, 7 are built from their
  Dockerfiles. `quay.io/...` and `docker.io/...` names are untouched.
- Work dir defaults to `$GROUP_SCRATCH/nextflow_work/<workflow-id>` (fast, purged);
  image cache and tmp stay on OAK as before.
- Failures retry twice, then the run **fails at the end** (`finish`) rather than upstream's
  `ignore`, which silently drops samples from the report.

## Validation checklist

Run `bin/setup_sherlock.sh`; it reports most of these.

- [ ] `apptainer`/`singularity` available on compute nodes (module name if any)
- [ ] Java 17–24 module name (`ml spider java`) — adjust `run_bj.sh` if not `java/17.0.4`
- [ ] `/scratch/groups/cgawad` exists and has quota for work dirs
- [ ] reference bundle has `GATK_bundle/Sequence/genome.fa`, `Intervals/wgs_intervals.bed`,
      `wgs_coverage_regions.interval_list`, Ginkgo refs for your `bin_size` × `read_length`
      (upstream default `read_length` is now 50; pass `--extra "--read_length 150"` for 150-bp data)
- [ ] `Sequence_bwamem2/` built
- [ ] GHCR packages public (or `conf/containers_dnaqc.config` used for ECR-hosted images)
- [ ] smoke test: 2 cells, `--extra "--n_reads 500000"`, check `workflow_outputs/<workspace>/<id>/reports/multiqc_report.html`

## Updating upstream

Bump `UPSTREAM_REF` in `bin/setup_sherlock.sh` and the workflow's default input, re-run the
mirror workflow (image tags can change between releases), then `bin/setup_sherlock.sh`.
