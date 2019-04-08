library(tidyverse)
library(stringi)
library(stringr)
library(grid)
library(gridExtra)
library(cowplot)
library(GenomicRanges)
library(StructuralVariantAnnotation)
library(BSgenome.Hsapiens.UCSC.hg19)
options(stringsAsFactors=FALSE)

basedir="~/../Dropbox (HMF Australia)/HMF Australia team folder/Structural Variant Analysis/colo829/"

# UCSC table export
hg19_gaps = with(read_tsv(paste0(basedir,"hg19_gap")),
                 GRanges(seqnames=str_replace(chrom, "chr", ""), ranges=IRanges(start=chromStart, end=chromEnd), type=type))
# http://hgdownload.cse.ucsc.edu/goldenPath/hg18/database/cytoBand.txt.gz
hg19_cytobands =  with(read_tsv(
  file=paste0(basedir, "cytoband.txt"),
  col_names=c("chr", "start", "end", "band", "type"),
  col_type= "ciicc"),
  GRanges(seqnames=chr, ranges=IRanges(start=start+1, end=end), band=band, type=type))
seqlevelsStyle(hg19_cytobands) = "NCBI"
hg19_centromeres = hg19_cytobands[hg19_cytobands$type == "acen"]

.lp_lookup_df = hg19_cytobands %>% as.data.frame() %>%
  group_by(seqnames) %>%
  summarise(len=max(end)) %>%
  ungroup() %>%
  mutate(chrint=as.integer(ifelse(seqnames == "X", 23, ifelse(seqnames == "Y", 24, as.character(seqnames))))) %>%
  arrange(chrint) %>%
  mutate(offset=cumsum(as.numeric(len))-len) %>%
  mutate(chr=as.character(seqnames))
.lp_lookup = .lp_lookup_df$offset
names(.lp_lookup) = .lp_lookup_df$chr
as_linear_pos = function(chr, x) { .lp_lookup[as.character(chr)] + x }

######
# Weaver load
# CHR BEGIN END ALLELE_1_CN ALLELE_2_CN
weaver_cn = with(read_tsv(
  file=paste0(basedir, "weaver/REGION_CN_PHASE"),
  col_names=c("chr", "start", "end", "cn1", "cn2"),
  col_type= "ciinn"),
  GRanges(seqnames=chr, ranges=IRanges(start=start, end=end), cn1=cn1, cn2=cn2, caller="weaver"))
# CHR_1 POS_1 ORI_1 ALLELE_ CHR_2 POS_2 ORI_2 ALLELE_ CN germline/somatic_post_aneuploidy/somatic_pre_aneuploidy
weaver_bp = with(read_tsv(
  file=paste0(basedir, "weaver/SV_CN_PHASE"),
  col_names=c("chr1", "start1", "ori1", "allele1", "chr2", "start2", "ori2", "allele2", "cn1", "cn2", "cncn", "type"),
  col_type= "ciciciciiicc"), {
    bp_name = paste0("bp", seq_along(chr1))
    gro = GRanges(seqnames=chr1, ranges=IRanges(start=start1, width=1), strand=ori1, allele=allele1, cn=cn1, type=type, partner=paste0(bp_name, "h"), caller="weaver")
    grh = GRanges(seqnames=chr2, ranges=IRanges(start=start2, width=1), strand=ori2, allele=allele2, cn=cn2, type=type, partner=paste0(bp_name, "o"), caller="weaver")
    names(gro) = paste0(bp_name, "o")
    names(grh) = paste0(bp_name, "h")
    return(c(gro, grh))
  })

######
# GRIDSS/purple load
gridss_bp_gr = breakpointRanges(readVcf(paste0(basedir, "purple/COLO829T.purple.sv.ann.vcf")), nominalPosition=TRUE)
gridss_be_gr = breakendRanges(readVcf(paste0(basedir, "purple/COLO829T.purple.sv.ann.vcf")), nominalPosition=TRUE)
gridss_gr = c(gridss_bp_gr, gridss_be_gr)
gridss_gr = gridss_gr[!str_detect(names(gridss_gr), "purple")] # strip out placeholder purple breakends
gridss_gr$caller="purple"
purple_cn = with(read_tsv(paste0(basedir, "purple/COLO829T.purple.cnv")) %>% rename("#chromosome"="chromosome"),
  GRanges(seqnames=chromosome, ranges=IRanges(start=start, end=end),
          cn=copyNumber,
          bafCount=bafCount,
          observedBAF=observedBAF,
          segmentStartSupport=segmentStartSupport,
          segmentEndSupport=segmentEndSupport,
          method=method,
          depthWindowCount=depthWindowCount,
          gcContent=gcContent,
          minStart=minStart,
          maxStart=maxStart,
          caller="purple"))
