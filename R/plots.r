#' @include methods.r

#' @title Top relative abundance
#'
#' Plot the relative abundance of the \code{top_n} most abundant species.
#'
#' @param phylo \link[phyloseq]{phyloseq} object
#' @param top_n integer indicating how many species to show
#' @param attribute Column name of the sample table, obtained from \link[phyloseq]{sam_data}.
#'
#'
#' @return A bar plot grouped by \code{attribute}.
#' @export
plot_top_species <- function(phylo, top_n = 10L, attribute) {
  if (is.null(phylo))
    return(NULL)
  relativeCounts(phylo)%>%
    t %>%
    as.data.frame %>%
    mutate(Selection = unlist(phylo@sam_data[, attribute])) %>%
    group_by(Selection) %>%
    summarise_all(funs(mean, sd)) %>%
    gather(key, Value,-Selection) %>%
    with(
      .,
      data.frame(
        Mean = Value[grep("_mean", key)],
        SD = Value[grep("_sd", key)],
        Selection = Selection[grep("_mean", key)],
        TaxID = str_sub(key[grep("_mean", key)], 1,-6),
        stringsAsFactors = F
      )
    ) %>%
    arrange(desc(Mean)) %>%
    group_by(Selection) %>%
    mutate(
      SpeciesUnordered = taxids2names(phylo, TaxID),
      Species = factor(SpeciesUnordered, SpeciesUnordered[order(Mean)])
    ) %>%
    plotly::slice(seq_len(min(top_n, n()))) %>%
    #{View(.); .} %>%
    ggplot(aes(Species, Mean, fill = Selection)) +
    geom_col(position = 'dodge') +
    geom_errorbar(aes(ymin = ifelse((Mean - SD) < 0, 0, (Mean - SD)), ymax = Mean + SD), width = 0.2) +
    scale_x_discrete(expand = c(0, 0)) + scale_y_continuous(expand = c(0, 0)) +
    coord_flip() + labs(x = 'Species / Metafeature', y = 'Mean relative abundance (RPM)')
}

#' Volcano plot
#'
#' Plot the log2(Fold change) against the p-value.
#'
#' @param tax_table A table obtained by \link[phyloseq]{tax_table}.
#' @param de_table A de_table obtained from \link{deseq2_table}.
#'
#'
#' @return An intercative volcano plot generated by plotly.
#' @export
plot_volcano <- function(tax_table, de_table) {
  a <- "p-value < 0.05 and log2(Fold Change) > 2"
  b <- "p-value > 0.05 and log2(Fold Change) > 2"
  c <- "p-value < 0.05 and log2(Fold Change) < 2"
  d <- "p-value > 0.05 and log2(Fold Change) < 2"
  cols <- c("green",
            "orange",
            "red",
            "black")
  names(cols) <- c(a, b, c, d)
  tmp <-
    data.table(Species = as.character(tax_table[rownames(de_table), "Species"]), de_table[, c("log2FoldChange", "padj")])
  tmp <- tmp[complete.cases(tmp)]
  tmp$threshold <-
    with(tmp, ifelse(
      abs(log2FoldChange) > 2,
      ifelse(padj < 0.05,
             a, b),
      ifelse(padj < 0.05 ,
             c, d)
    ))
  p <-
    ggplot(data = tmp,
           aes(label = Species,
               log2FoldChange, -log10(padj))) +
    # , colour = threshold)) +
    geom_point() +
    labs(x = "Fold change (log2)", y = "-log10 p-value")
  # + scale_color_manual(values = cols)
  p
}

#' Sankey plot
#'
#' Plot a sankey diagram.
#'
#' @param phylo \link[phyloseq]{phyloseq} object
#' @param source \code{c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")}
#' @param target \code{c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")}
#' @param level_filter \code{c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")}
#' @param source_filter String to filter \code{source} values.
#'
#' @return An intercative sankey plot generated by plotly.
#' @export
plot_sankey <-
  function(phylo,
           source = "Kingdom",
           target = "Phylum",
           level_filter = NULL,
           source_filter = NULL) {
    if (is.null(phylo))
      return(NULL)

    # Deal with NA values
    tax_table <- clean_tax_table(phylo@tax_table)

    firstLevel <- which(colnames(tax_table) == source)
    lastLevel <- which(colnames(tax_table) == target)
    levls <- colnames(tax_table)[firstLevel:lastLevel]

    pairs <-
      lapply(1:(length(levls) - 1), function(x)
        list(Source = levls[x], Target = levls[x + 1]))

    phylo@tax_table <- tax_table(tax_table)

    links <-
      do.call(rbind, lapply(pairs, function(x)
        makeSankey_links(
          tax_table,
          relativeCounts(phylo),
          x$Source,
          x$Target,
          source_filter,
          level_filter
        )))

    # Add __S and __T
    links$Source <-
      paste0(substr(links$Source_level, 1, 1), "__", links$Source)
    links$Target <-
      paste0(substr(links$Target_level, 1, 1), "__", links$Target)

    sources <- links$Source %>% unique
    targets <- links$Target %>% unique
    node_labels <-
      c(sources, targets) %>% setNames(0:(length(.) - 1), .)
    links <- links %>%
      mutate(SourceNr = node_labels[Source],
             TargetNr = node_labels[Target])

    p <- plot_ly(
      source = "sankey",
      type = "sankey",
      valueformat = ".0f",
      valuesuffix = "%",
      node = list(
        label = names(node_labels),
        # color = json_data$data[[1]]$node$color,
        pad = 15,
        thickness = 15,
        line = list(color = "black",
                    width = 0.5)
      ),

      link = with(links, list(
        source = SourceNr,
        target = TargetNr,
        value =  Value
      ))
    )
    return(list(plot = p, links = links))
  }

