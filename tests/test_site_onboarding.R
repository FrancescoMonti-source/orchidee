#!/usr/bin/env Rscript

source("R/external_bundle_validation_helpers.R")
source("R/ratb_hospital_days_helpers.R")
source("R/external_handoff_helpers.R")
source("tests/python_cli_helpers.R")

capture_error <- function(expr) {
  tryCatch(
    {
      force(expr)
      NA_character_
    },
    error = function(condition) conditionMessage(condition)
  )
}

read_manifest_value <- function(path, key) {
  prefix <- paste0(key, ": ")
  matches <- grep(
    paste0("^", key, ": "),
    readLines(path, warn = FALSE),
    value = TRUE
  )
  if (length(matches) != 1L) return(NA_character_)
  substring(matches[[1L]], nchar(prefix) + 1L)
}

run_r_script <- function(script, args = character(), env = character()) {
  if (length(env) > 0L) {
    if (is.null(names(env)) || any(!nzchar(names(env)))) {
      stop("run_r_script env must be a named character vector.")
    }
    previous_env <- Sys.getenv(names(env), unset = NA_character_)
    on.exit({
      previously_unset <- names(previous_env)[is.na(previous_env)]
      if (length(previously_unset) > 0L) Sys.unsetenv(previously_unset)
      previously_set <- previous_env[!is.na(previous_env)]
      if (length(previously_set) > 0L) {
        do.call(Sys.setenv, as.list(previously_set))
      }
    }, add = TRUE)
    do.call(Sys.setenv, as.list(env))
  }
  rscript <- file.path(
    R.home("bin"),
    if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  )
  output <- suppressWarnings(system2(
    rscript,
    c(
      "--no-save",
      "--no-restore",
      shQuote(script),
      shQuote(args)
    ),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(status = status, output = output)
}

spec <- orchidee_handoff_site_input_spec()
expected_blocks <- c(
  "microbiology_observations",
  "bacteria_mapping",
  "sample_type_mapping",
  "antibiotic_mapping",
  "unit_mapping",
  "incidence_exposure_by_year_um_uf_ta_de_profile"
)
empty_blocks <- lapply(spec, function(block_spec) {
  block <- as.data.frame(
    setNames(
      replicate(
        length(block_spec$template_columns),
        character(),
        simplify = FALSE
      ),
      block_spec$template_columns
    ),
    stringsAsFactors = FALSE,
    optional = TRUE
  )
  block
})

alias_blocks <- empty_blocks
names(alias_blocks$microbiology_observations)[
  names(alias_blocks$microbiology_observations) == "ratb_diagnostic_scope"
] <- "is_diagnostic"
alias_validation <- capture_error(
  orchidee_handoff_validate_site_input_columns(alias_blocks)
)

ambiguous_alias_blocks <- empty_blocks
ambiguous_alias_blocks$microbiology_observations$is_diagnostic <- logical()
ambiguous_alias_error <- capture_error(
  orchidee_handoff_validate_site_input_columns(
    ambiguous_alias_blocks
  )
)

swapped_blocks <- empty_blocks
swapped_blocks$bacteria_mapping <- empty_blocks$sample_type_mapping
swapped_blocks$sample_type_mapping <- empty_blocks$bacteria_mapping
swapped_error <- capture_error(
  orchidee_handoff_validate_site_input_columns(swapped_blocks)
)

duplicate_column_blocks <- empty_blocks
names(duplicate_column_blocks$bacteria_mapping)[[2L]] <-
  names(duplicate_column_blocks$bacteria_mapping)[[1L]]
duplicate_column_error <- capture_error(
  orchidee_handoff_validate_site_input_columns(
    duplicate_column_blocks
  )
)

test_root <- tempfile("orchidee-site-onboarding-")
template_dir <- file.path(test_root, "templates with spaces")
output_dir <- file.path(test_root, "output must stay absent")
dir.create(test_root, recursive = TRUE)
on.exit(unlink(test_root, recursive = TRUE, force = TRUE), add = TRUE)

template_run <- run_r_script(
  "scripts/emit_site_handoff_templates.R",
  template_dir
)
template_paths <- file.path(template_dir, paste0(expected_blocks, ".csv"))
expected_reference_tables <- orchidee_handoff_mapping_reference_tables(".")
reference_dir <- file.path(template_dir, "mapping_reference")
reference_paths <- file.path(
  reference_dir,
  paste0(names(expected_reference_tables), ".csv")
)
names(reference_paths) <- names(expected_reference_tables)
as_character_frame <- function(x) {
  x[] <- lapply(x, as.character)
  x
}
generated_reference_tables <- lapply(reference_paths, function(path) {
  utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    colClasses = "character",
    na.strings = "",
    fileEncoding = "UTF-8"
  )
})
expected_reference_tables_character <- lapply(
  expected_reference_tables,
  as_character_frame
)
reference_readme <- readLines(
  file.path(reference_dir, "README.txt"),
  warn = FALSE,
  encoding = "UTF-8"
)
template_headers <- vapply(
  template_paths,
  function(path) readLines(path, n = 1L, warn = FALSE),
  character(1)
)
expected_headers <- vapply(
  spec,
  function(block_spec) paste(block_spec$template_columns, collapse = ","),
  character(1)
)
example_input_dir <- normalizePath(
  "examples/site_handoff_minimal",
  winslash = "/",
  mustWork = TRUE
)
example_input_paths <- file.path(
  example_input_dir,
  paste0(expected_blocks, ".csv")
)
example_headers <- vapply(
  example_input_paths,
  function(path) readLines(path, n = 1L, warn = FALSE),
  character(1)
)
template_second_run <- run_r_script(
  "scripts/emit_site_handoff_templates.R",
  template_dir
)

environment_run <- run_r_script(
  "scripts/check_site_environment.R",
  template_paths
)

help_scripts <- c(
  "scripts/build_external_bundle_from_site_inputs.R",
  "scripts/build_rouen_external_bundle.R",
  "scripts/compare_operational_v2_gate.R",
  "scripts/smoke_external_runtime_inputs.R",
  "scripts/validate_external_bundle.R",
  "scripts/check_site_environment.R",
  "scripts/emit_site_handoff_templates.R"
)
help_runs <- lapply(help_scripts, run_r_script, args = "--help")
help_text <- vapply(
  help_runs,
  function(result) paste(result$output, collapse = "\n"),
  character(1)
)

wrapper_dry_run <- NULL
wrapper_swapped_run <- NULL
wrapper_dangerous_output_run <- NULL
wrapper_build_run <- NULL
wrapper_repeat_dry_run <- NULL
wrapper_no_force_run <- NULL
wrapper_force_run <- NULL
wrapper_unnecessary_force_run <- NULL
wrapper_incomplete_force_run <- NULL
wrapper_stale_lock_run <- NULL
wrapper_template_run <- NULL
wrapper_unsupported_atb_run <- NULL
render_valid_run <- NULL
render_invalid_run <- NULL
wrapper_template_dir <- file.path(test_root, "wrapper templates with spaces")
wrapper_template_run <- orchidee_run_cli(c(
  "site",
  "--emit-templates",
  wrapper_template_dir
))

run_site_wrapper <- function(
    input_paths = template_paths,
    output_path = output_dir,
    dry_run = TRUE,
    force = FALSE
  ) {
  stopifnot(length(input_paths) == 6L)
  wrapper_args <- c(
    "site",
    "--microbiology-observations", input_paths[[1L]],
    "--bacteria-mapping", input_paths[[2L]],
    "--sample-type-mapping", input_paths[[3L]],
    "--antibiotic-mapping", input_paths[[4L]],
    "--unit-mapping", input_paths[[5L]],
    "--incidence-exposure", input_paths[[6L]],
    "--output", output_path
  )
  if (dry_run) wrapper_args <- c(wrapper_args, "--dry-run")
  if (force) wrapper_args <- c(wrapper_args, "--force")
  orchidee_run_cli(wrapper_args)
}

run_example_wrapper <- function(output_path, force = FALSE) {
  wrapper_args <- c(
    "site",
    "--run-smoke-test",
    "--output",
    output_path
  )
  if (force) wrapper_args <- c(wrapper_args, "--force")
  orchidee_run_cli(wrapper_args)
}

wrapper_dry_run <- run_site_wrapper()
wrapper_unnecessary_force_run <- run_site_wrapper(
  output_path = file.path(test_root, "unnecessary_force_output"),
  force = TRUE
)
swapped_paths <- template_paths
swapped_paths[c(2L, 3L)] <- swapped_paths[c(3L, 2L)]
wrapper_swapped_run <- run_site_wrapper(input_paths = swapped_paths)
wrapper_dangerous_output_run <- run_site_wrapper(
  output_path = normalizePath(".", winslash = "\\", mustWork = TRUE)
)

build_input_paths <- example_input_paths
build_blocks <- lapply(
  build_input_paths,
  orchidee_handoff_read_table
)
names(build_blocks) <- expected_blocks

unsupported_atb_input_dir <- file.path(
  test_root,
  "unsupported atb inputs"
)
dir.create(unsupported_atb_input_dir)
unsupported_atb_blocks <- build_blocks
unsupported_atb_blocks$antibiotic_mapping$atb_norm <-
  "not_an_orchidee_atb"
unsupported_atb_paths <- file.path(
  unsupported_atb_input_dir,
  paste0(names(unsupported_atb_blocks), ".rds")
)
invisible(Map(
  saveRDS,
  unsupported_atb_blocks,
  unsupported_atb_paths
))
wrapper_unsupported_atb_run <- run_site_wrapper(
  input_paths = unsupported_atb_paths,
  output_path = file.path(test_root, "unsupported_atb_output"),
  dry_run = FALSE
)

build_output_dir <- file.path(
  test_root,
  "site_build_output $with'apostrophe"
)
wrapper_build_run <- run_example_wrapper(build_output_dir)
valid_bundle_dir <- file.path(
  build_output_dir,
  "bundle_v2_operational"
)
render_workspace_dir <- file.path(build_output_dir, "runtime")
render_environment <- c(
  ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR = normalizePath(
    valid_bundle_dir,
    winslash = "/",
    mustWork = TRUE
  ),
  ORCHIDEE_EXTERNAL_WORKSPACE_DIR = normalizePath(
    render_workspace_dir,
    winslash = "/",
    mustWork = FALSE
  )
)
render_valid_run <- run_r_script(
  "scripts/check_render_environment.R",
  env = render_environment
)

invalid_bundle_dir <- file.path(test_root, "invalid_v2_bundle")
dir.create(invalid_bundle_dir)
valid_bundle_files <- file.path(
  valid_bundle_dir,
  c(
    "sir_wide.rds",
    "sir_wide_meta.rds",
    "sample_scope_reference.rds",
    "denominator_bundle.rds"
  )
)
stopifnot(all(file.copy(valid_bundle_files, invalid_bundle_dir)))
invalid_meta_path <- file.path(invalid_bundle_dir, "sir_wide_meta.rds")
invalid_meta <- readRDS(invalid_meta_path)
invalid_meta$contract_version <- "v3"
saveRDS(invalid_meta, invalid_meta_path)
invalid_render_environment <- render_environment
invalid_render_environment[["ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR"]] <-
  normalizePath(invalid_bundle_dir, winslash = "/", mustWork = TRUE)
render_invalid_run <- run_r_script(
  "scripts/check_render_environment.R",
  env = invalid_render_environment
)
wrapper_repeat_dry_run <- run_site_wrapper(
  input_paths = build_input_paths,
  output_path = build_output_dir
)
wrapper_no_force_run <- run_site_wrapper(
  input_paths = build_input_paths,
  output_path = build_output_dir,
  dry_run = FALSE
)
v3_keep_path <- file.path(build_output_dir, "bundle_v3", "keep.txt")
v2_keep_path <- file.path(
  build_output_dir,
  "bundle_v2_operational",
  "keep.txt"
)
writeLines("preserve-v3", v3_keep_path)
writeLines("preserve-v2", v2_keep_path)
wrapper_force_run <- run_site_wrapper(
  input_paths = build_input_paths,
  output_path = build_output_dir,
  dry_run = FALSE,
  force = TRUE
)

incomplete_output_dir <- file.path(test_root, "incomplete_site_output")
dir.create(file.path(incomplete_output_dir, "bundle_v3"), recursive = TRUE)
wrapper_incomplete_force_run <- run_site_wrapper(
  input_paths = build_input_paths,
  output_path = incomplete_output_dir,
  dry_run = FALSE,
  force = TRUE
)
stale_lock_output_dir <- file.path(test_root, "stale_lock_output")
stale_lock_path <- paste0(
  file.path(stale_lock_output_dir, "bundle_v3"),
  ".site-build.lock"
)
dir.create(stale_lock_path, recursive = TRUE)
writeLines("pid: test", file.path(stale_lock_path, "owner.txt"))
wrapper_stale_lock_run <- run_site_wrapper(
  input_paths = build_input_paths,
  output_path = stale_lock_output_dir,
  dry_run = FALSE
)
if (!identical(render_valid_run$status, 0L)) {
  stop(
    "Valid site bundle failed render preflight:\n",
    paste(render_valid_run$output, collapse = "\n"),
    call. = FALSE
  )
}

# Why: protects the executable onboarding boundary. A site owns exactly six
# named blocks, the public synthetic example and generated templates share
# executable sources, mapping references expose their authoritative targets,
# help teaches the repository runner, and dry-run must reject a swapped mapping
# without publishing anything.
stopifnot(
  identical(names(spec), expected_blocks),
  all(vapply(
    spec,
    function(block_spec) {
      all(block_spec$required_columns %in% block_spec$template_columns)
    },
    logical(1)
  )),
  is.na(alias_validation),
  grepl(
    "must contain exactly one of these diagnostic_scope columns",
    ambiguous_alias_error,
    fixed = TRUE
  ),
  grepl(
    "bacteria_mapping is missing required columns",
    swapped_error,
    fixed = TRUE
  ),
  grepl(
    "bacteria_mapping contains duplicate column names",
    duplicate_column_error,
    fixed = TRUE
  ),
  identical(template_run$status, 0L),
  all(file.exists(template_paths)),
  all(file.exists(reference_paths)),
  identical(
    generated_reference_tables,
    expected_reference_tables_character
  ),
  any(
    generated_reference_tables$reference_code_ta$CODE_TA == "03" &
      generated_reference_tables$reference_code_ta[[
        "included_in_spares_current"
      ]] == "TRUE"
  ),
  any(
    generated_reference_tables$reference_code_ta$CODE_TA == "10" &
      generated_reference_tables$reference_code_ta[[
        "included_in_spares_current"
      ]] == "FALSE"
  ),
  any(grepl(
    "not a bundle-wide allow-list",
    reference_readme,
    fixed = TRUE
  )),
  all(c(
    "klebsiella_variicola",
    "citrobacter_amalonaticus",
    "citrobacter_freundii",
    "salmonella_spp"
  ) %in% generated_reference_tables$recognized_bact_norm$bact_norm),
  identical(
    generated_reference_tables$recognized_bact_norm$bact_order[
      generated_reference_tables$recognized_bact_norm$bact_norm ==
        "klebsiella_variicola"
    ],
    "Enterobacterales"
  ),
  any(grepl(
    "mapping-reference kit were created",
    template_run$output,
    fixed = TRUE
  )),
  identical(unname(template_headers), unname(expected_headers)),
  all(file.exists(example_input_paths)),
  identical(unname(example_headers), unname(expected_headers)),
  !identical(template_second_run$status, 0L),
  any(grepl(
    "Refusing to overwrite existing site-input templates",
    template_second_run$output,
    fixed = TRUE
  )),
  identical(environment_run$status, 0L),
  any(grepl(
    "six site-input column contracts are available",
    environment_run$output,
    fixed = TRUE
  )),
  !any(grepl(
    "microbiology_observations:",
    environment_run$output,
    fixed = TRUE
  )),
  all(vapply(help_runs, function(result) identical(result$status, 0L), logical(1))),
  all(grepl("scripts/orchidee.py run-r", help_text, fixed = TRUE)),
  !any(grepl("Usage: Rscript", help_text, fixed = TRUE))
)

stopifnot(
  identical(wrapper_dry_run$status, 0L),
  any(grepl(
    "required packages and input columns are available",
    wrapper_dry_run$output,
    fixed = TRUE
  )),
  sum(grepl(
    "microbiology_observations:",
    wrapper_dry_run$output,
    fixed = TRUE
  )) == 1L,
  identical(wrapper_unnecessary_force_run$status, 0L),
  {
    output_line <- grep(
      "^Output:",
      wrapper_unnecessary_force_run$output
    )[[1L]]
    warning_line <- grep(
      "--force is unnecessary because no compatible output exists.",
      wrapper_unnecessary_force_run$output,
      fixed = TRUE
    )[[1L]]
    output_line < warning_line
  },
  !dir.exists(output_dir),
  identical(wrapper_template_run$status, 0L),
  all(file.exists(file.path(
    wrapper_template_dir,
    paste0(expected_blocks, ".csv")
  ))),
  !identical(wrapper_swapped_run$status, 0L),
  any(grepl(
    "bacteria_mapping is missing required columns",
    wrapper_swapped_run$output,
    fixed = TRUE
  )),
  !dir.exists(output_dir),
  !identical(wrapper_dangerous_output_run$status, 0L),
  any(grepl(
    "not a filesystem root or an ancestor of the repository",
    wrapper_dangerous_output_run$output,
    fixed = TRUE
  )),
  identical(wrapper_build_run$status, 0L),
  any(grepl(
    "Mode: installation smoke test on the versioned synthetic fixture",
    wrapper_build_run$output,
    fixed = TRUE
  )),
  file.exists(file.path(
    build_output_dir,
    "bundle_v3",
    "build_manifest.txt"
  )),
  file.exists(file.path(
    build_output_dir,
    "bundle_v2_operational",
    "build_manifest.txt"
  )),
  nzchar(read_manifest_value(
    file.path(build_output_dir, "bundle_v3", "build_manifest.txt"),
    "build_id"
  )),
  identical(
    read_manifest_value(
      file.path(build_output_dir, "bundle_v3", "build_manifest.txt"),
      "build_id"
    ),
    read_manifest_value(
      file.path(
        build_output_dir,
        "bundle_v2_operational",
        "build_manifest.txt"
      ),
      "build_id"
    )
  ),
  any(grepl(
    "operational-v2 runtime smoke are complete",
    wrapper_build_run$output,
    fixed = TRUE
  )),
  sum(grepl(
    "orchidee.py render --rebuild",
    wrapper_build_run$output,
    fixed = TRUE
  )) == 1L,
  any(grepl("--bundle", wrapper_build_run$output, fixed = TRUE)),
  any(grepl(
    "bundle_v2_operational",
    wrapper_build_run$output,
    fixed = TRUE
  )),
  any(grepl("--workspace", wrapper_build_run$output, fixed = TRUE)),
  !any(grepl(
    "Next steps (PowerShell)",
    wrapper_build_run$output,
    fixed = TRUE
  )),
  identical(render_valid_run$status, 0L),
  !identical(render_invalid_run$status, 0L),
  any(grepl(
    "Operational bundle failed strict validation",
    render_invalid_run$output,
    fixed = TRUE
  )),
  identical(wrapper_repeat_dry_run$status, 0L),
  any(grepl(
    "Complete site outputs already exist",
    wrapper_repeat_dry_run$output,
    fixed = TRUE
  )),
  !identical(wrapper_no_force_run$status, 0L),
  any(grepl(
    "Complete site outputs already exist",
    wrapper_no_force_run$output,
    fixed = TRUE
  )),
  identical(wrapper_force_run$status, 0L),
  identical(readLines(v3_keep_path, warn = FALSE), "preserve-v3"),
  identical(readLines(v2_keep_path, warn = FALSE), "preserve-v2"),
  !identical(wrapper_incomplete_force_run$status, 0L),
  any(grepl(
    "incomplete or incompatible site build",
    wrapper_incomplete_force_run$output,
    fixed = TRUE
  )),
  any(grepl(
    "remove the two partial bundle directories",
    wrapper_incomplete_force_run$output,
    fixed = TRUE
  )),
  !identical(wrapper_stale_lock_run$status, 0L),
  any(grepl(
    "Remove this lock only after confirming no build is running",
    wrapper_stale_lock_run$output,
    fixed = TRUE
  )),
  !any(grepl(
    "\\.site-build\\.lock$",
    list.files(test_root, recursive = TRUE, full.names = TRUE)
  )),
  !identical(wrapper_unsupported_atb_run$status, 0L),
  any(grepl(
    "mapping_reference/supported_atb_norm.csv",
    wrapper_unsupported_atb_run$output,
    fixed = TRUE
  ))
)

cat("PASS: site onboarding contract, templates, help, dry-run and build\n")
