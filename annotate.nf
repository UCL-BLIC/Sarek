#!/usr/bin/env nextflow

/*
kate: syntax groovy; space-indent on; indent-width 2;
================================================================================
=                                 S  A  R  E  K                                =
================================================================================
 New Germline (+ Somatic) Analysis Workflow. Started March 2016.
--------------------------------------------------------------------------------
 @Authors
 Sebastian DiLorenzo <sebastian.dilorenzo@bils.se> [@Sebastian-D]
 Jesper Eisfeldt <jesper.eisfeldt@scilifelab.se> [@J35P312]
 Phil Ewels <phil.ewels@scilifelab.se> [@ewels]
 Maxime Garcia <maxime.garcia@scilifelab.se> [@MaxUlysse]
 Szilveszter Juhos <szilveszter.juhos@scilifelab.se> [@szilvajuhos]
 Max Käller <max.kaller@scilifelab.se> [@gulfshores]
 Malin Larsson <malin.larsson@scilifelab.se> [@malinlarsson]
 Marcel Martin <marcel.martin@scilifelab.se> [@marcelm]
 Björn Nystedt <bjorn.nystedt@scilifelab.se> [@bjornnystedt]
 Pall Olason <pall.olason@scilifelab.se> [@pallolason]
 Pelin Sahlén <pelin.akan@scilifelab.se> [@pelinakan]
--------------------------------------------------------------------------------
 @Homepage
 http://opensource.scilifelab.se/projects/sarek/
--------------------------------------------------------------------------------
 @Documentation
 https://github.com/SciLifeLab/Sarek/README.md
--------------------------------------------------------------------------------
 Processes overview
 - RunBcftoolsStats - Run BCFTools stats on vcf before annotation
 - RunSnpeff - Run snpEff for annotation of vcf files
 - RunVEP - Run VEP for annotation of vcf files
================================================================================
=                           C O N F I G U R A T I O N                          =
================================================================================
*/

// Check that Nextflow version is up to date enough
// try / throw / catch works for NF versions < 0.25 when this was implemented
try {
    if( ! nextflow.version.matches(">= ${params.nfRequiredVersion}") ){
        throw GroovyException('Nextflow version too old')
    }
} catch (all) {
    log.error "====================================================\n" +
              "  Nextflow version ${params.nfRequiredVersion} required! You are running v${workflow.nextflow.version}.\n" +
              "  Pipeline execution will continue, but things may break.\n" +
              "  Please update Nextflow.\n" +
              "============================================================"
}

if (params.help) exit 0, helpMessage()
if (!SarekUtils.isAllowedParams(params)) exit 1, "params unknown, see --help for more information"
if (!checkUppmaxProject()) exit 1, "No UPPMAX project ID found! Use --project <UPPMAX Project ID>"

tools = params.tools ? params.tools.split(',').collect{it.trim().toLowerCase()} : []
annotateTools = params.annotateTools ? params.annotateTools.split(',').collect{it.trim().toLowerCase()} : []
annotateVCF = params.annotateVCF ? params.annotateVCF.split(',').collect{it.trim()} : []

directoryMap = SarekUtils.defineDirectoryMap(params.outDir)
toolList = defineToolList()

if (!SarekUtils.checkParameterList(tools,toolList)) exit 1, 'Unknown tool(s), see --help for more information'

/*
================================================================================
=                               P R O C E S S E S                              =
================================================================================
*/

startMessage()

vcfToAnnotate = Channel.create()
vcfNotToAnnotate = Channel.create()

