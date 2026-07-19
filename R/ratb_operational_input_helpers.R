# Operational input selection for the RATB notebooks.
#
# This dispatcher preserves the CHU-native producer path while allowing the
# same downstream runtime to consume a strict canonical external bundle v2.

ratb_operational_input_sources <- function() {
  c("chu_native", "external_bundle_v2")
}

resolve_ratb_operational_context <- function(config) {
  if (!is.list(config) || !is.list(config$runtime)) {
    stop("orchidee_config$runtime must be a list.", call. = FALSE)
  }

  input_source <- config$runtime$input_source
  if (!is.character(input_source) || length(input_source) != 1L ||
      !input_source %in% ratb_operational_input_sources()) {
    stop(
      "orchidee_config$runtime$input_source must be exactly one of: ",
      paste(ratb_operational_input_sources(), collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  if (identical(input_source, "chu_native")) {
    return(list(
      input_source = input_source,
      is_chu_native = TRUE,
      bundle_dir = NULL,
      cache_dir = config$paths$data_dir,
      download_dir = config$paths$downloads_dir
    ))
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
  native_paths <- vapply(
    c(config$paths$data_dir, config$paths$downloads_dir),
    comparison_path,
    character(1)
  )
  if (any(external_paths %in% native_paths)) {
    stop(
      "orchidee_config$runtime$external_workspace_dir must keep external ",
      "cache and downloads separate from CHU-native paths.",
      call. = FALSE
    )
  }

  list(
    input_source = input_source,
    is_chu_native = FALSE,
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

load_existing_chu_ratb_scope_cache <- function(
    sir_wide,
    sir_wide_artifact_signature,
    data_dir = "data",
    cache_payload_path = file.path(data_dir, "ratb_scope_cache"),
    cache_meta_path = file.path(data_dir, "ratb_scope_cache_meta")
  ) {
  cache_paths <- c(cache_payload_path, cache_meta_path)
  if (!all(file.exists(cache_paths))) {
    stop(
      "Missing RATB scope cache artifacts. Render ",
      "orchidee_dedup_workflow.qmd first.",
      call. = FALSE
    )
  }

  payload <- tryCatch(readRDS(cache_payload_path), error = function(err) NULL)
  meta <- tryCatch(readRDS(cache_meta_path), error = function(err) NULL)

  if (!is.list(meta) || is.null(meta$fingerprint) ||
      !identical(
        meta$sir_wide_artifact_signature,
        sir_wide_artifact_signature
      ) ||
      !chu_ratb_cache_payload_is_usable(payload, sir_wide = sir_wide)) {
    stop(
      "Existing RATB scope cache is not usable. Render ",
      "orchidee_dedup_workflow.qmd first.",
      call. = FALSE
    )
  }

  list(
    payload = build_chu_ratb_runtime_payload_from_cache_payload(
      payload = payload,
      sir_wide = sir_wide
    ),
    meta = meta,
    source = cache_payload_path,
    decision = "loaded",
    cache_payload_path = cache_payload_path,
    cache_meta_path = cache_meta_path
  )
}

load_ratb_operational_runtime <- function(
    config,
    chu_cache_policy = "load_or_build"
  ) {
  allowed_cache_policies <- c("load_or_build", "load_existing")
  if (!is.character(chu_cache_policy) || length(chu_cache_policy) != 1L ||
      !chu_cache_policy %in% allowed_cache_policies) {
    stop(
      "chu_cache_policy must be exactly one of: ",
      paste(allowed_cache_policies, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  context <- resolve_ratb_operational_context(config)

  if (isTRUE(context$is_chu_native)) {
    sir_wide_path <- file.path(config$paths$data_dir, "sir_wide.rds")
    sir_wide_meta_path <- file.path(config$paths$data_dir, "sir_wide_meta.rds")
    missing_paths <- c(sir_wide_path, sir_wide_meta_path)[
      !file.exists(c(sir_wide_path, sir_wide_meta_path))
    ]
    if (length(missing_paths) > 0L) {
      stop(
        "Missing CHU-native sir_wide artifact files: ",
        paste(missing_paths, collapse = ", "),
        ". Run Rscript R/build_sir_wide_artifact.R first.",
        call. = FALSE
      )
    }

    sir_wide <- readRDS(sir_wide_path)
    sir_wide_meta <- readRDS(sir_wide_meta_path)
    artifact_validation <- validate_loaded_sir_wide_artifact(
      sir_wide = sir_wide,
      meta = sir_wide_meta
    )
    if (!isTRUE(artifact_validation$ok)) {
      stop(
        "CHU-native sir_wide artifact is invalid or inconsistent with metadata:\n - ",
        paste(artifact_validation$reasons, collapse = "\n - "),
        call. = FALSE
      )
    }

    sir_wide_artifact_signature <- compute_sir_wide_artifact_signature(
      sir_wide_path = sir_wide_path,
      sir_wide_meta_path = sir_wide_meta_path,
      meta = sir_wide_meta
    )

    if (identical(chu_cache_policy, "load_or_build")) {
      scope_result <- load_or_build_chu_ratb_scope_cache(
        sir_wide = sir_wide,
        sir_wide_meta = sir_wide_meta,
        sir_wide_artifact_signature = sir_wide_artifact_signature,
        data_dir = context$cache_dir,
        recompute = config$cache$recompute_ratb_scope,
        ref_dir = config$paths$ref_dir,
        structure_path = config$paths$consores_structure_path,
        codes_ta_path = config$paths$consores_codes_ta_path,
        codes_de_path = config$paths$consores_codes_de_path,
        microbiology_scope_policy = config$ratb$microbiology_scope_policy,
        incidence_denominator_policy = config$ratb$incidence_denominator_policy
      )
    } else {
      scope_result <- load_existing_chu_ratb_scope_cache(
        sir_wide = sir_wide,
        sir_wide_artifact_signature = sir_wide_artifact_signature,
        data_dir = context$cache_dir
      )
    }

    runtime_inputs <- scope_result$payload[c(
      "sir_wide_ratb_scope",
      "sir_wide_ratb_analytic_scope",
      "incidence_denominator_by_year"
    )]
    runtime_input_signature <- list(
      input_source = context$input_source,
      scope_fingerprint = as.character(scope_result$meta$fingerprint)
    )

    source <- scope_result$source
    decision <- scope_result$decision
    chu_native_qa <- scope_result$payload
    provenance <- list(input_source = context$input_source)
  } else {
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

    source <- "canonical external bundle v2"
    decision <- "loaded"
    chu_native_qa <- NULL
    provenance <- list(
      input_source = context$input_source,
      contract_version = bundle$validation_report$contract_version,
      sejuf_semantics = sir_wide_meta$sejuf_semantics
    )
  }

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
    chu_native_qa = chu_native_qa,
    runtime_input_signature = runtime_input_signature,
    provenance = provenance,
    source = source,
    decision = decision
  )
}
