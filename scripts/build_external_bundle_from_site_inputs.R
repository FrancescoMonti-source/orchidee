#!/usr/bin/env Rscript

resolve_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0L) {
    script_file <- sub("^--file=", "", file_arg[[1]])
    script_dir <- dirname(normalizePath(script_file, winslash = "/", mustWork = TRUE))
    return(normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

normalize_output_path_for_comparison <- function(path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (identical(.Platform$OS.type, "windows")) tolower(normalized) else normalized
}

project_root <- resolve_project_root()
setwd(project_root)

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
suppress_next_steps <- "--no-next-steps" %in% args
retired_contract_args <- grep("^--contract=", args, value = TRUE)
if (length(retired_contract_args) > 0L) {
  stop(
    "This builder always constructs the complete v3 contract. Remove ",
    "--contract=...; direct v2 construction is retired.",
    call. = FALSE
  )
}
operational_v2_args <- grep(
  "^--operational-v2-output=",
  args,
  value = TRUE
)
if (length(operational_v2_args) > 1L) {
  stop("Pass at most one --operational-v2-output option.", call. = FALSE)
}
operational_v2_output <- if (length(operational_v2_args) == 0L) {
  NA_character_
} else {
  sub("^--operational-v2-output=", "", operational_v2_args[[1L]])
}
if (!is.na(operational_v2_output) && !nzchar(operational_v2_output)) {
  stop("--operational-v2-output requires a directory.", call. = FALSE)
}
args <- setdiff(
  args,
  c("--force", "--no-next-steps", operational_v2_args)
)

if (length(args) == 8L) {
  stop(
    "The handoff contains exactly six site-owned blocks; do not pass a ",
    "seventh de_reference block.",
    call. = FALSE
  )
}
if (length(args) != 7L || "--help" %in% args || "-h" %in% args) {
  cat(
    "Usage (PowerShell):\n",
    "  & .\\scripts\\run_r.ps1 ",
    "scripts/build_external_bundle_from_site_inputs.R `\n",
    "    <microbiology_observations.{rds,csv,tsv,tab,txt}> `\n",
    "    <bacteria_mapping.{rds,csv,tsv,tab,txt}> `\n",
    "    <sample_type_mapping.{rds,csv,tsv,tab,txt}> `\n",
    "    <antibiotic_mapping.{rds,csv,tsv,tab,txt}> `\n",
    "    <unit_mapping.{rds,csv,tsv,tab,txt}> `\n",
    "    <denominator.{rds,csv,tsv,tab,txt}> `\n",
    "    <output_bundle_dir> `\n",
    "    [--operational-v2-output=<dir>] [--force] ",
    "[--no-next-steps]\n\n",
    "Inputs:\n",
    "  microbiology_observations: long local S/I/R observations with the\n",
    "    columns documented in site_contract.md.\n",
    "  bacteria_mapping: bacteria_local + bact_norm.\n",
    "  sample_type_mapping: sample_type_local + naturepvt_norm.\n",
    "  antibiotic_mapping: antibiotic_local + atb_norm.\n",
    "  unit_mapping: one row per SEJUF with CODE_TA, CODE_DE and\n",
    "    de_domain_ref directly in this block.\n",
    "  incidence exposure: calendar_year + SEJUM + SEJUF + CODE_TA + CODE_DE +\n",
    "    de_domain_ref + denominator_profile_id + exposure_value + exposure_unit.\n",
    "  This builder always constructs the complete v3 contract; unit_mapping\n",
    "    must contain CODE_TA, CODE_DE and de_domain_ref.\n",
    "  --operational-v2-output: validate v3, then materialize its closed\n",
    "    spares_current projection as a separate operational v2 bundle.\n",
    "  --no-next-steps: suppress copyable commands when a higher-level\n",
    "    operator wrapper owns the remaining workflow.\n",
    sep = ""
  )
  quit(status = if (length(args) == 0L || "--help" %in% args || "-h" %in% args) 0L else 1L)
}
microbiology_path <- args[[1L]]
bacteria_mapping_path <- args[[2L]]
sample_type_mapping_path <- args[[3L]]
antibiotic_mapping_path <- args[[4L]]
unit_mapping_path <- args[[5L]]
denominator_path <- args[[6L]]
output_bundle_dir <- args[[7L]]

bundle_file_names <- c(
  "sir_wide.rds",
  "sir_wide_meta.rds",
  "sample_scope_reference.rds",
  "denominator_bundle.rds"
)
bundle_object_names <- sub("\\.rds$", "", bundle_file_names)

bundle_known_output_paths <- function(output_dir) {
  c(
    file.path(output_dir, bundle_file_names),
    file.path(output_dir, "build_manifest.txt"),
    file.path(output_dir, "build_manifest.txt.tmp")
  )
}

quote_powershell_string <- function(value) {
  paste0("'", gsub("'", "''", value, fixed = TRUE), "'")
}

site_build_lock_path <- function(output_dir) {
  paste0(
    normalizePath(output_dir, winslash = "/", mustWork = FALSE),
    ".site-build.lock"
  )
}

claim_site_build_locks <- function(output_dirs) {
  lock_paths <- sort(unique(vapply(
    output_dirs,
    site_build_lock_path,
    character(1)
  )))
  claimed <- character()
  keep_claimed <- FALSE
  on.exit({
    if (!keep_claimed && length(claimed) > 0L) {
      unlink(claimed, recursive = TRUE, force = TRUE)
    }
  }, add = TRUE)

  for (lock_path in lock_paths) {
    lock_parent <- dirname(lock_path)
    if (!dir.exists(lock_parent) && !dir.create(
      lock_parent,
      recursive = TRUE,
      showWarnings = FALSE
    )) {
      stop("Cannot create build-lock parent: ", lock_parent, call. = FALSE)
    }
    if (!dir.create(lock_path, showWarnings = FALSE)) {
      owner_path <- file.path(lock_path, "owner.txt")
      owner <- if (file.exists(owner_path)) {
        paste(readLines(owner_path, warn = FALSE), collapse = "; ")
      } else {
        "owner metadata unavailable"
      }
      cleanup_command <- paste0(
        "Remove-Item -LiteralPath ",
        quote_powershell_string(lock_path),
        " -Recurse -Force"
      )
      stop(
        "Another site build holds the output lock ",
        lock_path,
        " (",
        owner,
        "). Remove this lock only after confirming no build is running. ",
        "PowerShell: ",
        cleanup_command,
        call. = FALSE
      )
    }
    claimed <- c(claimed, lock_path)
    writeLines(
      c(
        paste0("pid: ", Sys.getpid()),
        paste0(
          "claimed_at_utc: ",
          format(Sys.time(), tz = "UTC", usetz = TRUE)
        )
      ),
      file.path(lock_path, "owner.txt"),
      useBytes = TRUE
    )
  }

  keep_claimed <- TRUE
  claimed
}

invalidate_site_bundle_markers <- function(staged_bundles, force) {
  marker_paths <- unlist(lapply(staged_bundles, function(staged) {
    file.path(
      staged$output_dir,
      c("build_manifest.txt", "build_manifest.txt.tmp")
    )
  }), use.names = FALSE)
  existing <- marker_paths[file.exists(marker_paths)]
  if (!isTRUE(force)) {
    if (length(existing) > 0L) {
      stop(
        "Completion markers appeared while this build was staging. ",
        "No output was replaced; retry with another directory.",
        call. = FALSE
      )
    }
    return(invisible(marker_paths))
  }

  unlink(existing, force = TRUE)
  remaining <- marker_paths[file.exists(marker_paths)]
  if (length(remaining) > 0L) {
    stop(
      "Cannot invalidate existing completion markers: ",
      paste(remaining, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(marker_paths)
}

requested_output_dirs <- c(output_bundle_dir, operational_v2_output)
requested_output_dirs <- requested_output_dirs[!is.na(requested_output_dirs)]
output_files_instead_of_dirs <- requested_output_dirs[
  file.exists(requested_output_dirs) & !dir.exists(requested_output_dirs)
]
if (length(output_files_instead_of_dirs) > 0L) {
  stop(
    "Output must be a directory, not an existing file: ",
    paste(output_files_instead_of_dirs, collapse = ", "),
    call. = FALSE
  )
}
if (!is.na(operational_v2_output) && identical(
  normalize_output_path_for_comparison(output_bundle_dir),
  normalize_output_path_for_comparison(operational_v2_output)
)) {
  stop(
    "--operational-v2-output must differ from output_bundle_dir.",
    call. = FALSE
  )
}
requested_output_paths <- unlist(
  lapply(requested_output_dirs, bundle_known_output_paths),
  use.names = FALSE
)
if (!isTRUE(force) && any(file.exists(requested_output_paths))) {
  stop(
    "Output bundle artifacts already exist in a requested output directory",
    ". Pass --force to overwrite them.",
    call. = FALSE
  )
}

suppressPackageStartupMessages(library(dplyr))
source("R/bootstrap.R")
orchidee_source_required_script("helpers.R")
orchidee_source_required_script("phenotype_flag_helpers.R")
orchidee_source_required_script("external_bundle_validation_helpers.R")
orchidee_source_required_script("ratb_hospital_days_helpers.R")
orchidee_source_required_script("external_handoff_helpers.R")
orchidee_source_required_script("ratb_canonical_runtime_helpers.R")

contract <- orchidee_external_contract_v3()

microbiology_observations <- orchidee_handoff_read_table(microbiology_path)
bacteria_mapping <- orchidee_handoff_read_table(bacteria_mapping_path)
sample_type_mapping <- orchidee_handoff_read_table(sample_type_mapping_path)
antibiotic_mapping <- orchidee_handoff_read_table(antibiotic_mapping_path)
unit_mapping <- orchidee_handoff_read_table(unit_mapping_path)
denominator_input <- orchidee_handoff_read_table(denominator_path)

bundle <- orchidee_handoff_build_external_bundle_from_site_inputs(
  microbiology_observations = microbiology_observations,
  bacteria_mapping = bacteria_mapping,
  sample_type_mapping = sample_type_mapping,
  antibiotic_mapping = antibiotic_mapping,
  unit_mapping = unit_mapping,
  incidence_exposure_by_year_um_uf_ta_de_profile = denominator_input
)

run_canonical_runtime_smoke <- function(bundle, label) {
  runtime_inputs <- build_ratb_downstream_scope_from_canonical_inputs(
    sir_wide = bundle$sir_wide,
    sample_scope_reference = bundle$sample_scope_reference,
    denominator_bundle = bundle$denominator_bundle
  )
  runtime_validation <- validate_ratb_canonical_runtime_inputs(
    runtime_inputs = runtime_inputs,
    sir_wide = bundle$sir_wide
  )
  if (!isTRUE(runtime_validation$ok)) {
    stop(
      label,
      " failed the canonical runtime smoke: ",
      paste(runtime_validation$errors, collapse = " | "),
      call. = FALSE
    )
  }
  runtime_validation
}

source_runtime_validation <- run_canonical_runtime_smoke(
  bundle,
  paste0("External bundle ", contract$version)
)
operational_v2_bundle <- if (is.na(operational_v2_output)) {
  NULL
} else {
  project_external_bundle_v3_to_operational_v2(bundle)
}
operational_v2_runtime_validation <- if (is.null(operational_v2_bundle)) {
  NULL
} else {
  run_canonical_runtime_smoke(
    operational_v2_bundle,
    "Operational bundle v2"
  )
}

stage_bundle <- function(
    bundle,
    output_dir,
    contract,
    runtime_validation,
    label
  ) {
  if (!isTRUE(runtime_validation$ok)) {
    stop(label, " has no passing runtime smoke.", call. = FALSE)
  }
  normalized_output <- normalizePath(
    output_dir,
    winslash = "/",
    mustWork = FALSE
  )
  output_parent <- dirname(normalized_output)
  if (!dir.exists(output_parent) && !dir.create(
    output_parent,
    recursive = TRUE,
    showWarnings = FALSE
  )) {
    stop("Cannot create output parent directory: ", output_parent, call. = FALSE)
  }

  staging_dir <- tempfile(
    pattern = paste0(".", basename(normalized_output), "-staging-"),
    tmpdir = output_parent
  )
  if (!dir.create(staging_dir, showWarnings = FALSE)) {
    stop("Cannot create staging directory: ", staging_dir, call. = FALSE)
  }
  keep_staging <- FALSE
  on.exit({
    if (!keep_staging && dir.exists(staging_dir)) {
      unlink(staging_dir, recursive = TRUE, force = TRUE)
    }
  }, add = TRUE)

  for (object_name in bundle_object_names) {
    saveRDS(
      bundle[[object_name]],
      file.path(staging_dir, paste0(object_name, ".rds"))
    )
  }

  report <- validate_external_input_bundle(
    bundle_dir = staging_dir,
    contract = contract
  )
  print_external_input_bundle_validation(report)
  if (!isTRUE(report$ok)) {
    stop(label, " failed strict validation; no output was published.", call. = FALSE)
  }

  keep_staging <- TRUE
  list(
    directory = staging_dir,
    output_dir = normalized_output,
    report = report,
    runtime_validation = runtime_validation,
    contract = contract
  )
}

publish_staged_bundle <- function(
    staged,
    role,
    build_id,
    related_bundle_dir = NA_character_,
    overwrite = FALSE
  ) {
  output_dir <- staged$output_dir
  if (file.exists(output_dir) && !dir.exists(output_dir)) {
    stop("Output must be a directory: ", output_dir, call. = FALSE)
  }
  if (!dir.exists(output_dir) && !dir.create(
    output_dir,
    recursive = TRUE,
    showWarnings = FALSE
  )) {
    stop("Cannot create output directory: ", output_dir, call. = FALSE)
  }

  staged_files <- file.path(staged$directory, bundle_file_names)
  output_files <- file.path(output_dir, bundle_file_names)
  manifest_path <- file.path(output_dir, "build_manifest.txt")
  manifest_tmp_path <- file.path(output_dir, "build_manifest.txt.tmp")

  copied <- file.copy(
    from = staged_files,
    to = output_files,
    overwrite = isTRUE(overwrite),
    copy.mode = TRUE,
    copy.date = TRUE
  )
  if (!all(copied)) {
    stop(
      "Could not publish every validated bundle file to: ",
      output_dir,
      call. = FALSE
    )
  }

  staged_md5 <- unname(tools::md5sum(staged_files))
  output_md5 <- unname(tools::md5sum(output_files))
  if (!identical(staged_md5, output_md5)) {
    stop(
      "Published bundle files do not match their validated staging copies: ",
      output_dir,
      call. = FALSE
    )
  }

  related_line <- if (is.na(related_bundle_dir)) {
    character()
  } else {
    paste0(
      "related_bundle_dir: ",
      normalizePath(related_bundle_dir, winslash = "/", mustWork = FALSE)
    )
  }
  manifest_lines <- c(
    "ORCHIDEE site handoff bundle",
    "status: complete",
    "workflow: site_handoff",
    paste0("build_id: ", build_id),
    paste0("contract_version: ", staged$contract$version),
    paste0("role: ", role),
    paste0(
      "created_at_utc: ",
      format(Sys.time(), tz = "UTC", usetz = TRUE)
    ),
    paste0("bundle_dir: ", output_dir),
    related_line,
    "strict_validation: PASS",
    "runtime_smoke: PASS",
    "[Files]",
    paste0(bundle_file_names, "_md5: ", output_md5)
  )
  if (file.exists(manifest_tmp_path)) {
    stop(
      "Unexpected temporary completion marker appeared in: ",
      output_dir,
      call. = FALSE
    )
  }
  writeLines(manifest_lines, manifest_tmp_path, useBytes = TRUE)
  if (!file.rename(manifest_tmp_path, manifest_path)) {
    stop(
      "Could not finalize build_manifest.txt atomically in: ",
      output_dir,
      call. = FALSE
    )
  }

  manifest_path
}

staged_bundles <- list()
claimed_build_locks <- character()
build_result <- tryCatch({
  staged_source <- stage_bundle(
    bundle = bundle,
    output_dir = output_bundle_dir,
    contract = contract,
    runtime_validation = source_runtime_validation,
    label = paste0("External bundle ", contract$version)
  )
  staged_bundles[[length(staged_bundles) + 1L]] <- staged_source$directory

  staged_operational_v2 <- NULL
  if (!is.na(operational_v2_output)) {
    staged_operational_v2 <- stage_bundle(
      bundle = operational_v2_bundle,
      output_dir = operational_v2_output,
      contract = orchidee_external_contract_v2(),
      runtime_validation = operational_v2_runtime_validation,
      label = "Operational bundle v2"
    )
    staged_bundles[[length(staged_bundles) + 1L]] <-
      staged_operational_v2$directory
  }

  requested_staged_bundles <- Filter(
    Negate(is.null),
    list(staged_source, staged_operational_v2)
  )
  # Claim only at the publication boundary. Staging can be long, and a hard
  # crash should not strand a lock for the whole build; collisions are checked
  # again immediately after the lock is acquired.
  claimed_build_locks <- claim_site_build_locks(requested_output_dirs)
  if (!isTRUE(force) && any(file.exists(requested_output_paths))) {
    stop(
      "Output bundle artifacts appeared while this build was staging. ",
      "No output was replaced; retry with another directory.",
      call. = FALSE
    )
  }
  invalidate_site_bundle_markers(
    requested_staged_bundles,
    force = force
  )
  build_id <- paste0(
    format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"),
    "Z-",
    Sys.getpid(),
    "-",
    sprintf("%06d", sample.int(999999L, 1L))
  )

  source_manifest <- publish_staged_bundle(
    staged = staged_source,
    role = "durable_v3",
    build_id = build_id,
    related_bundle_dir = operational_v2_output,
    overwrite = force
  )
  operational_v2_manifest <- if (is.null(staged_operational_v2)) {
    NA_character_
  } else {
    publish_staged_bundle(
      staged = staged_operational_v2,
      role = "operational_v2",
      build_id = build_id,
      related_bundle_dir = output_bundle_dir,
      overwrite = force
    )
  }

  list(
    report = staged_source$report,
    operational_v2_report = if (is.null(staged_operational_v2)) {
      NULL
    } else {
      staged_operational_v2$report
    },
    source_manifest = source_manifest,
    operational_v2_manifest = operational_v2_manifest
  )
}, finally = {
  for (staging_dir in staged_bundles) {
    if (dir.exists(staging_dir)) {
      unlink(staging_dir, recursive = TRUE, force = TRUE)
    }
  }
  if (length(claimed_build_locks) > 0L) {
    unlink(claimed_build_locks, recursive = TRUE, force = TRUE)
  }
})

report <- build_result$report
operational_v2_report <- build_result$operational_v2_report

if (!is.na(operational_v2_output)) {
  v2_runtime_path <- normalizePath(
    operational_v2_output,
    winslash = "/",
    mustWork = TRUE
  )
  runtime_workspace_path <- normalizePath(
    file.path(dirname(v2_runtime_path), "runtime"),
    winslash = "/",
    mustWork = FALSE
  )
  cat(
    "\nBuild complete.\n",
    "Keep this complete v3 bundle: ",
    normalizePath(output_bundle_dir, winslash = "/", mustWork = TRUE),
    "\n",
    "Use this v2 bundle with the current ORCHIDEE runtime: ",
    v2_runtime_path,
    "\n",
    sep = ""
  )
  if (!suppress_next_steps) {
    cat(
      "Next steps (PowerShell):\n",
      "  $bundle = ", quote_powershell_string(v2_runtime_path), "\n",
      "  $workspace = ",
      quote_powershell_string(runtime_workspace_path),
      "\n",
      "  & .\\scripts\\render_orchidee.ps1 -Rebuild ",
      "-Bundle $bundle -Workspace $workspace\n",
      sep = ""
    )
  }
} else {
  cat(
    "Built validated ORCHIDEE ", contract$version,
    " external bundle: ",
    normalizePath(output_bundle_dir, winslash = "/", mustWork = TRUE),
    "\n",
    sep = ""
  )
  cat(
    "The current notebooks do not read v3 directly. To create their v2 ",
    "input, re-run with --operational-v2-output=<directory> and either a ",
    "new v3 output directory or, after review, --force.\n",
    sep = ""
  )
}