if (annotateVCF == []) {
  Channel.empty().mix(
    Channel.fromPath("${directoryMap.haplotypecaller}/*.vcf.gz")
      .flatten().map{vcf -> ['none', 'haplotypecaller', vcf, null]},
    Channel.fromPath("${directoryMap.manta}/*SV.vcf.gz")
      .flatten().map{vcf -> ['none', 'manta', vcf, null]},
    Channel.fromPath("${directoryMap.mutect1}/*.vcf.gz")
      .flatten().map{vcf -> ['none', 'mutect1', vcf, null]},
    Channel.fromPath("${directoryMap.mutect2}/*.vcf.gz")
      .flatten().map{vcf -> ['none', 'mutect2', vcf, null]},
    Channel.fromPath("${directoryMap.strelka}/*{somatic,variants}*.vcf.gz")
      .flatten().map{vcf -> ['none', 'strelka', vcf, null]},
    Channel.fromPath("${directoryMap.strelkabp}/*{somatic,variants}*.vcf.gz")
      .flatten().map{vcf -> ['none', 'strelkabp', vcf, null]}
  ).choice(vcfToAnnotate, vcfNotToAnnotate) {
    annotateTools == [] || (annotateTools != [] && it[0] in annotateTools) ? 0 : 1
  }
} else if (annotateTools == []) {
  list = ""
  annotateVCF.each{ list += ",${it}" }
  list = list.substring(1)
  if (StringUtils.countMatches("${list}", ",") == 0) vcfToAnnotate = Channel.fromPath("${list}")
    .map{vcf -> ['none', 'userspecified', vcf, null]}
  else vcfToAnnotate = Channel.fromPath("{$list}")
    .map{vcf -> ['none', 'userspecified', vcf, null]}
} else exit 1, "specify only tools or files to annotate, not both"

vcfNotToAnnotate.close()

(vcfForBCFtools, vcfForVCFtools, vcfForSnpeff, vcfForVep) = vcfToAnnotate.into(4)

process RunBcftoolsStats {
  tag {vcf}

  publishDir directoryMap.bcftoolsStats, mode: 'link'

  input:
    set annotator, variantCaller, file(vcf), file(idx) from vcfForBCFtools

  output:
    file ("${vcf.baseName}.bcf.tools.stats.out") into bcfReport

  when: !params.noReports

  script: QC.bcftools(vcf)
}

if (params.verbose) bcfReport = bcfReport.view {
  "BCFTools stats report:\n" +
  "File  : [${it.fileName}]"
}

process RunVcftools {
  tag {vcf}

  publishDir directoryMap.vcftools, mode: 'link'

  input:
    set annotator, variantCaller, file(vcf), file(idx) from vcfForVCFtools

  output:
    file ("${vcf.baseName}.*") into vcfReport

  when: !params.noReports

  script: QC.vcftools(vcf)
}

if (params.verbose) vcfReport = vcfReport.view {
  "VCFTools stats report:\n" +
  "Files : [${it.fileName}]"
}

process RunSnpeff {
  tag {vcf}

  publishDir params.outDir, mode: 'link', saveAs: {
    if (it == "${vcf.baseName}.snpEff.csv") "${directoryMap.snpeffReports}/${it}"
    else if (it == "${vcf.baseName}.snpEff.ann.vcf") null
    else "${directoryMap.snpeff}/${it}"
  }

  input:
    set annotator, variantCaller, file(vcf), file(idx) from vcfForSnpeff
    val snpeffDb from Channel.value(params.genomes[params.genome].snpeffDb)

  output:
    set file("${vcf.baseName}.snpEff.genes.txt"), file("${vcf.baseName}.snpEff.csv"), file("${vcf.baseName}.snpEff.summary.html") into snpeffOutput
    set val("snpeff"), variantCaller, file("${vcf.baseName}.snpEff.ann.vcf") into snpeffVCF

  when: 'snpeff' in tools || 'merge' in tools

  script:
  """
  java -Xmx${task.memory.toGiga()}g \
  -jar \$SNPEFF_HOME/snpEff.jar \
  ${snpeffDb} \
  -csvStats ${vcf.baseName}.snpEff.csv \
  -nodownload \
  -canon \
  -v \
  ${vcf} \
  > ${vcf.baseName}.snpEff.ann.vcf

  mv snpEff_summary.html ${vcf.baseName}.snpEff.summary.html
  """
}

