library(tidyverse)
library(visNetwork)
library(igraph)
library(GenomicRanges)
library(RMySQL)
library(Biostrings)
library(StructuralVariantAnnotation)

CN_ROUNDING= 0.2
CN_DIFF_MARGIN = 0.25
CN_CHANGE_MIN = 0.8
DB_MAX_LENGTH = 1000
MIN_LOH_CN = 0.5

query_all_copy_numer = function(dbConnect, table="copyNumber") {
  query = paste(
    "SELECT * ",
    " FROM ", table,
    sep = "")
  return (DBI::dbGetQuery(dbConnect, query) %>%
    mutate(id=as.character(id)))
}
query_somatic_structuralVariants = function(dbConnect, table="structuralVariant") {
  query = paste(
    "SELECT * ",
    " FROM ", table,
    " WHERE filter = 'PASS'",
    sep = "")
  return (DBI::dbGetQuery(dbConnect, query) %>%
    mutate(id=as.character(id)))
}
to_cn_gr = function(df) {
  gr = with(df, GRanges(
    seqnames=chromosome,
    ranges=IRanges(
      start=start,
      end=end),
    strand="*",
    sampleId=sampleId,
    segmentStartSupport=segmentStartSupport,
    segmentEndSupport=segmentEndSupport,
    bafCount=bafCount,
    observedBaf=observedBaf,
    actualBaf=actualBaf,
    copyNumber=copyNumber,
    copyNumberMethod=copyNumberMethod
  ))
  names(gr) = df$id
  return(gr)
}
to_sv_gr <- function(svdf, include.homology=TRUE) {
  dbdf = svdf
  grs = GRanges(
    seqnames=dbdf$startChromosome,
    ranges=IRanges(start=dbdf$startPosition + ifelse(include.homology, ifelse(is.na(dbdf$startIntervalOffsetStart), 0, dbdf$startIntervalOffsetStart), 0),
                   end=dbdf$startPosition + ifelse(include.homology, ifelse(is.na(dbdf$startIntervalOffsetEnd), 0, dbdf$startIntervalOffsetEnd), 0)),
    strand=ifelse(dbdf$startOrientation == 1, "+", "-"),
    QUAL=dbdf$qualScore,
    FILTER=dbdf$filter,
    sampleId=dbdf$sampleId,
    ploidy=dbdf$ploidy,
    insertSequence=dbdf$insertSequence,
    type=dbdf$type,
    af=dbdf$startAF,
    homseq=dbdf$startHomologySequence,
    adjustedaf=dbdf$adjustedStartAF,
    adjustedcn=dbdf$adjustedStartCopyNumber,
    adjustedcn_delta=dbdf$adjustedStartCopyNumberChange,
    partner=ifelse(is.na(dbdf$endChromosome), NA_character_, paste0(dbdf$id, "h")),
    tumourVariantFragmentCount=dbdf$startTumorVariantFragmentCount,
    tumourReferenceFragmentCount=dbdf$startTumorReferenceFragmentCount,
    normalVariantFragmentCount=dbdf$startNormalVariantFragmentCount,
    normalReferenceFragmentCount=dbdf$startNormalReferenceFragmentCount,
    ihomlen=dbdf$inexactHomologyOffsetEnd-dbdf$inexactHomologyOffsetStart,
    imprecise=dbdf$imprecise != 0,
    event=dbdf$event,
    id=dbdf$id,
    vcfId=dbdf$vcfId,
    beid=paste0(dbdf$id, ifelse(is.na(dbdf$endChromosome), "b",  "o")),
    linkedBy=dbdf$startLinkedBy)
  names(grs)=grs$beid
  dbdf = dbdf %>% filter(!is.na(endChromosome))
  rc_insert_sequence = dbdf$insertSequence
  rc_insert_sequence[!str_detect(rc_insert_sequence, "[^ACGTN]")] = as.character(reverseComplement(DNAStringSet(rc_insert_sequence[!str_detect(rc_insert_sequence, "[^ACGTN]")])))
  grh = GRanges(
    seqnames=dbdf$endChromosome,
    ranges=IRanges(start=dbdf$endPosition + ifelse(include.homology, ifelse(is.na(dbdf$endIntervalOffsetStart), 0, dbdf$endIntervalOffsetStart), 0),
                   end=dbdf$endPosition + ifelse(include.homology, ifelse(is.na(dbdf$endIntervalOffsetEnd), 0, dbdf$endIntervalOffsetEnd), 0)),
    strand=ifelse(dbdf$endOrientation == 1, "+", "-"),
    QUAL=dbdf$qualScore,
    FILTER=dbdf$filter,
    sampleId=dbdf$sampleId,
    ploidy=dbdf$ploidy,
    insertSequence=ifelse(dbdf$startOrientation != dbdf$endOrientation, dbdf$insertSequence, rc_insert_sequence),
    type=dbdf$type,
    af=dbdf$endAF,
    homseq=dbdf$endHomologySequence,
    adjustedaf=dbdf$adjustedEndAF,
    adjustedcn=dbdf$adjustedEndCopyNumber,
    adjustedcn_delta=dbdf$adjustedEndCopyNumberChange,
    partner=paste0(dbdf$id, "o"),
    tumourVariantFragmentCount=dbdf$endTumorVariantFragmentCount,
    tumourReferenceFragmentCount=dbdf$endTumorReferenceFragmentCount,
    normalVariantFragmentCount=dbdf$endNormalVariantFragmentCount,
    normalReferenceFragmentCount=dbdf$endNormalReferenceFragmentCount,
    ihomlen=dbdf$inexactHomologyOffsetEnd-dbdf$inexactHomologyOffsetStart,
    imprecise=dbdf$imprecise != 0,
    event=dbdf$event,
    id=dbdf$id,
    vcfId=stringr::str_replace(dbdf$vcfId, "o", "h"),
    beid=paste0(dbdf$id, "h"),
    linkedBy=dbdf$endLinkedBy)
  names(grh)=grh$beid
  return(c(grs, grh))
}
annotate_sv_with_cnv_id = function(cnv_gr, sv_gr, ...) {
  shits = as.data.frame(findOverlaps(query=sv_gr, subject=cnv_gr, type="start", select="all", ignore.strand=TRUE, ...)) %>%
    filter(sv_gr$sampleId[queryHits] == cnv_gr$sampleId[subjectHits] &
             as.logical(strand(sv_gr[queryHits]) == "-")) %>%
    mutate(
      distance=abs((start(sv_gr[queryHits]) + end(sv_gr[queryHits])) / 2 - start(cnv_gr[subjectHits])),
      qual=sv_gr$QUAL[queryHits]) %>%
    # match the closest SV
    group_by(queryHits) %>%
    arrange(distance, -qual) %>%
    filter(row_number() == 1) %>%
    # only match the best hit
    #group_by(subjectHits) %>%
    #top_n(1, qual) %>%
    #filter(row_number() == 1) %>%
    ungroup()
  ehits = as.data.frame(findOverlaps(query=sv_gr, subject=cnv_gr, type="end", select="all", ignore.strand=TRUE, ...)) %>%
    filter(sv_gr$sampleId[queryHits] == cnv_gr$sampleId[subjectHits] &
             as.logical(strand(sv_gr[queryHits]) == "+")) %>%
    mutate(
      distance=abs((start(sv_gr[queryHits]) + end(sv_gr[queryHits])) / 2 - end(cnv_gr[subjectHits])),
      qual=sv_gr$QUAL[queryHits]) %>%
    group_by(queryHits) %>%
    arrange(distance, -qual) %>%
    filter(row_number() == 1) %>%
    #group_by(subjectHits) %>%
    #top_n(1, qual) %>%
    #filter(row_number() == 1) %>%
    ungroup()
  sv_gr$cnv_id = NA_character_
  sv_gr$cnv_id[shits$queryHits] = names(cnv_gr)[shits$subjectHits]
  sv_gr$cnv_id[ehits$queryHits] = names(cnv_gr)[ehits$subjectHits]
  return(sv_gr$cnv_id)
}
induced_edge_gr = function (cnv_gr, ...) {
  start_cnv_gr = cnv_gr
  start(start_cnv_gr) = start(start_cnv_gr) - 1
  width(start_cnv_gr) = 1
  hits = findOverlaps(cnv_gr, start_cnv_gr)
  induced_gr_left = GRanges(
    seqnames=seqnames(cnv_gr[queryHits(hits)]),
    ranges=IRanges(start=end(cnv_gr[queryHits(hits)]), width = 1),
    strand="+",
    id=paste0("ref", names(cnv_gr[queryHits(hits)])))
  names(induced_gr_left) = paste0("end_", names(cnv_gr[queryHits(hits)]))
  induced_gr_left$cnv_id = names(cnv_gr[queryHits(hits)])
  induced_gr_right = GRanges(
    seqnames=seqnames(cnv_gr[queryHits(hits)]),
    ranges=IRanges(start=end(cnv_gr[queryHits(hits)])+1, width = 1),
    strand="-",
    id=paste0("ref", names(cnv_gr[queryHits(hits)])))
  names(induced_gr_right) = paste0("start_", names(start_cnv_gr[subjectHits(hits)]))
  induced_gr_right$cnv_id = names(start_cnv_gr[subjectHits(hits)])
  induced_gr_left$partner = names(induced_gr_right)
  induced_gr_right$partner = names(induced_gr_left)
  return( c(induced_gr_left, induced_gr_right))
}

