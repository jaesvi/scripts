


driver_fusions <- function(fusions, tsGenes, oncoGenes) {
  if (!"shared" %in% colnames(fusions)) {
    fusions$shared <- F
  }

  result = fusions %>% select(sampleId, gene = `3pGene`, driver, shared) %>%
    mutate(type = "FUSION") %>%
    distinct() %>%
    mutate(
      type = ifelse(gene %in% tsGenes$gene_name, "TSG", type),
      type = ifelse(gene %in% oncoGenes$gene_name, "ONCO", type),
      driverLikelihood = 1)

  return (result)
}

driver_amplifications <- function(amps, tsGenes, oncoGenes, ampTargets) {
  if (!"shared" %in% colnames(amps)) {
    amps$shared <- F
  }

  result = amps %>%
    filter(gene %in% oncoGenes$gene_name | gene %in% ampTargets$target) %>%
    group_by(sampleId = sampleId, gene, shared) %>% summarise(driver = "Amp") %>%
    mutate(
      driverLikelihood = 1,
      type = ifelse(gene %in% tsGenes$gene, "TSG", "ONCO"),
      biallelic = T)

  return (result)
}


driver_deletions <- function(dels, tsGenes, oncoGenes, delTargets, fragileGenes) {
  if (!"shared" %in% colnames(dels)) {
    dels$shared <- F
  }
  deletionArms = delTargets %>% mutate(arm = coalesce(telomere, centromere)) %>% filter(!is.na(arm) ) %>% select(gene, arm)

  result = dels %>%
    filter(gene %in% tsGenes$gene_name | gene %in% geneCopyNumberDeleteTargets$target) %>%
    filter(germlineHetRegions == 0, germlineHomRegions == 0) %>%
    group_by(sampleId = sampleId, gene, shared) %>% summarise(driver = "Del", partial = somaticRegions > 1) %>%
    left_join(fragileGenes %>% select(gene = gene_name, fragile), by = "gene") %>%
    mutate(fragile = ifelse(is.na(fragile), F, T)) %>%
    mutate(
      driverLikelihood = 1,
      type = ifelse(gene %in% oncoGenes$gene, "ONCO", "TSG"),
      driver = ifelse(fragile, "FragileDel", driver),
      biallelic = T) %>%
    left_join(deletionArms, by = "gene") %>%
    ungroup() %>%
    mutate(gene = coalesce(arm, gene)) %>%
    select(-arm)

  return (result)
}

driver_promoters <- function(promoters) {

  if (!"shared" %in% colnames(promoters)) {
    promoters$shared <- F
  }

  result = promoters %>%
    mutate(coordinate = genomic_coordinates(chromosome, position, ref, alt)) %>%
    group_by(sampleId, gene, shared) %>%
    summarise(
      driver = "Promoter",
      coordinate = first(coordinate),
      driverLikelihood = 1,
      hotspot = "Hotspot",
      type = "ONCO")

  return (result)
}