#' Taxonomy Bar Chart
#'
#' Plot a Taxonomy Bar Chart.
#'
#' @param phylo \link[phyloseq]{phyloseq} object.
#' @param attribute Column name of the sample table, obtained from \link[phyloseq]{sam_data}.
#' @param level \code{c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species".)}
#' @param relative logical value.
#'
#'
#' @return A barplot grouped by \code{attribute}.
#' @export
plot_taxa <- function(phylo, attribute, level, relative = T) {
  if (is.null(phylo))
    return(NULL)
  phylo@tax_table <- tax_table(as.matrix(clean_tax_table(phylo@tax_table)))
  if(relative){
    phylo@otu_table <- otu_table(relativeCounts(phylo), taxa_are_rows = T)
  }
  # trim to 10 most abundant taxa
  taxa_sums <- taxa_sums(phylo)
  taxa <- data.frame(Abundance = taxa_sums, Level = as.character(phylo@tax_table[names(taxa_sums),level]), stringsAsFactors=F) %>%
    group_by(Level) %>%
    summarize(Abundance= sum(Abundance)) %>% arrange(desc(Abundance)) %>% .[1:min(nrow(.), 10), "Level"] %>% unlist
  environment(subset_taxa) <- environment()
  phylo <- subset_taxa(phylo, phylo@tax_table[,level] %in% taxa)
  p <- plot_bar(phylo, x = attribute, fill = level) +
    aes(label = Species, y = Abundance) +
    geom_bar(stat = "identity") + coord_flip() +
    theme(axis.text.x = element_text(angle = 0, vjust = 1),
          axis.title.y = element_blank())
  if (relative) {
    groups <-
      aggregate(as.formula(paste("Abundance ~", attribute)), p$data, sum) %>%
      {
        setNames(.$Abundance, .[, attribute])
      }
    # p$data$Abundance <-
    p$data$Abundance <-
      p$data$Abundance / groups[p$data[, attribute]] * 100
  }
  p$data <- subset(p$data, Abundance != 0)
  p
}


# Function to plot species abundance (barplot)
plot_abundance <- function(phylo, taxids, attribute) {
  if (is.null(phylo))
    return(NULL)
  sorted_info <- phylo@sam_data %>%
    transmute(
      Run = rownames(.),
      Selection = unlist(.[, attribute]),
      Transcript = `Total.Reads`,
      Species = 'all'
    )
  species_info <-
    if (length(taxids) == 0L) {
      NULL
    } else {
      phylo@otu_table[taxids, ] %>%
        t %>%
        as.data.frame %>%
        bind_cols(sorted_info %>% select(Run, Selection)) %>%
        gather(TaxID, Transcript, one_of(taxids)) %>%
        mutate(Species = taxids2names(phylo, TaxID), TaxID = NULL)
    }
  bind_rows(species_info, sorted_info) %>%
    mutate(
      AllSpecies = Species == 'all',
      Species = factor(Species, c('all', Species %>% unique %>% sort) %>% unique),
      SpeciesKind = ifelse(AllSpecies, 'All species', 'Selected species'),
      MaxTranscript = ifelse(AllSpecies, max(Transcript), max(Transcript[!AllSpecies]))
    ) %>%
    # {View(.); .} %>%
    ggplot(aes(Run, Transcript, fill = Species)) +
    geom_col(position = 'dodge') +
    geom_col(
      aes(y = MaxTranscript, alpha = Selection),
      position = 'stack',
      fill = '#acbad5',
      width = 1
    ) +
    scale_alpha_discrete(range = c(0, .5)) +
    scale_x_discrete(expand = c(0, 0)) + scale_y_continuous(expand = c(0, 0)) +
    facet_wrap(~ SpeciesKind, scales = 'free_x') +
    coord_flip() + labs(x = 'Run', y = 'Relative abundance')
}