gridss_sv_links = function(svdf, svgr) {
  bind_rows(
    # gridss links
    svgr %>% as.data.frame() %>%
      dplyr::select(sampleId, id, beid, linkedBy) %>%
      filter(!is.na(linkedBy) & linkedBy != "." & linkedBy != "") %>%
      dplyr::mutate(linkedBy = str_split(as.character(linkedBy), stringr::fixed(","))) %>%
      tidyr::unnest(linkedBy) %>%
      group_by(sampleId, linkedBy) %>%
      filter(n() == 2) %>%
      arrange(beid) %>%
      summarise(
        id1=paste0(ifelse(row_number() == 1, id, ""), collapse=""),
        id2=paste0(ifelse(row_number() == 2, id, ""), collapse=""),
        beid1=paste0(ifelse(row_number() == 1, beid, ""), collapse=""),
        beid2=paste0(ifelse(row_number() == 2, beid, ""), collapse="")),
    # breakpoint partner links
    svdf %>%
      filter(!is.na(endChromosome)) %>%
      mutate(
        linkedBy=paste0("partner", id),
        id1=id,
        id2=id,
        beid1=paste0(id, "o"),
        beid2=paste0(id, "h")) %>%
      dplyr::select(sampleId, linkedBy, id1, id2, beid1, beid2)) %>%
    ungroup()
}

