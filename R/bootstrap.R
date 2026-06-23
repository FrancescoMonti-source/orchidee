# Shared path-resolution and sourcing helpers.
#
# Keep this file dependency-light: it is used before the rest of the project
# helpers are available.

orchidee_resolve_existing_path <- function(candidates, what = "required file") {
  existing <- candidates[file.exists(candidates)]
  if (length(existing) == 0L) {
    stop(
      "Missing ", what, ". Expected one of: ",
      paste(candidates, collapse = ", "),
      call. = FALSE
    )
  }
  existing[[1]]
}

orchidee_resolve_script_path <- function(script_name, what = NULL) {
  if (is.null(what)) {
    what <- paste0("script ", script_name)
  }
  orchidee_resolve_existing_path(
    c(file.path("R", script_name), script_name),
    what = what
  )
}

orchidee_resolve_config_path <- function(config_name, what = NULL) {
  if (is.null(what)) {
    what <- paste0("config ", config_name)
  }
  orchidee_resolve_existing_path(
    c(file.path("config", config_name), config_name),
    what = what
  )
}

orchidee_source_required_script <- function(script_name, what = NULL) {
  source(orchidee_resolve_script_path(script_name, what = what))
}

orchidee_source_required_config <- function(config_name, what = NULL) {
  source(orchidee_resolve_config_path(config_name, what = what))
}

orchidee_required_functions_available <- function(required_funs) {
  all(vapply(required_funs, exists, logical(1), mode = "function"))
}

orchidee_source_script_if_missing <- function(script_name, required_funs, what = NULL) {
  if (!orchidee_required_functions_available(required_funs)) {
    orchidee_source_required_script(script_name, what = what)
  }

  if (!orchidee_required_functions_available(required_funs)) {
    stop(
      "Required functions are not available after sourcing ",
      script_name,
      ": ",
      paste(required_funs, collapse = ", "),
      call. = FALSE
    )
  }

  invisible(TRUE)
}
