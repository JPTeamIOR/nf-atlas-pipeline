# nf-atlas-pipeline

Hello! This tool is designed to help you run the rnaseq pipeline locally.

## requirements

You need to have the following tools installed:

- Nextflow (make sure it is present in your PATH)
- Docker (optional)

## usage

./setup.sh

This will get the static files you'll need to run the pipeline, and the code for the pipeline itself.

./rnaseq.sh --docker sample1_R1_001.fastq.gz sample1_R2_001.fastq.gz

This will run the pipeline with the given sample files. Note the --docker flag is optional. If you don't have docker installed, you can remove the flag and the pipeline will use nextflow in singularity mode. 
The code will produce 6 csv files that will be packaged in a .tgz archive. This is perfect for uploading onto the prostatecanceratlas.org website. It will also keep the log folder, so you can make sure everything went well.

rnaseq.config is the config file for the pipeline. It is used to set RAM and CPU available on your machine for this task. Change it to your taste, see what works for you.

May your pillow always be fresh!