cluster_links = function(svdf, linked_breakends) {
  linkdf = linked_breakends %>% ungroup() %>% dplyr::select(id1, id2)
  cluster_id = 1:nrow(svdf)
  names(cluster_id) = svdf$id
  last_cluster_id = -1
  while (any(cluster_id != last_cluster_id)) {
    last_cluster_id = cluster_id
    # update cluster_id
    linkdf = linkdf %>%
      mutate(
        cid1 = cluster_id[id1],
        cid2 = cluster_id[id2],
        cid=pmin(cluster_id[id1], cluster_id[id2]))
    update_ids = bind_rows(
        linkdf %>% filter(cid1 > cid) %>% dplyr::select(id=id1, cid),
        linkdf %>% filter(cid2 > cid) %>% dplyr::select(id=id2, cid)) %>%
      group_by(id) %>%
      mutate(cid=min(cid))
    cluster_id[update_ids$id] = update_ids$cid
  }
  return(cluster_id)
}


find_cn_loh_links = function(cndf) {
  loh_bounds_df = cndf %>% group_by(sampleId, chromosome) %>%
    arrange(sampleId, chromosome, start) %>%
    # Q: why no min bafCount on the LOH segment in svanalyser?
    filter(bafCount > 0) %>%
    mutate(
      minorCN = (1 - actualBaf) * copyNumber,
      is_loh = minorCN < MIN_LOH_CN,
      is_loh_start_flank = !is_loh & lead(is_loh) & !is.na(lead(is_loh)),
      is_loh_end_flank = !is_loh & lag(is_loh) & !is.na(lag(is_loh))) %>%
    # just the bounding non-LOH segments - these should have the SV breakpoints
    filter(is_loh_start_flank | is_loh_end_flank) %>%
    # Remove start/end indicator if we don't pair up
    # this happens when a LOH continues to the  start/end of the chromosome
    mutate(
      is_loh_start_flank=is_loh_start_flank & lead(is_loh_end_flank) & !is.na(lead(is_loh_end_flank)),
      is_loh_end_flank=is_loh_end_flank & lag(is_loh_start_flank) & !is.na(lag(is_loh_start_flank)))
  loh_cn_pair_df = data.frame(
      cnid_start_flank = loh_bounds_df %>% filter(is_loh_start_flank) %>% pull(id) %>% as.character(),
      cnid_end_flank = loh_bounds_df %>% filter(is_loh_end_flank) %>% pull(id)  %>% as.character(),
      stringsAsFactors=TRUE) %>%
    mutate(linked_by=paste0("loh", row_number()))
  return(loh_cn_pair_df)
}
find_sv_loh_links = function(cndf, cngr, svgr, maxgap=1000, ...) {
  loh_cn_pair_df = find_cn_loh_links(cndf) %>%
    mutate(
      beid_start_flank = find_closest_sv_to_segment(cnid_start_flank, cngr, svgr, "end", maxgap=maxgap, ...),
      beid_end_flank = find_closest_sv_to_segment(cnid_end_flank, cngr, svgr, "start", maxgap=maxgap, ...)) %>%
    filter(is.na(beid_start_flank) | is.na(beid_end_flank) |
             # ifelse is just a placeholder so we don't index by NA
             svgr[ifelse(is.na(beid_start_flank), names(svgr)[1], beid_start_flank)]$partner !=
             names(svgr[ifelse(is.na(beid_end_flank), names(svgr)[1], beid_end_flank)]))
  return(loh_cn_pair_df)
}
find_closest_sv_to_segment = function(cnid, cngr, svgr, position, ...) {
  result = rep(NA, length(cnid))
  cngr = cngr[as.character(cnid)]
  expected_sv_strand = ifelse(position=="start", "-", "+")
  hits = findOverlaps(query=cngr, subject=svgr, type=position, select="all", ignore.strand=TRUE, ...) %>%
    as.data.frame() %>%
    filter(as.logical(strand(svgr)[subjectHits] == expected_sv_strand)) %>%
    mutate(
      distance=abs((start(svgr[subjectHits]) + end(svgr[subjectHits])) / 2 - ifelse(position=="start", start(cngr[queryHits]), end(cngr[queryHits]))),
      QUAL=svgr$QUAL[subjectHits]) %>%
    group_by(queryHits) %>%
    arrange(distance, -QUAL) %>%
    filter(row_number() == 1)
  result[hits$queryHits] = svgr$beid[hits$subjectHits]
  return(result)
}
loh_sv_links = function(cndf, svdf) {
  cndf = cndf %>%
    group_by(sampleId, chromosome) %>%
    arrange(start) %>%
    mutate(
      is_loh_start_flank = lead(is_loh_start),
      start_loh_id = lead(loh_id),
      is_loh_end_flank = lag(is_loh_end),
      end_loh_id = lag(loh_id))

  start_sv = cndf %>%
    filter(is_loh_start_flank) %>%
    inner_join(svdf %>%
      filter(strand=="+") %>%
      dplyr::select(sampleId, id, cnid, strand),
      by=c("id"="cnid", "sampleId"="sampleId"),
      suffix=c("", ".sv")) %>%
    mutate(bound="start_sv_id")

    bind_rows(cndf %>% dplyr::select(sampleId, id, loh_id, is_loh_end) %>%
      filter(is_loh_end) %>%
      inner_join(svdf %>% dplyr::select(sampleId, id, cnid, strand) %>% filter(strand=="+"), by=c("id"="cnid", "sampleId"="sampleId"), suffix=c("", ".sv")) %>%
      mutate(bound="end_sv_id")) %>%
    dplyr::select(sampleId, loh_id, sv_id=id.sv, bound) %>%
    group_by(sampleId, loh_id, bound) %>%
    spread(bound, sv_id)
}