purple_germline_cn = with(read_tsv(paste0(basedir, "purple/COLO829T.purple.germline.cnv")) %>% rename("#chromosome"="chromosome"),
  GRanges(seqnames=chromosome, ranges=IRanges(start=start, end=end),
    cn=copyNumber,
    bafCount=bafCount,
    observedBAF=observedBAF,
    segmentStartSupport=segmentStartSupport,
    segmentEndSupport=segmentEndSupport,
    method=method,
    depthWindowCount=depthWindowCount,
    gcContent=gcContent,
    minStart=minStart,
    maxStart=maxStart,
    caller="purple"))

######
# Conserting/CREST load
conserting_qual_merge = read_tsv(paste0(basedir, "conserting/colo829_CONSERTING_Mapability_100.txt.QualityMerge"))
conserting_cna_calls = read_tsv(paste0(basedir, "conserting/colo829_CONSERTING_Mapability_100.txt.CNAcalls"))
conserting_conflict = read_tsv(paste0(basedir, "conserting/colo829_CONSERTING_Mapability_100_potential_conflict_segment.txt"))
conserting_crest = read_tsv(paste0(basedir, "conserting/colo829_CREST-map_final_report.txt.QualityMerge"),
  col_names=c("chr1", "pos1", "ori1", "score1", "chr2", "pos2", "ori2", "score2"),
  col_type= "cicicici")
conserting_chr_to_xy = function(chr) { ifelse(chr == 23, "X", ifelse(chr == 24, "Y", chr)) }
conserting_cna = with(conserting_cna_calls, GRanges(
  seqnames=conserting_chr_to_xy(chrom),
  ranges=IRanges(start=loc.start, end=loc.end),
  num.mark=num.mark,
  Log2Ratio=Log2Ratio,
  caller="conserting"))
conserting_cn = with(conserting_qual_merge, GRanges(
  seqnames=conserting_chr_to_xy(chrom),
  ranges=IRanges(start=loc.start, end=loc.end),
  num.mark=num.mark,
  length.ratio=length.ratio,
  seg.mean=seg.mean,
  GMean=GMean,
  DMean=DMean,
  LogRatio=LogRatio,
  QualityScore=QualityScore,
  SV_Matched=SV_Matched,
  caller="conserting"))
crest_bp = with(conserting_crest, {
    bp_name = paste0("bp", seq_along(chr1))
    gro = GRanges(seqnames=conserting_chr_to_xy(chr1), ranges=IRanges(start=pos1, width=1), strand=ori1, score=score1, partner=paste0(bp_name, "h"), caller="conserting")
    grh = GRanges(seqnames=conserting_chr_to_xy(chr2), ranges=IRanges(start=pos2, width=1), strand=ori2, score=score2, partner=paste0(bp_name, "o"), caller="conserting")
    names(gro) = paste0(bp_name, "o")
    names(grh) = paste0(bp_name, "h")
    return(c(gro, grh))
  })
######
# Ascat
ascat_cn = with(read_tsv(paste0(basedir, "ascat/COLO829T.segments.txt")),
  GRanges(seqnames=chr, ranges=IRanges(start=startpos, end=endpos), nMajor=nMajor, nMinor=nMinor, caller="ascat"))


# Consistency with SV calls:
# segments
# segments supported by SV
# distance to SV
evaluate_cn_transitions = function (cngr, svgr, margin=100000, distance=c("cn_transition", "sv")) {
  distance <- match.arg(distance)
  cn_transitions = with(cngr %>% as.data.frame(), reduce(c(
    GRanges(seqnames=seqnames, ranges=IRanges(start=start, width=1)),
    GRanges(seqnames=seqnames, ranges=IRanges(start=end + 1, width=1)))))
  cn_transitions$distance = NA
  cn_transitions$caller = unique(cngr$caller)
  svgr$distance = NA
  hits = findOverlaps(svgr, cn_transitions, maxgap=margin, ignore.strand=TRUE) %>% as.data.frame() %>%
    mutate(distance=pmax(1, abs(start(svgr)[queryHits] - start(cn_transitions)[subjectHits])))
  #browser()
  best_sv_hit = hits %>% group_by(queryHits) %>% filter(distance==min(distance))
  best_cn_hit = hits %>% group_by(subjectHits) %>% filter(distance==min(distance))
  cn_transitions[best_cn_hit$subjectHits]$distance = best_cn_hit$distance
  svgr[best_sv_hit$queryHits]$distance = best_sv_hit$distance
  if (distance == "cn_transition") {
    return(cn_transitions)
  } else {
    return(svgr)
  }
}
cn_transistions = c(
  evaluate_cn_transitions(ascat_cn, gridss_gr),
  evaluate_cn_transitions(purple_cn, gridss_gr),
  evaluate_cn_transitions(conserting_cn, crest_bp),
  evaluate_cn_transitions(weaver_cn, weaver_bp)
)

