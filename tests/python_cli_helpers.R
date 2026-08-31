orchidee_test_python <- function() {
  explicit <- Sys.getenv("ORCHIDEE_PYTHON", unset = "")
  if (nzchar(explicit)) {
    return(list(command = explicit, prefix = character()))
  }

  names <- if (.Platform$OS.type == "windows") {
    c("py", "python")
  } else {
    c("python3", "python")
  }
  paths <- Sys.which(names)
  available <- which(nzchar(paths))
  if (length(available) == 0L) {
    stop("Python 3 is required to run the ORCHIDEE operator CLI.")
  }
  selected <- available[[1L]]
  list(
    command = unname(paths[[selected]]),
    prefix = if (identical(names[[selected]], "py")) "-3" else character()
  )
}

orchidee_run_cli <- function(args) {
  python <- orchidee_test_python()
  output <- suppressWarnings(system2(
    python$command,
    c(
      python$prefix,
      shQuote(normalizePath(
        "scripts/orchidee.py",
        winslash = "/",
        mustWork = TRUE
      )),
      shQuote(args)
    ),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(status = status, output = output)
}