hg19_centromeres = function() {
  GRanges(
    seqnames=c(1:22, "X", "Y"),
    ranges=IRanges(start=c(121535434, 92326171, 90504854, 49660117, 46405641, 58830166, 58054331, 43838887, 47367679, 39254935,
                           51644205, 34856694, 16000000, 16000000, 17000000, 35335801, 22263006, 15460898, 24681782, 26369569, 11288129, 13000000, 58632012, 10104553),
                   end=c(124535434, 95326171, 93504854, 52660117, 49405641, 61830166, 61054331, 46838887, 50367679, 42254935,
                         54644205, 37856694, 19000000, 19000000, 20000000, 38335801, 25263006, 18460898, 27681782, 29369569, 14288129, 16000000, 61632012, 13104553)))
}
hg19_primary_seqinfo = function() {
  require(R.cache)
  seqinfo = addMemoization(SeqinfoForUCSCGenome)("hg19")
  seqlevelsStyle(seqinfo) = "NCBI"
  seqinfo = seqinfo[c(1:22, "X", "Y")]
  return(seqinfo)
}
hg19_arms = function() {
  centomeres = hg19_centromeres()
  parm = GRanges(seqnames=seqnames(centomeres), IRanges(start=1, end=start(centomeres) - 1))
  qarm = GRanges(seqnames=seqnames(centomeres), IRanges(start=end(centomeres) + 1, end=seqlengths(hg19_primary_seqinfo())))
  centomeres$arm = paste0(seqnames(centomeres), "C")
  parm$arm = paste0(seqnames(parm), "P") # short arm, and lower position
  qarm$arm = paste0(seqnames(qarm), "Q")
  return(c(parm, qarm, centomeres))
}
on_hg19_arm = function(gr) {
  hg19_arms()$arm[findOverlaps(gr, hg19_arms(), select="first", ignore.strand=TRUE)]
}

cluster_consistency = function(svgr) {
  svgr$arm = on_hg19_arm(svgr)
  svgr %>% as.data.frame() %>%
    mutate(towardsCentromere = (str_detect(arm, "P") & strand == "+") | (str_detect(arm, "Q") & strand == "-")) %>%
    group_by(sampleId, cluster, arm) %>%
    # overall cluster info
    mutate(cluster_calls=length(unique(id)),
           cluster_breakend_call=sum(str_detect(beid, "b"))) %>%
    group_by(sampleId, cluster, arm, cluster_calls, cluster_breakend_call) %>%
    # arm-level consistency
    summarise(
      toward_centromere_count=sum(towardsCentromere),
      toward_telomere_count=n() - toward_centromere_count,
      toward_centromere_ploidy=sum(towardsCentromere * ploidy),
      toward_telomere_ploidy=sum(ploidy) - toward_centromere_ploidy)
}
load_line_elements = function(file) {
  linedf = readr::read_csv(file)
  linegr = with(linedf, GRanges(
    seqnames=Chromosome,
    ranges=IRanges(start=PosStart, end=PosEnd),
    type=Type))
}
load_fragile_sites = function(file) {
  df = readr::read_csv(file)
  with(df, GRanges(
    seqnames=Chromosome,
    ranges=IRanges(start=PosStart, end=PosEnd),
    type=Type,
    gene_name=GeneName,
    cfs_name=CFSName))
}
svids_of_overlap = function(gr, annotation_gr, maxgap=1, ignore.strand=TRUE) {
  unique(gr$id[overlapsAny(gr, annotation_gr, maxgap=maxgap, ignore.strand=ignore.strand)])
}

