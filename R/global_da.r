#' @include methods.r

#' @title Global Diversity analysis
#'
#' Compute the alpha diversity of each group of samples, of each study.
#'
#' @param input_dir A directory that contains data generated by \link[MetaMap]{transformData}. The default is inside the package.
#' @param max_samples Only studies with at most \code{max_samples} will be used. The default is 1000.
#' @param log A logical value indicating whether a log file should be generated with info about the process. The default is \code{FALSE}
#'
#' @return A CSV file that will be written in the current directory.
#' @export
globalDA <- function(input_dir = pkg_file("data"), max_samples = 1000,
                     log = F){
  output_dir <- file.path("da_results")
  dir.create(output_dir, showWarnings=F)

  r <- run(input_dir, max_samples, log)

  r$Result %>%
    .[order(.$Pvalue),] %>%
    write.csv(file.path(output_dir, "diversity_analysis.csv"), row.names=F)

  if(log){
    write.csv(r$Error, file.path(output_dir, "da_log.csv"), row.names = F)
  }
}

run <- function(input_dir, max_samples, log) {
  env <- environment()
  error <- data.frame()
  studies <- sapply(strsplit(list.files(file.path(input_dir, "studies")), split = "\\."), `[`, 1)
  res <- do.call(rbind, lapply(studies, function(study){
    cls <- class(try(loadPhylo(dir = input_dir, study, envir = environment())))
    if(cls == "try-error" || length(sample_names(phylo)) > max_samples) {
      error <- rbind(error, c(study, NA, geterrmessage()), stringsAsFactors = F)
      if(log) assign("error", error, env)
      return(NULL)
    }
    attributes <- sample_data(phylo) %>% colnames %>%
      subset(!. %in% c("sraID", "Total.Reads", "Selection", "All"))
    sapply(attributes, function(attribute){
      print(paste0(study, "_", attribute))
      PVal <- try(diversity_test(phylo, attribute), silent = T)
      if(class(PVal) == "try-error"){
        error <- rbind(error, c(study, attribute, geterrmessage()), stringsAsFactors = F)
        if(log) assign("error", error, env)
        return(NA)
      } else
        return(PVal)
    }) %>%
      data.frame(Study = rep(study, length(attributes)), Phenotype = names(.), Pvalue = .)
  }))
  if(log)
    colnames(error) <- c("Study", "Phenotype", "Messsage")
  return(list(Result = res, Error = error))
}
