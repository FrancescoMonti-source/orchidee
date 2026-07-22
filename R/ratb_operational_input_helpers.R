# Operational external-bundle v2 input for the RATB notebooks.

resolve_ratb_operational_context <- function(config) {
  if (!is.list(config) || !is.list(config$runtime)) {
    stop("orchidee_config$runtime must be a list.", call. = FALSE)
  }

  bundle_dir <- config$runtime$external_bundle_v2_dir
  workspace_dir <- config$runtime$external_workspace_dir
  if (!is.character(bundle_dir) || length(bundle_dir) != 1L || !nzchar(bundle_dir)) {
    stop(
      "orchidee_config$runtime$external_bundle_v2_dir must be a non-empty path.",
      call. = FALSE
    )
  }
  if (!is.character(workspace_dir) || length(workspace_dir) != 1L ||
      !nzchar(workspace_dir)) {
    stop(
      "orchidee_config$runtime$external_workspace_dir must be a non-empty path.",
      call. = FALSE
    )
  }

  external_cache_dir <- file.path(workspace_dir, "cache")
  external_download_dir <- file.path(workspace_dir, "downloads")
  comparison_path <- function(path) {
    normalized <- normalizePath(path, winslash = "/", mustWork = FALSE)
    if (.Platform$OS.type == "windows") tolower(normalized) else normalized
  }
  external_paths <- vapply(
    c(external_cache_dir, external_download_dir),
    comparison_path,
    character(1)
  )
  protected_paths <- vapply(
    c(config$paths$data_dir, config$paths$downloads_dir),
    comparison_path,
    character(1)
  )
  if (any(external_paths %in% protected_paths)) {
    stop(
      "orchidee_config$runtime$external_workspace_dir must keep external ",
      "cache and downloads separate from protected local paths.",
      call. = FALSE
    )
  }

  list(
    input_source = "external_bundle_v2",
    bundle_dir = bundle_dir,
    cache_dir = external_cache_dir,
    download_dir = external_download_dir
  )
}

ratb_external_bundle_signature <- function(validation_report) {
  paths <- validation_report$paths
  roles <- c(
    "sir_wide",
    "sir_wide_meta",
    "sample_scope_reference",
    "denominator_bundle"
  )
  if (!is.list(paths) || !all(roles %in% names(paths))) {
    stop("Validated external bundle paths are incomplete.", call. = FALSE)
  }

  artifact_paths <- unlist(paths[roles], use.names = FALSE)
  if (any(!file.exists(artifact_paths))) {
    stop("Validated external bundle files are no longer available.", call. = FALSE)
  }
  hashes <- as.list(as.character(unname(tools::md5sum(artifact_paths))))
  names(hashes) <- roles

  list(
    input_source = "external_bundle_v2",
    contract_version = "v2",
    bundle_files = hashes
  )
}

load_ratb_operational_runtime <- function(config) {
  context <- resolve_ratb_operational_context(config)
  bundle <- load_validated_external_input_bundle(
    bundle_dir = context$bundle_dir,
    contract = orchidee_external_contract_v2(),
    strict_preferred = TRUE
  )
  sir_wide <- bundle$sir_wide
  sir_wide_meta <- bundle$sir_wide_meta
  runtime_inputs <- build_ratb_downstream_scope_from_canonical_inputs(
    sir_wide = sir_wide,
    sample_scope_reference = bundle$sample_scope_reference,
    denominator_bundle = bundle$denominator_bundle
  )
  runtime_input_signature <- ratb_external_bundle_signature(
    bundle$validation_report
  )

  stop_if_invalid_ratb_canonical_runtime_inputs(
    runtime_inputs = runtime_inputs,
    sir_wide = sir_wide
  )

  list(
    input_source = context$input_source,
    context = context,
    sir_wide = sir_wide,
    sir_wide_meta = sir_wide_meta,
    runtime_inputs = runtime_inputs,
    runtime_input_signature = runtime_input_signature,
    provenance = list(
      input_source = context$input_source,
      contract_version = bundle$validation_report$contract_version,
      sejuf_semantics = sir_wide_meta$sejuf_semantics
    ),
    source = "canonical external bundle v2",
    decision = "loaded"
  )
}
