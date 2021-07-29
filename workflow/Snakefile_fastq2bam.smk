import os
import glob
import re
import yaml
from collections import defaultdict
import helperFun

configfile: "config.yaml"
res_config = yaml.load(open("resources.yaml"))

# rename variables from config file for clarity downstream
fastq_suffix1 = config["fastq_suffix1"]
fastq_suffix2 = config["fastq_suffix2"]

# this is where Snakemake output will go, specify with baseDir in config.yml
fastqFilterDir = config["fastq2bamDir"] + config["fastqFilterDir"]
bamDir = config["fastq2bamDir"] + config["bamDir"]
sumstatDir = config["fastq2bamDir"] + config["sumstatDir"]

# Get sample names from keys of dictionary
run_dict, sample_dict, sample_runs = helperFun.create_sample_dict(config["samples"])
print(sample_dict)
print(run_dict)
SAMPLES = sample_dict.keys()

###
# workflow with rules
###

rule all:
    input:
        config["fastq2bamDir"] + "bam_sumstats.txt"
	
include: "rules/fastq2bam.smk"