find_simple_events = function(cndf, svdf, svgr) {

}
add_prev_next_cnid = function(cndf) {
  cndf %>%
    group_by(sampleId, chromosome) %>%
    arrange(start) %>%
    mutate(
      next_cnid = lead(id),
      prev_cnid = lag(id)) %>%
    ungroup()
}
#    ------ CN1 -> CN3
#   /      \
# CN1  CN2  CN3
find_simple_deletions = function(cndf, svdf, svgr) {
  cndf = add_prev_next_cnid(cndf) %>% as.data.frame()
  svdf = svdf %>% as.data.frame()
  row.names(cndf) = cndf$id
  row.names(svdf) = svdf$id
  bpgr = with(mcols(svgr), svgr[!is.na(partner)])
  dels = bpgr[strand(bpgr) == "+" & strand(partner(bpgr)) == "-" &
      cndf[bpgr$cnid,]$next_cnid == cndf[partner(bpgr)$cnid,]$prev_cnid]
  data.frame(
      simple_event_type="DEL",
      svid=dels$id,
      left_flank_cnid=dels$cnid,
      cnid=cndf[dels$cnid,]$next_cnid,
      right_flank_cnid=partner(bpgr)[dels$partner]$cnid,
      stringsAsFactors=FALSE) %>%
    mutate(
      left_flank_ploidy=cndf[left_flank_cnid,]$copyNumber,
      right_flank_ploidy=cndf[right_flank_cnid,]$copyNumber,
      ploidy=cndf[cnid,]$copyNumber,
      svploidy=svdf[svid,]$ploidy) %>%
    mutate(
      flanking_ploidy_delta=left_flank_ploidy-right_flank_ploidy,
      ploidy_inconsistency_delta=(left_flank_ploidy + right_flank_ploidy) / 2 - svploidy - ploidy)
}
#    ------ CN2 -> CN2
#    \    /
# CN1  CN2  CN3
find_simple_duplications = function(cndf, svdf, svgr) {
  cndf = add_prev_next_cnid(cndf) %>% as.data.frame()
  svdf = svdf %>% as.data.frame()
  row.names(cndf) = cndf$id
  row.names(svdf) = svdf$id
  bpgr = with(mcols(svgr), svgr[!is.na(partner)])
  dups = bpgr[strand(bpgr) == "-" & strand(partner(bpgr)) == "+" & bpgr$cnid == partner(bpgr)$cnid]
  data.frame(
    simple_event_type="DUP",
    svid=dups$id,
    cnid=dups$cnid,
    left_flank_cnid=cndf[dups$cnid,]$prev_cnid,
    right_flank_cnid=cndf[dups$cnid,]$next_cnid,
    stringsAsFactors=FALSE) %>%
    mutate(
      left_flank_ploidy=cndf[left_flank_cnid,]$copyNumber,
      right_flank_ploidy=cndf[right_flank_cnid,]$copyNumber,
      ploidy=cndf[cnid,]$copyNumber,
      svploidy=svdf[svid,]$ploidy) %>%
    mutate(
      flanking_ploidy_delta=left_flank_ploidy-right_flank_ploidy,
      ploidy_inconsistency_delta=(left_flank_ploidy + right_flank_ploidy) / 2 + svploidy - ploidy)
}
#    a    b     c   d
#    -----------------
#    |    |     |    |
# CN1  CN2  CN3  CN4  CN5   (CN2 and CN4 can be 0bp in size)
find_simple_inversions = function(cndf, svdf, svgr, max.breakend.gap=35) {
  cndf = add_prev_next_cnid(cndf) %>% as.data.frame()
  svdf = svdf %>% as.data.frame()
  row.names(cndf) = cndf$id
  row.names(svdf) = svdf$id
  bpgr = svgr[!is.na(svgr$partner)]
  bpgr = bpgr[seqnames(bpgr) == seqnames(partner(bpgr)) & strand(bpgr) == strand(partner(bpgr))]
  findBreakpointOverlaps(bpgr, bpgr, maxgap=max.breakend.gap, ignore.strand=TRUE, sizemargin=NULL, restrictMarginToSizeMultiple=NULL) %>%
    filter(
      bpgr[queryHits]$sampleId == bpgr[subjectHits]$sampleId &
      as.logical(strand(bpgr[queryHits]) != strand(bpgr[subjectHits])) &
      end(bpgr[queryHits]) < start(partner(bpgr)[queryHits]) &
        end(bpgr[subjectHits]) < start(partner(bpgr)[subjectHits]) &
      start(bpgr[queryHits]) < start(bpgr[subjectHits])) %>%
    mutate(
      beida=names(bpgr[queryHits]),
      beidb=names(bpgr[subjectHits]),
      beidc=ifelse(start(partner(bpgr)[queryHits]) <= start(partner(bpgr)[subjectHits]), bpgr$partner[queryHits], bpgr$partner[subjectHits]),
      beidd=ifelse(start(partner(bpgr)[queryHits]) <= start(partner(bpgr)[subjectHits]), bpgr$partner[subjectHits], bpgr$partner[queryHits])) %>%
    mutate(
      cnid_left_a=ifelse(strand(bpgr[beida]) == "+", bpgr[beida]$cnid, cndf[bpgr[beida]$cnid,]$prev_cnid),
      cnid_right_a=ifelse(strand(bpgr[beida]) == "-", bpgr[beida]$cnid, cndf[bpgr[beida]$cnid,]$next_cnid),

      cnid_left_b=ifelse(strand(bpgr[beidb]) == "+", bpgr[beidb]$cnid, cndf[bpgr[beidb]$cnid,]$prev_cnid),
      cnid_right_b=ifelse(strand(bpgr[beidb]) == "-", bpgr[beidb]$cnid, cndf[bpgr[beidb]$cnid,]$next_cnid),

      cnid_left_c=ifelse(strand(bpgr[beidc]) == "+", bpgr[beidc]$cnid, cndf[bpgr[beidc]$cnid,]$prev_cnid),
      cnid_right_c=ifelse(strand(bpgr[beidc]) == "-", bpgr[beidc]$cnid, cndf[bpgr[beidc]$cnid,]$next_cnid),

      cnid_left_d=ifelse(strand(bpgr[beidd]) == "+", bpgr[beidd]$cnid, cndf[bpgr[beidd]$cnid,]$prev_cnid),
      cnid_right_d=ifelse(strand(bpgr[beidd]) == "-", bpgr[beidd]$cnid, cndf[bpgr[beidd]$cnid,]$next_cnid)) %>%
    mutate(
      # simple inversions have nothing happening within the inversion
      # ie: CN3 = right(b) == left(c)
      simple_event_type="INV",
      is_simple_inversion=cnid_right_b==cnid_left_c,
      left_flank_cnid=cnid_left_a,
      left_overlap_cnid=ifelse(cnid_right_a == cnid_left_b, cnid_right_a, NA_character_),
      cnid=ifelse(cnid_right_b==cnid_left_c, cnid_right_b, NA_character_),
      right_overlap_cnid=ifelse(cnid_right_c == cnid_left_d, cnid_right_c, NA_character_),
      right_flank_cnid=cnid_right_d) %>%
    mutate(
      left_flank_ploidy=cndf[left_flank_cnid,]$copyNumber,
      left_overlap_ploidy=cndf[left_overlap_cnid,]$copyNumber,
      ploidy=cndf[cnid,]$copyNumber,
      right_overlap_ploidy=cndf[right_overlap_cnid,]$copyNumber,
      right_flank_ploidy=cndf[right_flank_cnid,]$copyNumber,
      svploidy_a=bpgr[beida]$ploidy,
      svploidy_b=bpgr[beidb]$ploidy) %>%
    mutate(
      sv_delta = svploidy_a - svploidy_b,
      flanking_ploidy_delta=left_flank_ploidy-right_flank_ploidy,
      ploidy_left_flank_delta=left_flank_ploidy - ploidy,
      ploidy_right_flank_delta=left_flank_ploidy - ploidy,
      ploidy_sv_delta = (svploidy_a + svploidy_b) / 2 - ploidy)
}
chain_events = function(links) {
  #chains = data.frame(
   # beid=unique(links$beid
    #index=1
  stop("TODO")
}