cn_transistions$inGap = overlapsAny(cn_transistions, hg19_gaps, maxgap=100000)
cn_transistions$inCentromere = overlapsAny(cn_transistions, hg19_centromeres, maxgap=100000)
cn_transistions$isFirstOrLast = is.na(lead(as.character(seqnames(cn_transistions)))) |
  is.na(lag(as.character(seqnames(cn_transistions)))) |
  seqnames(cn_transistions) != lead(as.character(seqnames(cn_transistions))) |
  seqnames(cn_transistions) != lag(as.character(seqnames(cn_transistions)))

ascat_cn$cn = ascat_cn$nMajor + ascat_cn$nMinor
weaver_cn$cn = weaver_cn$cn1 + weaver_cn$cn2
conserting_cn$cn = 2 * (conserting_cn$DMean/conserting_cn$GMean)
cn = c(ascat_cn, purple_cn, conserting_cn, weaver_cn)

########
# Plots
c(ascat_cn, purple_cn, conserting_cn, weaver_cn) %>%
  as.data.frame() %>%
  dplyr::select(seqnames, start, end, caller) %>%
  mutate(length=end-start) %>%
ggplot() +
  aes(x=length) +
  geom_histogram() +
  scale_x_log10() +
  facet_grid(caller ~ ., scales="free_y") +
  labs(title="Copy number segment size distribution")

cn_transistions %>%
  as.data.frame() %>%
  replace_na(list(distance=100000)) %>%
  filter(!(inGap | isFirstOrLast | inCentromere)) %>%
ggplot() +
  aes(x=distance) +
  geom_histogram(bins=10) +
  scale_x_log10(breaks=c(1,10,100,1000, 10000, 100000), labels=c("0", "10", "100", "1000", "10000", "No matching SV")) +
  facet_grid(caller ~ ., scales="free_y") +
  labs(y="CN transitions", x="Distance to nearest SV")

# TODO replace with horizontal and vertical segments
# remove vertical segments when end + 1 != lead(start)
with(cn %>% as.data.frame() %>% mutate(chr=as.character(seqnames)), bind_rows(
    data.frame(caller=caller, chr=chr, pos=start, cn=cn),
    data.frame(caller=caller, chr=chr, pos=end, cn=cn))) %>%
  mutate(linearpos=as_linear_pos(chr, pos)) %>%
  arrange(caller, linearpos) %>%
ggplot() +
  geom_segment(aes(x=x, xend=xend, y=cn, yend=cn, colour=caller), data=cn %>%
    as.data.frame() %>%
    mutate(
      x=as_linear_pos(seqnames, start),
      xend=as_linear_pos(seqnames, end))) +
  geom_segment(aes(x=x, xend=xend, y=cn, yend=cn_next, colour=caller), data=cn %>%
                 as.data.frame() %>%
                 mutate(
                   x=as_linear_pos(seqnames, end) + 1,
                   xend=lead(as_linear_pos(seqnames, start)),
                   cn_next=lead(cn)) %>%
                 filter(x == xend & seqnames==lead(seqnames))) +
  geom_vline(aes(xintercept=pos), data=data.frame(pos=as_linear_pos(c(1:22, "X", "Y"), 0))) +
  geom_rect(aes(xmin=start, xmax=end, ymin=0, ymax=10), fill="gray", data=data.frame(
    start=as_linear_pos(seqnames(hg19_centromeres), start(hg19_centromeres)),
    end=as_linear_pos(seqnames(hg19_centromeres), end(hg19_centromeres)))) +
  coord_cartesian(ylim=c(0, 8)) +
  scale_x_continuous(breaks=with(.lp_lookup_df, offset+len/2), labels=c(1:22, "X", "Y")) +
  theme(axis.ticks.x=element_blank()) +
  facet_grid(caller ~ . ) +
  labs(x="", y="Copy Number")

