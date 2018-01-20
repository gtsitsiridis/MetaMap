#' @include methods.r

#' @title Global Differential Expression
#'
#' Perform DESeq2 on each group of samples for each study.
#'
#' @param input_dir A directory that contains data generated by \link[MetaMap]{transformData}. The default is inside the package.
#' @param max_samples Only studies with at most \code{max_samples} will be used. The default is 1000.
#' @param log A logical value indicating whether a log file should be generated with info about the process. The default is \code{FALSE}
#'
#' @return CSV files containing DESeq2 tables.
#' @export
globalDE <- function(input_dir = pkg_file("data"), max_samples = 1000,
                     log = F){
  output_dir <- file.path("de_results")
  dir.create(output_dir, showWarnings=F)

  r <- run(input_dir, output_dir, max_samples, log)

  if(log){
    write.csv(r, file.path(output_dir, "de_log.csv"), row.names = F)
  }
}

run <- function(input_dir, output_dir, max_samples, log) {
  env <- environment()
  error <- data.frame()
  studies <- sapply(strsplit(list.files(file.path(input_dir, "studies")), split = "\\."), `[`, 1)
  lapply(studies, function(study){
    cls <- class(try(loadPhylo(dir = input_dir, study, envir = environment())))
    if(cls == "try-error" || length(sample_names(phylo)) > max_samples) {
      error <- rbind(error, c(study, NA, geterrmessage()), stringsAsFactors = F)
      if(log) assign("error", error, env)
      return(NULL)
    }
    attributes <- sample_data(phylo) %>% colnames %>%
      subset(!. %in% c("sraID", "Total.Reads", "Selection", "All"))
    lapply(attributes, function(attribute){
      file_path <- file.path(output_dir,paste0(study,"_", attribute, ".csv"))
      print(file_path)
      if(file.exists(file_path)) return()
      de_table <- try(deseq2_table(phylo, attribute), silent = T)
      if(class(de_table) == "try-error"){
        error <- rbind(error, c(study, attribute, geterrmessage()), stringsAsFactors = F)
        if(log) assign("error", error, env)
        return(NULL)
      } else {
          rownames(de_table) <- taxids2names(phylo, rownames(de_table))
          write.csv(de_table, file_path)
      }
    })
  })
  colnames(error) <- c("Study", "Phenotype", "Messsage")
  error
}