if (params.verbose) snpeffOutput = snpeffOutput.view {
  "snpEff report:\n" +
  "File  : ${it.fileName}"
}

if('merge' in tools) {
  // When running in the 'merge' mode
  // snpEff output is used as VEP input
  // vcfCompressed is in the mix, only if it came out of snpEff

  vcfCompressed = Channel.create()

  vcfForVep = Channel.empty().mix(
    vcfCompressed.until({it[0]!="snpeff"})
  )
}

process RunVEP {
  tag {vcf}

  publishDir params.outDir, mode: 'link', saveAs: {
    if (it == "${vcf.baseName}.vep.summary.html") "${directoryMap.vep}/${it}"
    else null
  }

  input:
    set annotator, variantCaller, file(vcf), file(idx) from vcfForVep

  output:
    set val("vep"), variantCaller, file("${vcf.baseName}.vep.ann.vcf") into vepVCF
    file("${vcf.baseName}.vep.summary.html") into vepReport

  when: 'vep' in tools || 'merge' in tools

  script:
  genome = params.genome == 'smallGRCh37' ? 'GRCh37' : params.genome
  """
  vep \
  -i ${vcf} \
  -o ${vcf.baseName}.vep.ann.vcf \
  --stats_file ${vcf.baseName}.vep.summary.html \
  --cache \
  --everything \
  --filter_common \
  --format vcf \
  --offline \
  --per_gene \
  --fork ${task.cpus} \
  --total_length \
  --vcf
  """
}

if (params.verbose) vepReport = vepReport.view {
  "VEP report:\n" +
  "Files : ${it.fileName}"
}

vcfToCompress = snpeffVCF.mix(vepVCF)

process CompressVCF {
  tag {"${annotator} - ${vcf}"}

  publishDir "${directoryMap."$annotator"}", mode: 'link'

  input:
    set annotator, variantCaller, file(vcf) from vcfToCompress

  output:
    set annotator, variantCaller, file("*.vcf.gz"), file("*.vcf.gz.tbi") into (vcfCompressed, vcfCompressedoutput)

  script:
  """
  bgzip < ${vcf} > ${vcf}.gz
  tabix ${vcf}.gz
  """
}

if (params.verbose) vcfCompressedoutput = vcfCompressedoutput.view {
  "${it[0]} VCF:\n" +
  "File  : ${it[2].fileName}\n" +
  "Index : ${it[3].fileName}"
}

process GetVersionBCFtools {
  publishDir directoryMap.version, mode: 'link'
  output: file("v_*.txt")
  when: !params.noReports
  script: QC.getVersionBCFtools()
}

process GetVersionSnpEFF {
  publishDir directoryMap.version, mode: 'link'
  output: file("v_*.txt")
  when: 'snpeff' in tools || 'merge' in tools
  script: QC.getVersionSnpEFF()
}

process GetVersionVCFtools {
  publishDir directoryMap.version, mode: 'link'
  output: file("v_*.txt")
  when: !params.noReports
  script: QC.getVersionVCFtools()
}

process GetVersionVEP {
  publishDir directoryMap.version, mode: 'link'
  output: file("v_*.txt")
  when: 'vep' in tools || 'merge' in tools
  script: QC.getVersionVEP()
}

/*
================================================================================
=                               F U N C T I O N S                              =
================================================================================
*/

def checkUppmaxProject() {
  // check if UPPMAX project number is specified
  return !(workflow.profile == 'slurm' && !params.project)
}

def defineToolList() {
  return [
    'merge',
    'snpeff',
    'vep'
  ]
}

def grabRevision() {
  // Return the same string executed from github or not
  return workflow.revision ?: workflow.commitId ?: workflow.scriptId.substring(0,10)
}