as_undirected_segment_connectivity_igraph = function(cngr, svgr) {
  bpgr = svgr[!is.na(svgr$partner)]
  df = bind_rows(
    findOverlaps(cngr, cngr, maxgap=1) %>%
      as.data.frame() %>%
      mutate(
        cnid1 = names(cngr)[queryHits],
        cnid2 = names(cngr)[subjectHits]) %>%
      dplyr::select(cnid1, cnid2),
    data.frame(
      cnid1=bpgr$cnid,
      cnid2=partner(bpgr)$cnid,
      stringsAsFactors=FALSE)) %>%
    filter(cnid1 < cnid2) %>%
    distinct()
  # TODO: add graph weighting by #edges or total edge ploidy
  ig = graph_from_data_frame(df, directed=FALSE, vertices=data.frame(cnid=names(cngr)))
  return(ig)
}
find_cn_communities = function(cngr, svgr) {
  ig = as_undirected_segment_connectivity_igraph(cngr, svgr)
  comm = cluster_edge_betweenness(ig)
  return(membership(comm))
}

get_community_sv_info_df = function(cndf, svdf, cngr, svgr, cn_membership) {
  cndf$community_id = cn_membership
  row.names(cndf) = cndf$id
  svgr$community_id = cndf[svgr$cnid,]$community_id
  svgr$arm = on_hg19_arm(svgr)
  sv_info = as.data.frame(svgr) %>%
    group_by(community_id) %>%
    summarise(
      community_breakend_count=n(),
      community_arms=str_replace_all(str_replace_all(paste0(unique(arm), collapse=","), "P", "p"), "Q", "q"))
  df = data.frame(community_id = unique(cn_membership), stringsAsFactors=FALSE) %>%
    left_join(sv_info, by="community_id") %>%
    replace_na(list(community_breakend_count=0))
  return(df)
}

