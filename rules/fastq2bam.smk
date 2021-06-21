localrules: collect_sumstats
import os

rule get_fastq_pe:
    #should specify tmpdir probably
    output:
        "data/{Organism}/{sample}/{run}_1.fastq",
        "data/{Organism}/{sample}/{run}_2.fastq"
    params:
        outdir = "data/{Organism}/{sample}"
        
    conda:
        "../envs/fastq2bam.yml"
    shell:
        "fasterq-dump {wildcards.run} -O {params.outdir}"

rule gzip_fastq:
    input:
        "data/{Organism}/{sample}/{run}_1.fastq",
        "data/{Organism}/{sample}/{run}_2.fastq"
    output:
        "data/{Organism}/{sample}/{run}_1.fastq.gz",
        "data/{Organism}/{sample}/{run}_2.fastq.gz"
    shell:
        "gzip {input}"

rule download_reference:
    output:
        "data/{Organism}/genome/{refGenome}.fna.gz"
    params:
        link = lambda wildcards:
            helperFun.get_ref_link(wildcards.refGenome)
    log:
        "logs/{Organism}/dl_genome/{refGenome}.log"
    shell:
        "wget -O {output} -o {log} {params.link}"

rule index_ref:
    input:
        ref = "data/{Organism}/genome/{refGenome}.fna.gz"
    output: 
            expand("data/{{Organism}}/genome/{{refGenome}}.fna.gz.{ext}", ext=["sa", "pac", "bwt", "ann", "amb"])
    conda:
        "../envs/fastq2bam.yml"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['index_ref']['mem']
    log:
        "logs/{Organism}/index_ref/{refGenome}.log" 
    shell:
        "bwa index {input.ref} 2> {log}"

rule fastp:
    input:
        r1 = lambda wildcards:
            expand("data/{Organism}/{{sample}}/{run}_1.fastq.gz", Organism=sample_dict[wildcards.sample]["Organism"], run=sample_dict[wildcards.sample]["Run"]),
        r2 = lambda wildcards:
            expand("data/{Organism}/{{sample}}/{run}_2.fastq.gz", Organism=sample_dict[wildcards.sample]["Organism"], run=sample_dict[wildcards.sample]["Run"])
    output: 
        r1 = fastqFilterDir + "{sample}_fastp" + fastq_suffix1,
        r2 = fastqFilterDir + "{sample}_fastp" + fastq_suffix2,
        summ = sumstatDir + "{sample}_fastp.out"
    conda:
        "../envs/fastq2bam.yml"
    threads: res_config['fastp']['threads']
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['fastp']['mem'] 
    shell:
        "fastp --in1 {input.r1} --in2 {input.r2} "
        "--out1 {output.r1} --out2 {output.r2} "
        "--thread {threads} "
        "--detect_adapter_for_pe "
        "2> {output.summ}"

rule bwa_map:
    input:
        ref = lambda wildcards:
            expand("data/{Organism}/genome/{refGenome}.fna.gz", Organism=sample_dict[wildcards.sample]["Organism"], refGenome=sample_dict[wildcards.sample]["refGenome"]),
        r1 = fastqFilterDir + "{sample}_fastp" + fastq_suffix1,
        r2 = fastqFilterDir + "{sample}_fastp" + fastq_suffix2,
        # the following files are bwa index files that aren't directly input into command below, but needed
        sa = lambda wildcards:
            expand("data/{Organism}/genome/{refGenome}.fna.gz.sa", Organism=sample_dict[wildcards.sample]["Organism"], refGenome=sample_dict[wildcards.sample]["refGenome"]),
        pac = lambda wildcards:
            expand("data/{Organism}/genome/{refGenome}.fna.gz.pac", Organism=sample_dict[wildcards.sample]["Organism"], refGenome=sample_dict[wildcards.sample]["refGenome"]),
        bwt = lambda wildcards:
            expand("data/{Organism}/genome/{refGenome}.fna.gz.bwt", Organism=sample_dict[wildcards.sample]["Organism"], refGenome=sample_dict[wildcards.sample]["refGenome"]),
        ann = lambda wildcards:
            expand("data/{Organism}/genome/{refGenome}.fna.gz.ann", Organism=sample_dict[wildcards.sample]["Organism"], refGenome=sample_dict[wildcards.sample]["refGenome"]),
        amb = lambda wildcards:
            expand("data/{Organism}/genome/{refGenome}.fna.gz.amb", Organism=sample_dict[wildcards.sample]["Organism"], refGenome=sample_dict[wildcards.sample]["refGenome"])
    output: 
        bam = bamDir + "{sample}_sorted.bam",
        bai = bamDir + "{sample}_sorted.bai"
    params:
        lib_id = lambda wildcards: sample_dict[wildcards.sample]['LibraryName'],
        sample = "{sample}",
    conda:
        "../envs/fastq2bam.yml"
    threads: res_config['bwa_map']['threads']
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['bwa_map']['mem'] 
    shell:
        "bwa mem -M -t {threads} -R \'@RG\\tID:{params.lib_id}\\tSM:{params.sample}\\tPL:ILLUMINA\' {input.ref} {input.r1} {input.r2} | "
        "samtools sort -o {output.bam} -"