def helpMessage() {
  // Display help message
  this.sarekMessage()
  log.info "    Usage:"
  log.info "       nextflow run annotate.nf --test [--step STEP] [--tools TOOL[,TOOL]] --genome <Genome>"
  log.info "    --noReports"
  log.info "       Disable QC tools and MultiQC to generate a HTML report"
  log.info "    --tools"
  log.info "       Option to configure which tools to use in the workflow."
  log.info "         Different tools to be separated by commas."
  log.info "       Possible values are:"
  log.info "         snpeff (use snpEff for Annotation of Variants)"
  log.info "         vep (use VEP for Annotation of Variants)"
  log.info "         merge (first snpEff, then feed its output VCFs to VEP)"
  log.info "    --annotateTools"
  log.info "       Option to configure which tools to annotate."
  log.info "         Different tools to be separated by commas."
  log.info "       Possible values are:"
  log.info "         haplotypecaller (Annotate HaplotypeCaller output)"
  log.info "         manta (Annotate Manta output)"
  log.info "         mutect1 (Annotate MuTect1 output)"
  log.info "         mutect2 (Annotate MuTect2 output)"
  log.info "         strelka (Annotate Strelka output)"
  log.info "    --annotateVCF"
  log.info "       Option to configure which vcf to annotate."
  log.info "         Different vcf to be separated by commas."
  log.info "    --genome <Genome>"
  log.info "       Use a specific genome version."
  log.info "       Possible values are:"
  log.info "         GRCh37"
  log.info "         GRCh38 (Default)"
  log.info "         smallGRCh37 (Use a small reference (Tests only))"
  log.info "    --onlyQC"
  log.info "       Run only QC tools and gather reports"
  log.info "    --help"
  log.info "       you're reading it"
  log.info "    --verbose"
  log.info "       Adds more verbosity to workflow"
}

def minimalInformationMessage() {
  // Minimal information message
  log.info "Command Line: " + workflow.commandLine
  log.info "Profile     : " + workflow.profile
  log.info "Project Dir : " + workflow.projectDir
  log.info "Launch Dir  : " + workflow.launchDir
  log.info "Work Dir    : " + workflow.workDir
  log.info "Out Dir     : " + params.outDir
  log.info "Genome      : " + params.genome
  log.info "Genome_base : " + params.genome_base
  if (tools) log.info "Tools       : " + tools.join(', ')
  if (annotateTools) log.info "Annotate on : " + annotateTools.join(', ')
  if (annotateVCF) log.info "VCF files   : " +annotateVCF.join(',\n    ')
  log.info "Containers"
  if (params.repository != "") log.info "  Repository   : " + params.repository
  if (params.containerPath != "") log.info "  ContainerPath: " + params.containerPath
  log.info "  Tag          : " + params.tag
  log.info "Reference files used:"
  log.info "  snpeffDb    :\n\t" + params.genomes[params.genome].snpeffDb
}

def nextflowMessage() {
  // Nextflow message (version + build)
  log.info "N E X T F L O W  ~  version ${workflow.nextflow.version} ${workflow.nextflow.build}"
}

def sarekMessage() {
  // Display Sarek message
  log.info "Sarek - Workflow For Somatic And Germline Variations ~ ${params.version} - " + this.grabRevision() + (workflow.commitId ? " [${workflow.commitId}]" : "")
}

def startMessage() {
  // Display start message
  SarekUtils.sarek_ascii()
  this.sarekMessage()
  this.minimalInformationMessage()
}

workflow.onComplete {
  // Display complete message
  this.nextflowMessage()
  this.sarekMessage()
  this.minimalInformationMessage()
  log.info "Completed at: " + workflow.complete
  log.info "Duration    : " + workflow.duration
  log.info "Success     : " + workflow.success
  log.info "Exit status : " + workflow.exitStatus
  log.info "Error report: " + (workflow.errorReport ?: '-')
}

workflow.onError {
  // Display error message
  this.nextflowMessage()
  this.sarekMessage()
  log.info "Workflow execution stopped with the following message:"
  log.info "  " + workflow.errorMessage
}