export_to_visNetwork = function(cndf, svdf, cngr, svgr, sampleId, file=paste0("breakpointgraph.", sampleId, ".html")) {
  segmentSupportShape = function(support) {
    ifelse(support %in% c("TELOMERE", "CENTROMERE"), "triangle",
           ifelse(support == "BND", "square",
                  ifelse(support == "MULTIPLE", "circle",
                         "star")))
  }
  sampleFilterId = sampleId
  cndf = cndf %>% filter(sampleId == sampleFilterId)
  svdf = svdf %>% filter(sampleId == sampleFilterId)
  svgr = svgr[svgr$sampleId == sampleFilterId,]
  cndf$groupname = as.character(find_cn_communities(cngr, svgr))
  cndf = cndf %>%
    left_join(get_community_sv_info_df(cndf, svdf, cngr, svgr, cndf$groupname),
      by=c("groupname"="community_id")) %>%
    # split out small groups
    mutate(group = paste0(community_breakend_count, " breakends \n", community_arms)) %>%
    # remove groups with few breakends
    mutate(group = ifelse(community_breakend_count <= 6, NA, group)) %>%
    # never group arms with nothing happening
    mutate(group = ifelse(segmentStartSupport %in% c("CENTROMERE", "TELOMERE") & segmentEndSupport %in% c("CENTROMERE", "TELOMERE"), NA, group))

  nodes = bind_rows(
    # start
    cndf %>%
      mutate(
        label=round(copyNumber, 1),
        size=pmax(1, copyNumber),
        id=paste0(id, "-"),
        shape=segmentSupportShape(segmentStartSupport),
        color="lightblue"),
    # end
    cndf %>%
      mutate(
        size=copyNumber,
        id=paste0(id, "+"),
        shape=segmentSupportShape(segmentEndSupport),
        color="lightblue"),
    # unplaced single breakends
    svdf %>% filter(is.na(endChromosome)) %>%
      mutate(
        label=round(ploidy, 1),
        id=paste0("be_", id),
        shape="diamond",
        color="red")
  )
  edges = bind_rows(
    # internal segment edges
    cndf %>%
      mutate(
        from=paste0(paste0(id, "-")),
        to=paste0(paste0(id, "+")),
        color="lightblue",
        width=copyNumber,
        length=log10(end - start) + 1,
        title=paste0(chromosome, ":", start, "-", end, " (", end - start + 1, "bp) ", method, " ", actualBAF),
        smooth=FALSE,
        dashes=FALSE) %>%
      dplyr::select(from, to, color, width, length, title, smooth, dashes),
    # Reference edges
    cndf %>%
      group_by(sampleId, chromosome) %>%
      arrange(start) %>%
      mutate(nextid=lead(id)) %>%
      ungroup() %>%
      filter(!is.na(nextid)) %>%
      mutate(color=ifelse(segmentEndSupport == "CENTROMERE", "lightgreen", "green"),
             from=paste0(paste0(id, "+")),
             to=paste0(paste0(nextid, "-")),
             label=NA,
             width=2,
             length=NA,
             title=NA,
             smooth=FALSE,
             dashes=TRUE) %>%
      dplyr::select(from, to, color, label, width, length, title, smooth, dashes),
    # breakpoint edges
    svgr %>% as.data.frame() %>%
      inner_join(svdf, by=c("id"="id"), suffix=c("", ".df")) %>%
      group_by(sampleId, id) %>%
      arrange(seqnames, start) %>%
      mutate(
        partner_orientation=lead(strand),
        partner_cnid=lead(cnid)) %>%
      ungroup() %>%
      filter(!is.na(partner_cnid)) %>%
      mutate(
        color="red",
        from=paste0(paste0(cnid, strand)),
        to=paste0(paste0(partner_cnid, partner_orientation)),
        label=round(ploidy, 1),
        width=ploidy,
        length=NA,
        title=id,
        smooth=TRUE,
        dashes=FALSE) %>%
      dplyr::select(from, to, color, label, width, length, title, smooth, dashes),
    # breakend edges
    svgr %>% as.data.frame() %>%
      inner_join(svdf, by=c("id"="id"), suffix=c("", ".df")) %>%
      filter(is.na(partner)) %>%
      mutate(
        color="red",
        from=paste0(paste0(cnid, strand)),
        to=paste0("be_", id),
        label=round(ploidy, 1),
        width=ploidy,
        length=NA,
        title=id,
        smooth=TRUE,
        dashes=FALSE) %>%
      dplyr::select(from, to, color, label, width, length, title, smooth, dashes)
  )
  rescaling = list(width=5, length=3, size=3)
  visNetwork(
      nodes %>% mutate(size=pmin(size, 10) * rescaling$size),
      edges %>% mutate(width=pmin(width, 10) * rescaling$width, length=length * rescaling$length),
      height = "1000px", width = "100%") %>%
    visIgraphLayout(layout="layout_nicely", physics=TRUE, type="full", randomSeed=0) %>%
    visClusteringByGroup(cndf %>% filter(!is.na(group)) %>% pull(group) %>% unique(), label = "", force = FALSE, shape="big square") %>%
    visLegend() %>%
    visSave(file)
}

SVA_SVS_to_gr = function(sv_raw_df) {
  row.names(sv_raw_df) = sv_raw_df$Id
  full_gr = c(with(sv_raw_df, GRanges(
    seqnames=ChrStart,
    ranges=IRanges(start=PosStart, width=1),
    strand=ifelse(OrientStart == -1, "-", "+"),
    Id=Id,
    beid=paste0(Id, ifelse(ChrEnd != 0, "o", "b")),
    SampleId=SampleId,
    isLine=LEStart != "None",
    partner=ifelse(ChrEnd != 0, paste0(Id, "h"), NA),
    Homology=Homology,
    ihomlen=InexactHOEnd-InexactHOStart,
    insSeq=InsertSeq,
    qual=QualScore,
    cn=Ploidy,
    refContext=RefContextStart
  )), with(sv_raw_df %>% filter(ChrEnd != 0), GRanges(
    seqnames=ChrEnd,
    ranges=IRanges(start=PosEnd, width=1),
    strand=ifelse(OrientEnd == -1, "-", "+"),
    Id=Id,
    beid=paste0(Id, "h"),
    SampleId=SampleId,
    isLine=LEEnd != "None",
    partner=paste0(Id, "o"),
    Homology=Homology,
    ihomlen=InexactHOEnd-InexactHOStart,
    insSeq=InsertSeq,
    qual=QualScore,
    cn=Ploidy,
    refContext=RefContextEnd
  )))
  names(full_gr) = full_gr$beid
  return(full_gr)
}
query_cancer_type_by_sample = function(dbConnect) {
  query = "
    SELECT s.sampleId, primaryTumorLocation, cancerSubtype
    FROM baseline b
    INNER JOIN sample s ON b.patientId = s.patientId"
  return (DBI::dbGetQuery(dbConnect, query))
}