"""rule sort_bam:
    input: 
        bamDir + "{sample}.bam"
    output: 
        temp(bamDir + "{sample}_sorted.bam"),
        temp(bamDir + "{sample}_sorted.bai")
    conda:
        "../envs/fastq2bam.yml"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['sort_bam']['mem'] 
    shell:
        "picard SortSam I={input} O={output[0]} SORT_ORDER=coordinate CREATE_INDEX=true TMP_DIR={bamDir}"
"""

rule dedup:
    input: 
        bamDir + "{sample}_sorted.bam",
        bamDir + "{sample}_sorted.bai"
    output:
        dedupBam = bamDir + "{sample}_dedup.bam",
        dedupMet = sumstatDir + "{sample}_dedupMetrics.txt",
    conda:
        "../envs/fastq2bam.yml"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['dedup']['mem'] 
    shell:
        "picard MarkDuplicates I={input[0]} O={output.dedupBam} METRICS_FILE={output.dedupMet} REMOVE_DUPLICATES=false TAGGING_POLICY=All\n"
        "picard BuildBamIndex I={output.dedupBam} "

rule bam_sumstats:
    input: 
        bam = bamDir + "{sample}_dedup.bam",
        ref = lambda wildcards:
            expand("data/{Organism}/genome/{refGenome}.fna.gz", Organism=sample_dict[wildcards.sample]["Organism"], refGenome=sample_dict[wildcards.sample]["refGenome"])

    output: 
        cov = sumstatDir + "{sample}_coverage.txt",
        alnSum = sumstatDir + "{sample}_AlnSumMets.txt",
        val = sumstatDir + "{sample}_validate.txt"
    conda:
        "../envs/fastq2bam.yml"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['bam_sumstats']['mem'] 
    shell:
        "samtools coverage --output {output.cov} {input.bam}\n"
        "picard CollectAlignmentSummaryMetrics I={input.bam} R={input.ref} O={output.alnSum}\n"
        # The following ValidateSamFile exits with non-zero status when a BAM file contains errors, 
        # causing snakemake to exit and remove these output files.  I cirumvent this by appending "|| true".
        # I also ignore "INVALID_TAG_NM" because it isn't used by GATK but causes errors at this step
        "picard ValidateSamFile I={input.bam} R={input.ref} O={output.val} IGNORE=INVALID_TAG_NM || true"
		
rule collect_sumstats:
    input:
        fastpFiles = expand(sumstatDir + "{sample}_fastp.out", sample=SAMPLES),
        dedupFiles = expand(sumstatDir + "{sample}_dedupMetrics.txt", sample=SAMPLES),
        alnSumMetsFiles = expand(sumstatDir + "{sample}_AlnSumMets.txt", sample=SAMPLES),
        coverageFiles = expand(sumstatDir + "{sample}_coverage.txt", sample=SAMPLES),
        validateFiles = expand(sumstatDir + "{sample}_validate.txt", sample=SAMPLES)
    output:
         config["fastq2bamDir"] + "bam_sumstats.txt"
    run:
        FractionReadsPassFilter, NumFilteredReads = helperFun.collectFastpOutput(input.fastpFiles)
        PercentDuplicates = helperFun.collectDedupMetrics(input.dedupFiles)
        PercentHQreads, PercentHQbases = helperFun.collectAlnSumMets(input.alnSumMetsFiles)
        SeqDepths, CoveredBases = helperFun.collectCoverageMetrics(input.coverageFiles)
        validateSams = helperFun.collectValidationStatus(input.validateFiles)

        helperFun.printBamSumStats(FractionReadsPassFilter, NumFilteredReads, PercentDuplicates, PercentHQreads, PercentHQbases, SeqDepths, CoveredBases, validateSams, config["fastq2bamDir"])

