# nf-atlas-pipeline

Hello! This tool is designed to help you run the rnaseq pipeline locally.

## requirements

You need to have the following tools installed:

- Nextflow (make sure it is present in your PATH)
- Docker (optional)

## usage

### setup
> ./setup.sh

This will get the static files you'll need to run the pipeline, and the code for the pipeline itself.

### run a single sample
> ./rnaseq.sh --docker sample1_R1_001.fastq.gz sample1_R2_001.fastq.gz

This will run the pipeline with the given sample files. Note the --docker flag is optional. If you don't have docker installed, you can remove the flag and the pipeline will use nextflow in singularity mode. 
The code will produce 6 TSV files that will be packaged in a .tgz archive. This is perfect for uploading onto the prostatecanceratlas.org website. It will also keep the log folder, so you can make sure everything went well.

### run multiple samples (batch)

Organise your data so each sample lives in its own folder:

```
data/
  sample_A/
    sampleA_R1_001.fastq.gz
    sampleA_R2_001.fastq.gz
  sample_B/
    sampleB.fastq.gz
  ...
```

Then run:

> ./batch_rnaseq.sh --docker data/

Each subfolder that contains 1 or 2 `*.fastq.gz` / `*.fq.gz` files is treated as one sample. The script calls `rnaseq.sh` from within each sample folder, so every sample gets its own `run-<timestamp>/` directory (with `output.tgz` and logs) right next to its FASTQ files.

At the end a summary shows which samples succeeded, were skipped, or failed. If any sample fails the exit code is non-zero, but the remaining samples are still processed.

**Useful options**

| Flag | Effect |
|---|---|
| `--docker` | Use Docker (default: Singularity) |
| `--singularity` | Use Singularity explicitly |
| `--skip-done` | Skip any sample folder that already contains a `run-*/output.tgz` archive |

### config
rnaseq.config is the config file for the pipeline. It is used to set RAM and CPU available on your machine for this task. Change it to your taste, see what works for you.

May your pillow always be fresh!