# wget http://www.repeatmasker.org/genomes/hg19/RepeatMasker-rm330-db20120124/hg19.fa.out.gz
# from http://github.com/PapenfussLab/sv_benchmark
import.repeatmasker.fa.out <- function(repeatmasker.fa.out) {
  cache_filename = paste0(repeatmasker.fa.out, ".grrm.rds")
  if (file.exists(cache_filename)) {
    grrm = readRDS(cache_filename)
  } else {
    rmdt <- read_table2(repeatmasker.fa.out, col_names=FALSE, skip=3)
    grrm <- GRanges(
      seqnames=rmdt$X5,
      ranges=IRanges(start=rmdt$X6 + 1, end=rmdt$X7),
      strand=ifelse(rmdt$X9=="C", "-", "+"),
      repeatType=rmdt$X10,
      repeatClass=rmdt$X11)
    saveRDS(grrm, file=cache_filename)
  }
  seqlevelsStyle(grrm) = "NCBI"
  return(grrm)
}
import.repeatmasker.insertseq <- function(rmoutfile) {
  rmdt <- read_table2(
      rmoutfile,
      col_names=c("swscore", "percdiv", "percdel", "percins", "query", "qstart", "qend", "qleft", "orientation", "repeatType", "repeatClass", "rstart", "rend", "rleft", "id", "hasBetterOverlappingMatch"),
      col_types="ddddcddcccccdcdc",
      skip=3)
}
repeatmasker.insertseq.summarise <- function(rmdt) {
  rmdt = rmdt %>%
    filter(is.na(hasBetterOverlappingMatch)) %>%
    mutate(match_length=qend-qstart)
  byrcdf_long = rmdt %>%
    group_by(repeatClass) %>%
    do({
      GRanges(seqnames=.$query, ranges=IRanges(start=.$qstart, .$qend), strand="*") %>%
        GenomicRanges::reduce() %>%
        as.data.frame() %>%
        group_by(seqnames) %>%
        summarise(nbases=sum(end - start))
    })
  byrcdf = byrcdf_long %>%
    spread(repeatClass, nbases) %>%
    replace(., is.na(.), 0)
  byrtdf = rmdt %>%
    filter(is.na(hasBetterOverlappingMatch)) %>%
    mutate(match_length=qend-qstart) %>%
    group_by(repeatType) %>%
    do({
      GRanges(seqnames=.$query, ranges=IRanges(start=.$qstart, .$qend), strand="*") %>%
        GenomicRanges::reduce() %>%
        as.data.frame() %>%
        group_by(seqnames) %>%
        summarise(nbases=sum(end - start))
    }) %>%
    spread(repeatType, nbases) %>%
    replace(., is.na(.), 0)
  closest_repeat = rmdt %>%
    group_by(query) %>%
    top_n(1, qstart + match_length / 100000) %>%
    ungroup() %>%
    filter(!duplicated(query)) %>%
    dplyr::select(query, closest_repeatType=repeatType, closest_repeatClass=repeatClass, closest_start=qstart, closest_match_length=match_length)
  longest_repeat = rmdt %>%
    group_by(query) %>%
    top_n(1, match_length - qstart / 100000) %>%
    ungroup() %>%
    filter(!duplicated(query)) %>%
    dplyr::select(query, longest_repeatType=repeatType, longest_repeatClass=repeatClass, longest_start=qstart, longest_match_length=match_length)
  byquery = full_join(closest_repeat, longest_repeat, by="query") %>%
    full_join(byrcdf, by=c("query"="seqnames")) %>%
    full_join(byrcdf, by=c("query"="seqnames"))
  if (byquery$closest_start > byquery$longest_start) {
    browser()
    stop("sanity check failure")
  }
  return(byquery)
}

getRepeatAnn = function(repeatClass) {
  repeatClass = str_extract(repeatClass, "^[^/]+")
  repeatClass <- ifelse(repeatClass %in% c("No repeat", "DNA", "LINE", "LTR", "SINE", "Satellite", "Other", "Low_complexity", "Simple_repeat"), repeatClass, "Other")
  repeatClass <- ifelse(repeatClass == "", "No repeat", repeatClass)
  repeatClass <- ifelse(repeatClass %in% c("Low_complexity", "Simple_repeat"), "Simple/Low complexity", repeatClass)
  repeatClass <- factor(repeatClass, levels = c("No repeat", "Simple/Low complexity", "Satellite", "LINE", "SINE", "DNA", "LTR", "Other"))
}