#' DE Boxplot
#'
#' Plot Boxplots for the abundance distribution of the \code{taxids} grouped by \code{attribute}.
#'
#' @param phylo \link[phyloseq]{phyloseq} object.
#' @param taxids a list of taxids.
#' @param attribute Column name of the sample table, obtained from \link[phyloseq]{sam_data}.
#'
#'
#' @return A ggplot2 object showing the boxplots.
#' @export
plot_diff <- function(phylo, taxids, attribute) {
  relativeCounts(phylo)[taxids, ] %>%
    t %>%
    as.data.frame %>%
    mutate(Selection = unlist(phylo@sam_data[, attribute])) %>%
    gather(TaxID, Transcript, -Selection) %>%
    mutate(Species = taxids2names(phylo, TaxID)) %>%
    # {View(.);.} %>%
    ggplot(aes(Selection, Transcript, colour = Species)) +
    geom_boxplot(position = 'dodge') +
    labs(x = 'Grouping', y = 'Relative abundance')
}

#' MDS plot
#'
#' Plot MDS of the given phyloseq object, colored by \code{color}.
#'
#' @param phylo \link[phyloseq]{phyloseq} object.
#' @param color Column name of the sample table, obtained from \link[phyloseq]{sam_data}. The distance methods used is JSD.
#'
#'
#' @return A ggplot2 object showing the MDS plot
#' @export
plot_mds <- function(phylo, color) {
  if (is.null(phylo))
    return(NULL)
  phylo@otu_table <- otu_table(relativeCounts(phylo), taxa_are_rows = T)
  sam_dt_names <- names(phylo@sam_data)
  attrs <-
    c("Axis.1",
      "Axis.2",
      sam_dt_names[sam_dt_names != "All"]) %>% setNames(c("x", "y", paste0("label", 1:(length(
        .
      ) - 2)))) %>% as.list
  p <-
    plot_ordination(phylo, ordinate(phylo, 'MDS', phyloseq::distance(phylo, 'jsd')), color = color) +
    do.call(aes_string, attrs)
  ggplotly(p, tooltip = c(names(attrs)))
}

#' Alpha diversity plot
#'
#' Plot Alpha diversity of the given phyloseq object, colored by \code{color}.
#'
#' @param phylo \link[phyloseq]{phyloseq} object.
#' @param color Column name of the sample table, obtained from \link[phyloseq]{sam_data}. The distance methods used is JSD.
#'
#'
#' @return A ggplot2 object showing the alpha diversity plot.
#' @export
plot_alpha <- function(phylo, color) {
  if (is.null(phylo))
    return(NULL)
  sam_dt_names <- names(phylo@sam_data)
  attrs <-
    c("samples",
      "value",
      sam_dt_names[!sam_dt_names %in% c("All", "sraID")]) %>% setNames(c("x", "y", paste0("label", 1:(length(
        .
      ) - 2)))) %>% as.list
  p <- plot_richness(phylo, measures = "Shannon", color = color)
  if (!is.null(color)) {
    newOrder <- p$data[order(p$data[, color]), "samples"]
    p$data$samples <- factor(p$data[["samples"]], levels = newOrder)
  }
  p <- p + do.call(aes_string, attrs) +
    labs(x = p$labels$x, y = p$labels$y) + theme(axis.text.x = element_blank(), axis.ticks = element_blank())
  ggplotly(p, tooltip = c(names(attrs)))
}

# Function to plot DE heatmap
plot_de_heatmap <-
  function(phylo,
           de_table,
           attribute,
           cond1,
           cond2,
           top_n = 20L) {
    if (is.null(phylo))
      return(NULL)
    if (nrow(de_table) < top_n)
      top_n <- nrow(de_table)
    top_otus <-
      de_table[order(de_table$padj),][1:top_n,] %>% rownames
    environment(subset_samples) <- environment()
    phylo <-
      subset_samples(phylo, unlist(phylo@sam_data[, attribute]) %in% c(cond1, cond2))
    phylo <- prune_taxa(top_otus, phylo)

    p <-
      plot_heatmap(phylo,
                   "NMDS",
                   "jaccard",
                   sample.label = attribute,
                   taxa.label = "Species") +
      aes(x = Sample, label = Species, fill = Abundance) +
      theme(axis.title.x = element_blank(), axis.title.y = element_blank())
    # avoid -inf values
    p$data$Abundance <- p$data$Abundance + 1
    ggplotly(p) %>% layout(margin = list(b = 120))
  }

#' Metafeature plot
#'
#' Plots the maximum abundance of each metafeature against the percentage of studies covering it.
#'
#'
#' @export
mfPlot <- function(mf_tbl) {
  mfMax <- apply(mf_tbl, 1, function(x) {
    study_nr <- which.max(x)
    c(study_nr, x[study_nr])
  }) %>% t %>% as.data.frame
  colnames(mfMax) <- c("maxStudy", "maxRelAbundance")
  mfMax$maxStudy <- colnames(mf_tbl)[mfMax$maxStudy]
  mfCoverage <-
    apply(mf_tbl, 1, function(x)
      length(which(!is.na(x))) / length(x) * 100)
  df <- cbind(mfMax, as.data.frame(mfCoverage))
  df$Metafeature <- rownames(df)
  ggplot(df,
         aes(
           x = mfCoverage,
           y = maxRelAbundance,
           label1 = Metafeature,
           label2 = maxStudy
         )) + geom_point() + labs(x = "% Covered", y = "Maximum relative abundance (RPM)")
}
