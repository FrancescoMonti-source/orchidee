#!/usr/bin/env Rscript

# Why: -Diagnose exists because the builder is fail-fast and truncates its
# value lists. Three properties make it useful to a site, and each is asserted
# below:
#   1. a run without BLOCKING findings means the build and strict v3
#      validation actually complete, so PASS is never a false promise;
#   2. one pass reports every blocking class at once;
#   3. a problem that only makes rows audit-only never masquerades as blocking.

source("R/external_bundle_validation_helpers.R")
source("R/ratb_hospital_days_helpers.R")
source("R/external_handoff_helpers.R")

block_names <- names(orchidee_handoff_site_input_spec("v3"))

rscript_path <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)

run_script <- function(script, args) {
  output <- suppressWarnings(system2(
    rscript_path,
    c("--no-save", "--no-restore", shQuote(script), shQuote(args)),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(status = status, output = output)
}

write_blocks <- function(dir, blocks) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (block_name in names(blocks)) {
    utils::write.csv(
      blocks[[block_name]],
      file.path(dir, paste0(block_name, ".csv")),
      row.names = FALSE,
      na = "",
      fileEncoding = "UTF-8"
    )
  }
  file.path(dir, paste0(block_names, ".csv"))
}

read_report_table <- function(report_dir, file_name) {
  path <- file.path(report_dir, file_name)
  if (!file.exists(path)) {
    return(NULL)
  }
  utils::read.csv(path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
}

test_root <- file.path(tempdir(), "orchidee_site_diagnostics")
unlink(test_root, recursive = TRUE, force = TRUE)
dir.create(test_root, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(test_root, recursive = TRUE, force = TRUE), add = TRUE)

case_index <- 0L
run_case <- function(label, blocks, report_dir = NULL) {
  case_index <<- case_index + 1L
  slug <- sprintf("%02d_%s", case_index, label)
  input_paths <- write_blocks(file.path(test_root, paste0(slug, "_inputs")), blocks)
  if (is.null(report_dir)) {
    report_dir <- file.path(test_root, paste0(slug, "_report"))
  }
  result <- run_script(
    "scripts/diagnose_site_inputs.R",
    c(input_paths, report_dir)
  )
  result$label <- label
  result$report_dir <- report_dir
  result$input_paths <- input_paths
  result$findings <- read_report_table(report_dir, "findings.csv")
  result
}

severity_of <- function(result, block, check) {
  if (is.null(result$findings)) return(NA_character_)
  matched <- result$findings$severity[
    result$findings$block == block & result$findings$check == check
  ]
  if (length(matched) == 0L) NA_character_ else matched[[1L]]
}

blocking_checks <- function(result) {
  if (is.null(result$findings)) return(character())
  sort(paste0(
    result$findings$block,
    "/",
    result$findings$check
  )[result$findings$severity == "BLOCKING"])
}

# The soundness invariant: whatever -Diagnose accepts, the operator path must
# accept too. That path is the one build_site.ps1 runs -- v3 plus the
# spares_current projection to operational v2 -- so the v3 build alone would
# leave the projection and v2 validation untested.
assert_pass_implies_buildable <- function(result) {
  if (!identical(result$status, 0L)) {
    return(invisible(NULL))
  }
  bundle_dir <- file.path(test_root, paste0(result$label, "_bundle"))
  build <- run_script(
    "scripts/build_external_bundle_from_site_inputs.R",
    c(
      result$input_paths,
      file.path(bundle_dir, "bundle_v3"),
      "--contract=v3",
      paste0(
        "--operational-v2-output=",
        file.path(bundle_dir, "bundle_v2_operational")
      ),
      "--no-next-steps"
    )
  )
  if (!identical(build$status, 0L)) {
    stop(
      "-Diagnose passed but the operator build failed for fixture '",
      result$label,
      "':\n",
      paste(utils::tail(build$output, 20L), collapse = "\n"),
      call. = FALSE
    )
  }
  invisible(NULL)
}

# A completable build is not the same as a correct one. Where a fixture exists to
# pin how a value is read, the assertion has to reach into the bundle the
# invariant built and look at what was stored.
bundle_sample_dates <- function(result) {
  sir_wide_path <- file.path(
    test_root,
    paste0(result$label, "_bundle"),
    "bundle_v3",
    "sir_wide.rds"
  )
  if (!file.exists(sir_wide_path)) {
    return(NULL)
  }
  sort(as.character(readRDS(sir_wide_path)$DATEPRELEV))
}

## Baseline blocks -----------------------------------------------------------

clean_blocks <- list(
  microbiology_observations = data.frame(
    PATID = c("PDIAG001", "PDIAG002"),
    EVTID = c("SDIAG001", "SDIAG002"),
    ELTID = c("MDIAG001", "MDIAG002"),
    DATEPRELEV = c("2024-03-12", "2024-04-02"),
    HEUREPRELEV = c("09:15", "10:00"),
    SEJUF = c("UFDIAG1", "UFDIAG1"),
    souche_id = c("I1", "I1"),
    bacteria_local = c("E. coli", "E. coli"),
    sample_type_local = c("Urine", "Urine"),
    antibiotic_local = c("Cefotaxime", "Cefotaxime"),
    sir_result = c("S", "R"),
    ratb_diagnostic_scope = c(TRUE, TRUE),
    blse_status_row = c("no_signal", "no_signal"),
    carbapenemase_status_row = c("no_signal", "no_signal"),
    stringsAsFactors = FALSE
  ),
  bacteria_mapping = data.frame(
    bacteria_local = "E. coli",
    bact_norm = "escherichia_coli",
    stringsAsFactors = FALSE
  ),
  sample_type_mapping = data.frame(
    sample_type_local = "Urine",
    naturepvt_norm = "urines",
    stringsAsFactors = FALSE
  ),
  antibiotic_mapping = data.frame(
    antibiotic_local = "Cefotaxime",
    atb_norm = "cefotaxime",
    stringsAsFactors = FALSE
  ),
  unit_mapping = data.frame(
    SEJUF = "UFDIAG1",
    CODE_TA = "03",
    CODE_DE = "102",
    de_domain_ref = "MÉDECINE",
    stringsAsFactors = FALSE
  ),
  incidence_exposure_by_year_um_uf_ta_de_profile = data.frame(
    calendar_year = 2024L,
    SEJUM = "UMDIAG1",
    SEJUF = "UFDIAG1",
    CODE_TA = "03",
    CODE_DE = "102",
    de_domain_ref = "MÉDECINE",
    denominator_profile_id = "midnight_presence",
    exposure_value = 1000L,
    exposure_unit = "patient_days",
    stringsAsFactors = FALSE
  )
)

with_blocks <- function(...) {
  overrides <- list(...)
  blocks <- clean_blocks
  for (name in names(overrides)) {
    blocks[[name]] <- overrides[[name]]
  }
  blocks
}

add_observation <- function(blocks, ...) {
  extra <- list(...)
  row <- blocks$microbiology_observations[1L, , drop = FALSE]
  for (name in names(extra)) {
    row[[name]] <- extra[[name]]
  }
  blocks$microbiology_observations <- rbind(
    blocks$microbiology_observations,
    row
  )
  blocks
}

## Cases ---------------------------------------------------------------------

clean_result <- run_case("clean", clean_blocks)

# One fixture carrying every blocking class at once: the command exists to
# report them together rather than one rebuild at a time.
broken_blocks <- with_blocks(
  microbiology_observations = data.frame(
    PATID = c(
      "PDIAG001", "PDIAG001", "PDIAG002", "PDIAG003", "PDIAG004", "PDIAG005"
    ),
    EVTID = c(
      "SDIAG001", "SDIAG001", "SDIAG002", "SDIAG003", "SDIAG004", NA_character_
    ),
    ELTID = c(
      "MDIAG001", "MDIAG001", "MDIAG002", "MDIAG003", "MDIAG004", "MDIAG005"
    ),
    DATEPRELEV = c(
      "2024-03-12", "2024-03-12", "2024-04-02", "2024-05-20", "2023-06-11",
      "2024-07-01"
    ),
    HEUREPRELEV = c("09:15", "09:15", "10:00", "11:30", "08:00", "08:00"),
    SEJUF = c(
      "UFDIAG1", "UFDIAG1", "UFDIAG1", "UFAUDIT", "UFDIAG1", "UFDIAG2"
    ),
    souche_id = rep("I1", 6L),
    bacteria_local = c(
      "E. coli", "E. coli", "E. coli", "Staphylococcus aureus", "E. coli",
      "E. coli"
    ),
    sample_type_local = c("Urine", "Urine", "Urine", "Pus", "Urine", "Urine"),
    antibiotic_local = c(
      "Cefotaxime", "Amoxicilline", "Cefotaxime", "Oxacilline", "Cefotaxime",
      "Cefotaxime"
    ),
    sir_result = c("R", "S", "S", "R", "S", "ZZZ"),
    ratb_diagnostic_scope = c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE),
    blse_status_row = rep("no_signal", 6L),
    carbapenemase_status_row = rep("no_signal", 6L),
    stringsAsFactors = FALSE
  ),
  sample_type_mapping = data.frame(
    sample_type_local = c("Urine", "Pus"),
    naturepvt_norm = c("urines", NA_character_),
    stringsAsFactors = FALSE
  ),
  antibiotic_mapping = data.frame(
    antibiotic_local = c("Cefotaxime", "Amoxicilline", "Oxacilline"),
    atb_norm = c("cefotaxime", "amoxicilline", "not_a_real_atb"),
    stringsAsFactors = FALSE
  ),
  unit_mapping = data.frame(
    SEJUF = c("UFDIAG1", "UFDIAG1", "UFDIAG2"),
    CODE_TA = c("03", "03", "10"),
    CODE_DE = c("102", "102", "211"),
    de_domain_ref = c("MÉDECINE", "MÉDECINE", "URGENCES"),
    stringsAsFactors = FALSE
  ),
  incidence_exposure_by_year_um_uf_ta_de_profile = data.frame(
    calendar_year = rep(2024L, 4L),
    SEJUM = c("UMDIAG1", "UMDIAG1", "UMDIAG2", "UMDIAG3"),
    SEJUF = c("UFDIAG1", "UFDIAG1", "UFDIAG2", "UFORPHAN"),
    CODE_TA = c("03", "03", "20", "03"),
    CODE_DE = c("102", "102", "211", "102"),
    de_domain_ref = c("MÉDECINE", "MÉDECINE", "URGENCES", "MÉDECINE"),
    denominator_profile_id = rep("midnight_presence", 4L),
    exposure_value = c(1000L, 500L, 300L, 200L),
    exposure_unit = rep("patient_days", 4L),
    stringsAsFactors = FALSE
  )
)
broken_result <- run_case("broken", broken_blocks)

# Values the builder rejects but a plain as.numeric() would accept.
fractional_result <- run_case(
  "fractional_exposure",
  with_blocks(
    incidence_exposure_by_year_um_uf_ta_de_profile = transform(
      clean_blocks$incidence_exposure_by_year_um_uf_ta_de_profile,
      exposure_value = 1.5
    )
  )
)

# An empty exposure_unit must be a finding, not an unresolved comparison that
# aborts the run before the report is written.
missing_unit_result <- run_case(
  "missing_exposure_unit",
  with_blocks(
    incidence_exposure_by_year_um_uf_ta_de_profile = transform(
      clean_blocks$incidence_exposure_by_year_um_uf_ta_de_profile,
      exposure_unit = NA_character_
    )
  )
)

phenotype_typo_result <- run_case(
  "phenotype_typo",
  with_blocks(
    microbiology_observations = transform(
      clean_blocks$microbiology_observations,
      blse_status_row = c("typo", "no_signal")
    )
  )
)

# "unknown" is a recognized status but not an accepted collapsed BLSE value.
phenotype_collapse_result <- run_case(
  "phenotype_collapse",
  with_blocks(
    microbiology_observations = transform(
      clean_blocks$microbiology_observations,
      blse_status_row = c("unknown", "no_signal")
    )
  )
)

# Two rows sharing the ORCHIDEE row grain but disagreeing on SEJUF.
row_grain_result <- run_case(
  "row_grain_conflict",
  add_observation(
    clean_blocks,
    SEJUF = "UFDIAG2",
    antibiotic_local = "Cefotaxime",
    sir_result = "R"
  )
)

# The builder validates a whole mapping table, including rows no observation
# uses.
unused_blank_result <- run_case(
  "unused_blank_target",
  with_blocks(
    bacteria_mapping = data.frame(
      bacteria_local = c("E. coli", "Never observed"),
      bact_norm = c("escherichia_coli", NA_character_),
      stringsAsFactors = FALSE
    )
  )
)

incomplete_unit_result <- run_case(
  "incomplete_unit_mapping",
  with_blocks(
    unit_mapping = transform(
      clean_blocks$unit_mapping,
      CODE_DE = NA_character_
    )
  )
)

# A screening row is dropped before the builder checks key identity, so a
# missing PATID there must not be reported as blocking.
screening_missing_patid_result <- run_case(
  "screening_missing_patid",
  add_observation(
    clean_blocks,
    PATID = NA_character_,
    ELTID = "MDIAG003",
    EVTID = "SDIAG003",
    ratb_diagnostic_scope = FALSE
  )
)

# A schema error in one block must not suppress content checks in the others.
partial_schema_result <- run_case(
  "partial_schema",
  with_blocks(
    unit_mapping = clean_blocks$unit_mapping[, c("SEJUF", "CODE_TA"), drop = FALSE],
    microbiology_observations = transform(
      clean_blocks$microbiology_observations,
      sir_result = c("ZZZ", "R")
    )
  )
)

# A microbiology row with no SEJUF still enters the build but leaves the
# analytic perimeter.
missing_sejuf_result <- run_case(
  "missing_sejuf",
  add_observation(
    clean_blocks,
    SEJUF = NA_character_,
    ELTID = "MDIAG003",
    EVTID = "SDIAG003"
  )
)

# One document carrying two distinct labels must count as one occurrence, not
# two. Both rows share PATID + EVTID + ELTID and differ only by antibiotic, so
# the antibiotic dimension really does see two labels in one occurrence.
multi_label_observations <- clean_blocks$microbiology_observations[
  c(1L, 1L), ,
  drop = FALSE
]
multi_label_observations$antibiotic_local <- c("Cefotaxime", "Ciprofloxacine")
multi_label_observations$sir_result <- c("S", "R")
multi_label_result <- run_case(
  "multi_label_document",
  with_blocks(
    antibiotic_mapping = data.frame(
      antibiotic_local = c("Cefotaxime", "Ciprofloxacine"),
      atb_norm = c("cefotaxime", "ciprofloxacine"),
      stringsAsFactors = FALSE
    ),
    microbiology_observations = multi_label_observations
  )
)
multi_label_mapped <- multi_label_result$findings[
  multi_label_result$findings$block == "antibiotic_mapping" &
    multi_label_result$findings$check == "mapped_local_labels", ,
  drop = FALSE
]
multi_label_coverage <- read_report_table(
  multi_label_result$report_dir,
  "label_coverage.csv"
)
multi_label_antibiotics <- sort(multi_label_coverage$local_label[
  multi_label_coverage$dimension == "antibiotic"
])

# Two local sample types mapped to a blank target collapse onto the same
# canonical value, exactly as the builder collapses them, so the row grain must
# see the conflict rather than keeping the rows apart.
blank_target_collision_observations <- clean_blocks$microbiology_observations[
  c(1L, 1L), ,
  drop = FALSE
]
blank_target_collision_observations$sample_type_local <- c("Pus", "Liquide")
blank_target_collision_observations$HEUREPRELEV <- c("09:15", "11:45")
blank_target_collision_result <- run_case(
  "blank_target_collision",
  with_blocks(
    sample_type_mapping = data.frame(
      sample_type_local = c("Urine", "Pus", "Liquide"),
      naturepvt_norm = c("urines", NA_character_, NA_character_),
      stringsAsFactors = FALSE
    ),
    microbiology_observations = blank_target_collision_observations
  )
)

# One unreadable value must not blank a whole column and hide an independent
# problem on another row.
independent_exposure_result <- run_case(
  "independent_exposure_problems",
  with_blocks(
    incidence_exposure_by_year_um_uf_ta_de_profile = data.frame(
      calendar_year = c(2024L, 2024L),
      SEJUM = c("UMDIAG1", "UMDIAG2"),
      SEJUF = c("UFDIAG1", "UFDIAG1"),
      CODE_TA = c("03", "03"),
      CODE_DE = c("102", "102"),
      de_domain_ref = c("MÉDECINE", "MÉDECINE"),
      denominator_profile_id = rep("midnight_presence", 2L),
      exposure_value = c("1.5", "-1"),
      exposure_unit = rep("patient_days", 2L),
      stringsAsFactors = FALSE
    )
  )
)

# The same holds upstream: an unreadable date must not suppress a row-grain
# conflict on the rows that parse.
independent_date_observations <- clean_blocks$microbiology_observations[
  c(1L, 1L, 1L), ,
  drop = FALSE
]
independent_date_observations$DATEPRELEV <- c(
  "not-a-date", "2024-03-12", "2024-03-12"
)
independent_date_observations$SEJUF <- c("UFDIAG1", "UFDIAG1", "UFDIAG2")
independent_date_result <- run_case(
  "independent_date_problems",
  with_blocks(microbiology_observations = independent_date_observations)
)

# The documented DD/MM/YYYY form has to reach the bundle as the date it denotes.
# Deriving one format from the whole column, as as.Date() does, matched
# "12/03/2024" against %Y/%m/%d as year 12 and never reached the %d/%m/%Y
# branch, so a uniformly French column built a bundle dated in year 12 while
# both -Diagnose and the build exited 0. A PASS that only proves the build
# completes cannot see that, hence the assertions on the stored values.
french_date_observations <- clean_blocks$microbiology_observations
french_date_observations$DATEPRELEV <- c("12/03/2024", "02/04/2024")
french_date_result <- run_case(
  "french_date_format",
  with_blocks(microbiology_observations = french_date_observations)
)

# Anchored shapes are disjoint, so each value is read the same way whatever its
# neighbours look like and a column mixing the documented forms is fine.
mixed_date_observations <- clean_blocks$microbiology_observations
mixed_date_observations$DATEPRELEV <- c("12/03/2024", "2024-03-13")
mixed_date_result <- run_case(
  "mixed_date_formats",
  with_blocks(microbiology_observations = mixed_date_observations)
)

# Trailing characters are the same defect on times: strptime ignores them, so an
# unanchored %H:%M:%S read "09:15:00 (approx)" as 09:15 and dropped the rest.
trailing_time_observations <- clean_blocks$microbiology_observations
trailing_time_observations$HEUREPRELEV <- c("09:15:00 (approx)", "10:00")
trailing_time_result <- run_case(
  "trailing_time_characters",
  with_blocks(microbiology_observations = trailing_time_observations)
)

# Only bacteria_local is required to resolve: bact_norm belongs to the row
# grain. A missing sample type or antibiotic costs analytic value, not the
# build, so blocking them would reject handoffs the builder accepts.
missing_sample_type_label_result <- run_case(
  "missing_sample_type_label",
  add_observation(
    clean_blocks,
    ELTID = "MDIAG003",
    EVTID = "SDIAG003",
    sample_type_local = NA_character_
  )
)
missing_antibiotic_label_result <- run_case(
  "missing_antibiotic_label",
  add_observation(
    clean_blocks,
    ELTID = "MDIAG003",
    EVTID = "SDIAG003",
    antibiotic_local = NA_character_
  )
)
missing_bacteria_label_result <- run_case(
  "missing_bacteria_label",
  add_observation(
    clean_blocks,
    ELTID = "MDIAG003",
    EVTID = "SDIAG003",
    bacteria_local = NA_character_
  )
)

# Resolution state must not be inferred from the value: a site is free to use
# a label that looks like an internal marker.
marker_lookalike_result <- run_case(
  "marker_lookalike_target",
  with_blocks(
    antibiotic_mapping = data.frame(
      antibiotic_local = "Cefotaxime",
      atb_norm = "<unmapped:fake>",
      stringsAsFactors = FALSE
    )
  )
)

# The projection stores the annual denominator with as.integer(), so a year
# beyond that range fails v2 validation after v3 succeeded.
overflow_result <- run_case(
  "annual_exposure_overflow",
  with_blocks(
    incidence_exposure_by_year_um_uf_ta_de_profile = data.frame(
      calendar_year = c(2024L, 2024L),
      SEJUM = c("UMDIAG1", "UMDIAG2"),
      SEJUF = c("UFDIAG1", "UFDIAG1"),
      CODE_TA = c("03", "03"),
      CODE_DE = c("102", "102"),
      de_domain_ref = c("MÉDECINE", "MÉDECINE"),
      denominator_profile_id = rep("midnight_presence", 2L),
      exposure_value = rep(.Machine$integer.max, 2L),
      exposure_unit = rep("patient_days", 2L),
      stringsAsFactors = FALSE
    )
  )
)

# More offending values than the summary shows: every one must still reach the
# site, or the correct-and-rerun loop comes straight back.
many_uf_exposure <- do.call(
  rbind,
  lapply(seq_len(11L), function(index) {
    row <- clean_blocks$incidence_exposure_by_year_um_uf_ta_de_profile
    row$SEJUM <- sprintf("UMEXTRA%02d", index)
    row$SEJUF <- sprintf("UFEXTRA%02d", index)
    row
  })
)
many_unmapped_uf_result <- run_case(
  "many_unmapped_uf",
  with_blocks(
    incidence_exposure_by_year_um_uf_ta_de_profile = rbind(
      clean_blocks$incidence_exposure_by_year_um_uf_ta_de_profile,
      many_uf_exposure
    )
  )
)
many_unmapped_uf_values <- read_report_table(
  many_unmapped_uf_result$report_dir,
  "finding_values.csv"
)
many_unmapped_uf_listed <- sort(many_unmapped_uf_values$value[
  many_unmapped_uf_values$block == "unit_mapping" &
    many_unmapped_uf_values$check == "exposure_uf_not_covered"
])

## Public operator wrapper ---------------------------------------------------
##
## The R CLI is an implementation detail; sites reach -Diagnose through
## build_site.ps1, including the -Output form the operator procedure documents.

wrapper_diagnose <- NULL
wrapper_diagnose_report <- NULL
wrapper_clean <- NULL
wrapper_technical <- NULL
wrapper_technical_report <- NULL
wrapper_preserved_before <- NULL
wrapper_preserved_after <- NULL
wrapper_technical_staging <- NULL
wrapper_unsafe_report <- NULL
if (identical(.Platform$OS.type, "windows")) {
  powershell <- Sys.which("powershell.exe")
  if (!nzchar(powershell)) {
    stop("Windows PowerShell 5.1 is required for the site wrapper test.")
  }
  run_wrapper_diagnose <- function(inputs, output = NULL, report = NULL) {
    wrapper_args <- c(
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      shQuote(
        normalizePath("scripts/build_site.ps1", winslash = "\\", mustWork = TRUE)
      ),
      "-MicrobiologyObservations", shQuote(inputs[[1L]]),
      "-BacteriaMapping", shQuote(inputs[[2L]]),
      "-SampleTypeMapping", shQuote(inputs[[3L]]),
      "-AntibioticMapping", shQuote(inputs[[4L]]),
      "-UnitMapping", shQuote(inputs[[5L]]),
      "-IncidenceExposure", shQuote(inputs[[6L]]),
      if (is.null(output)) character() else c("-Output", shQuote(output)),
      if (is.null(report)) character() else c("-Report", shQuote(report)),
      "-Diagnose"
    )
    lines <- suppressWarnings(system2(
      powershell,
      wrapper_args,
      stdout = TRUE,
      stderr = TRUE
    ))
    status <- attr(lines, "status")
    if (is.null(status)) status <- 0L
    list(status = status, output = lines)
  }

  wrapper_inputs <- write_blocks(
    file.path(test_root, "wrapper inputs"),
    broken_blocks
  )
  wrapper_output <- file.path(test_root, "wrapper output")
  wrapper_diagnose <- run_wrapper_diagnose(wrapper_inputs, wrapper_output)
  wrapper_diagnose_report <- file.path(wrapper_output, "diagnostics")

  # A report artifact that cannot be replaced is a technical failure, not a
  # verdict on the blocks, so the wrapper must surface 2 rather than the code
  # reserved for blocking findings. Standing a directory in the place of one
  # artifact makes it unreplaceable deterministically, with no file locking and
  # no dependence on the account running the test.
  technical_inputs <- write_blocks(
    file.path(test_root, "wrapper technical inputs"),
    clean_blocks
  )
  wrapper_technical_output <- file.path(test_root, "wrapper technical output")
  wrapper_clean <- run_wrapper_diagnose(
    technical_inputs,
    wrapper_technical_output
  )
  wrapper_technical_report <- file.path(
    wrapper_technical_output,
    "diagnostics"
  )
  wrapper_preserved_names <- setdiff(
    list.files(wrapper_technical_report),
    "findings.csv"
  )
  wrapper_preserved_before <- tools::md5sum(
    file.path(wrapper_technical_report, wrapper_preserved_names)
  )
  blocked_artifact <- file.path(wrapper_technical_report, "findings.csv")
  unlink(blocked_artifact, force = TRUE)
  dir.create(blocked_artifact)
  wrapper_technical <- run_wrapper_diagnose(
    technical_inputs,
    wrapper_technical_output
  )
  wrapper_preserved_after <- tools::md5sum(
    file.path(wrapper_technical_report, wrapper_preserved_names)
  )
  wrapper_technical_staging <- dir.exists(
    file.path(wrapper_technical_report, ".orchidee_diagnostics_staging")
  )

  # A setup mistake before R even starts is a technical failure too. The
  # repository root is refused as an output directory, and that refusal used to
  # leave the wrapper at 1 -- the code a caller reads as blocking findings in
  # the site's own blocks.
  wrapper_unsafe_report <- run_wrapper_diagnose(
    technical_inputs,
    report = normalizePath(".", winslash = "\\", mustWork = TRUE)
  )
}

## Stale report artifacts ----------------------------------------------------

shared_report_dir <- file.path(test_root, "shared_report")
reused_pass <- run_case("reuse_pass", clean_blocks, report_dir = shared_report_dir)
stale_before <- file.exists(file.path(shared_report_dir, "label_coverage.csv"))
reused_schema_failure <- run_case(
  "reuse_schema_failure",
  with_blocks(
    microbiology_observations = clean_blocks$microbiology_observations[
      ,
      setdiff(names(clean_blocks$microbiology_observations), "bacteria_local"),
      drop = FALSE
    ]
  ),
  report_dir = shared_report_dir
)
stale_after <- file.exists(file.path(shared_report_dir, "label_coverage.csv"))

## Derived report content ----------------------------------------------------

label_coverage <- read_report_table(broken_result$report_dir, "label_coverage.csv")
unit_coverage <- read_report_table(broken_result$report_dir, "unit_coverage.csv")
year_coverage <- read_report_table(broken_result$report_dir, "year_coverage.csv")
unmapped_bacteria <- label_coverage[
  label_coverage$dimension == "bacteria" & label_coverage$status == "unmapped", ,
  drop = FALSE
]

patient_identifiers <- unique(broken_blocks$microbiology_observations$PATID)
patient_identifiers <- patient_identifiers[!is.na(patient_identifiers)]
report_text <- paste(
  readLines(
    file.path(broken_result$report_dir, "site_input_diagnostics.txt"),
    warn = FALSE,
    encoding = "UTF-8"
  ),
  collapse = "\n"
)

expected_broken_blocking <- sort(c(
  "bacteria_mapping/unmapped_local_labels",
  "antibiotic_mapping/unsupported_atb_norm",
  "unit_mapping/duplicate_sejuf",
  "unit_mapping/exposure_uf_not_covered",
  "incidence_exposure_by_year_um_uf_ta_de_profile/duplicate_grain_rows",
  "incidence_exposure_by_year_um_uf_ta_de_profile/ta_de_disagrees_with_unit_mapping",
  "microbiology_observations/unsupported_sir_values"
))

## Every accepted fixture must really build ----------------------------------

all_results <- list(
  clean_result, broken_result, fractional_result, missing_unit_result,
  phenotype_typo_result, phenotype_collapse_result, row_grain_result,
  unused_blank_result, incomplete_unit_result, screening_missing_patid_result,
  partial_schema_result, missing_sejuf_result, multi_label_result,
  missing_sample_type_label_result, missing_antibiotic_label_result,
  missing_bacteria_label_result, marker_lookalike_result, overflow_result,
  many_unmapped_uf_result, blank_target_collision_result,
  independent_exposure_result, independent_date_result, mixed_date_result,
  french_date_result, trailing_time_result,
  reused_pass, reused_schema_failure
)
invisible(lapply(all_results, assert_pass_implies_buildable))

## Assertions ----------------------------------------------------------------

stopifnot(
  # A contract-satisfying handoff passes with no blocking finding.
  identical(clean_result$status, 0L),
  any(grepl("PASS:", clean_result$output, fixed = TRUE)),
  length(blocking_checks(clean_result)) == 0L,

  # A broken handoff fails, and one pass reports every blocking class.
  identical(broken_result$status, 1L),
  identical(blocking_checks(broken_result), expected_broken_blocking),

  # Audit-only problems stay warnings and never block the build.
  identical(
    severity_of(broken_result, "unit_mapping", "microbiology_uf_not_covered"),
    "WARNING"
  ),
  identical(
    severity_of(
      broken_result,
      "sample_type_mapping",
      "blank_canonical_value_in_use"
    ),
    "WARNING"
  ),
  identical(
    severity_of(
      broken_result,
      "microbiology_observations",
      "screening_propagation"
    ),
    "WARNING"
  ),
  identical(
    severity_of(
      broken_result,
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "year_not_covered"
    ),
    "WARNING"
  ),
  all(broken_result$findings$severity %in% c("BLOCKING", "WARNING", "INFO")),

  # Denominator fields are validated as strictly as the builder validates them.
  identical(fractional_result$status, 1L),
  identical(
    severity_of(
      fractional_result,
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "non_integer_value"
    ),
    "BLOCKING"
  ),
  identical(missing_unit_result$status, 1L),
  !is.null(missing_unit_result$findings),
  identical(
    severity_of(
      missing_unit_result,
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "missing_required_value"
    ),
    "BLOCKING"
  ),

  # Optional phenotype statuses are validated, both per value and collapsed.
  identical(phenotype_typo_result$status, 1L),
  identical(
    severity_of(
      phenotype_typo_result,
      "microbiology_observations",
      "unsupported_phenotype_status"
    ),
    "BLOCKING"
  ),
  identical(phenotype_collapse_result$status, 1L),
  identical(
    severity_of(
      phenotype_collapse_result,
      "microbiology_observations",
      "unsupported_collapsed_phenotype"
    ),
    "BLOCKING"
  ),

  # Conflicts on the canonical row grain are detected.
  identical(row_grain_result$status, 1L),
  identical(
    severity_of(
      row_grain_result,
      "microbiology_observations",
      "conflicting_row_grain_attribute"
    ),
    "BLOCKING"
  ),

  # A blank canonical target blocks even on an unused mapping row.
  identical(unused_blank_result$status, 1L),
  identical(
    severity_of(
      unused_blank_result,
      "bacteria_mapping",
      "missing_canonical_value"
    ),
    "BLOCKING"
  ),

  # An incomplete TA/DE mapping used by exposure blocks instead of silently
  # comparing as equal.
  identical(incomplete_unit_result$status, 1L),
  identical(
    severity_of(
      incomplete_unit_result,
      "unit_mapping",
      "incomplete_ta_de_mapping"
    ),
    "BLOCKING"
  ),

  # A missing identifier on a screening row is not a blocking problem, because
  # the builder drops that row first.
  identical(screening_missing_patid_result$status, 0L),
  is.na(severity_of(
    screening_missing_patid_result,
    "microbiology_observations",
    "missing_document_identity"
  )),

  # A schema error in one block does not suppress content checks elsewhere.
  identical(partial_schema_result$status, 1L),
  identical(
    severity_of(
      partial_schema_result,
      "unit_mapping",
      "missing_required_columns"
    ),
    "BLOCKING"
  ),
  identical(
    severity_of(
      partial_schema_result,
      "microbiology_observations",
      "unsupported_sir_values"
    ),
    "BLOCKING"
  ),

  # A microbiology row without SEJUF is reported with its counts.
  identical(missing_sejuf_result$status, 0L),
  identical(
    severity_of(missing_sejuf_result, "microbiology_observations", "missing_sejuf"),
    "WARNING"
  ),

  # Only a missing bacterium blocks; the other two dimensions cost analytic
  # value, and the invariant above proves the builder accepts them.
  identical(missing_sample_type_label_result$status, 0L),
  identical(
    severity_of(
      missing_sample_type_label_result,
      "microbiology_observations",
      "missing_sample_type_local"
    ),
    "WARNING"
  ),
  identical(missing_antibiotic_label_result$status, 0L),
  identical(
    severity_of(
      missing_antibiotic_label_result,
      "microbiology_observations",
      "missing_antibiotic_local"
    ),
    "WARNING"
  ),
  identical(missing_bacteria_label_result$status, 1L),
  identical(
    severity_of(
      missing_bacteria_label_result,
      "microbiology_observations",
      "missing_bacteria_local"
    ),
    "BLOCKING"
  ),

  # A canonical target that looks like an internal marker is still a target.
  identical(marker_lookalike_result$status, 1L),
  identical(
    severity_of(
      marker_lookalike_result,
      "antibiotic_mapping",
      "unsupported_atb_norm"
    ),
    "BLOCKING"
  ),

  # An annual total the operational v2 denominator cannot hold is blocking,
  # even though v3 alone would accept it.
  identical(overflow_result$status, 1L),
  identical(
    severity_of(
      overflow_result,
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "annual_exposure_overflow"
    ),
    "BLOCKING"
  ),

  # Values beyond the tenth are truncated in the summary but kept in full.
  identical(many_unmapped_uf_result$status, 1L),
  identical(length(many_unmapped_uf_listed), 11L),
  identical(many_unmapped_uf_listed, sprintf("UFEXTRA%02d", 1:11)),
  any(grepl(
    "the complete list is in finding_values.csv",
    many_unmapped_uf_result$output,
    fixed = TRUE
  )),

  # Occurrence totals are distinct counts, not sums of per-label counts. The
  # fixture really carries two distinct antibiotic labels in one occurrence, and
  # it must pass, otherwise the invariant above skips it and the counts are
  # asserted on a handoff nobody proved buildable.
  identical(multi_label_result$status, 0L),
  identical(multi_label_antibiotics, c("Cefotaxime", "Ciprofloxacine")),
  identical(multi_label_mapped$n_rows, 2L),
  identical(multi_label_mapped$n_document_occurrences, 1L),

  # Two local labels mapped to a blank target collapse as the builder collapses
  # them, so the row-grain conflict is visible instead of being hidden.
  identical(blank_target_collision_result$status, 1L),
  identical(
    severity_of(
      blank_target_collision_result,
      "microbiology_observations",
      "conflicting_row_grain_attribute"
    ),
    "BLOCKING"
  ),

  # One unreadable value does not hide an independent problem on another row.
  identical(independent_exposure_result$status, 1L),
  identical(
    severity_of(
      independent_exposure_result,
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "non_integer_value"
    ),
    "BLOCKING"
  ),
  identical(
    severity_of(
      independent_exposure_result,
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "negative_exposure_value"
    ),
    "BLOCKING"
  ),
  identical(independent_date_result$status, 1L),
  identical(
    severity_of(
      independent_date_result,
      "microbiology_observations",
      "dateprelev_format"
    ),
    "BLOCKING"
  ),
  identical(
    severity_of(
      independent_date_result,
      "microbiology_observations",
      "conflicting_row_grain_attribute"
    ),
    "BLOCKING"
  ),

  # The documented French form reaches the bundle as the date it denotes. A
  # completable build was never enough here: the corrupt reading also built.
  identical(french_date_result$status, 0L),
  identical(
    bundle_sample_dates(french_date_result),
    c("2024-03-12", "2024-04-02")
  ),

  # Anchored shapes are disjoint, so a column mixing the documented forms is
  # read value by value and each one keeps its own meaning.
  identical(mixed_date_result$status, 0L),
  identical(
    bundle_sample_dates(mixed_date_result),
    c("2024-03-12", "2024-03-13")
  ),

  # The clean fixture pins the ISO form through the same assertion.
  identical(bundle_sample_dates(clean_result), c("2024-03-12", "2024-04-02")),

  # Trailing characters on a time are reported rather than silently dropped.
  identical(trailing_time_result$status, 1L),
  identical(
    severity_of(
      trailing_time_result,
      "microbiology_observations",
      "heureprelev_format"
    ),
    "BLOCKING"
  ),

  # Coverage counts are reported per label in rows and document occurrences.
  identical(unmapped_bacteria$local_label, "Staphylococcus aureus"),
  identical(unmapped_bacteria$n_rows, 1L),
  identical(unmapped_bacteria$n_document_occurrences, 1L),

  # Screening exclusion is counted on whole document occurrences: the pair of
  # rows sharing MDIAG001 leaves the build although only one is flagged.
  any(grepl(
    "removes 2 rows (1 occurrences)",
    broken_result$output,
    fixed = TRUE
  )),

  # The perimeter distinction is visible per unit rather than only in totals.
  identical(sort(unit_coverage$SEJUF), c("UFDIAG1", "UFDIAG2")),
  identical(
    unit_coverage$included_in_spares_current[unit_coverage$SEJUF == "UFDIAG2"],
    FALSE
  ),

  # The projection total sits next to the profiled total: UFDIAG2 is mapped
  # outside the perimeter and UFORPHAN has no unit row, so only the 1500
  # patient-days of UFDIAG1 survive the spares_current context.
  identical(as.numeric(year_coverage$exposure_total), 2000),
  identical(as.numeric(year_coverage$exposure_in_spares_current), 1500),

  # A reused report directory never mixes fresh findings with stale tables.
  isTRUE(stale_before),
  identical(reused_schema_failure$status, 1L),
  isFALSE(stale_after),

  # A complete report is marked as one, and the marker lists exactly the files
  # published beside it. Without that, a half-replaced directory carries
  # ordinary names with nothing to say it was interrupted.
  file.exists(file.path(clean_result$report_dir, "report_manifest.txt")),
  identical(
    sort(setdiff(list.files(clean_result$report_dir), "report_manifest.txt")),
    sort(intersect(
      readLines(
        file.path(clean_result$report_dir, "report_manifest.txt"),
        warn = FALSE
      ),
      list.files(clean_result$report_dir)
    ))
  ),

  # The report carries aggregate counts and local vocabulary, never patients.
  !any(vapply(
    patient_identifiers,
    function(identifier) grepl(identifier, report_text, fixed = TRUE),
    logical(1)
  ))
)

if (identical(.Platform$OS.type, "windows")) {
  wrapper_findings <- read_report_table(wrapper_diagnose_report, "findings.csv")
  stopifnot(
    # The public operator entry point reaches the diagnostics, reports the same
    # verdict, and honours -Output as the documented workflow requires.
    identical(wrapper_diagnose$status, 1L),
    dir.exists(wrapper_diagnose_report),
    !is.null(wrapper_findings),
    sum(wrapper_findings$severity == "BLOCKING") ==
      length(expected_broken_blocking),
    any(grepl(
      "Correct the blocking findings above",
      wrapper_diagnose$output,
      fixed = TRUE
    )),
    # -Diagnose never builds, so no bundle may appear beside the report.
    !dir.exists(file.path(dirname(wrapper_diagnose_report), "bundle_v3")),

    # A contract-satisfying handoff reaches PASS through the wrapper too.
    identical(wrapper_clean$status, 0L),

    # A run that cannot publish its report exits 2 through the wrapper, says so,
    # and leaves the previous report exactly as it found it.
    identical(wrapper_technical$status, 2L),
    any(grepl(
      "this is not a verdict on the six blocks",
      wrapper_technical$output,
      fixed = TRUE
    )),
    !any(grepl(
      "Correct the blocking findings above",
      wrapper_technical$output,
      fixed = TRUE
    )),
    length(wrapper_preserved_names) >= 3L,
    identical(wrapper_preserved_before, wrapper_preserved_after),
    isFALSE(wrapper_technical_staging),
    !dir.exists(file.path(dirname(wrapper_technical_report), "bundle_v3")),

    # A setup failure before R starts honours the same contract. Status 1 has to
    # mean blocking findings and nothing else.
    identical(wrapper_unsafe_report$status, 2L),
    any(grepl(
      "The diagnostics could not start",
      wrapper_unsafe_report$output,
      fixed = TRUE
    ))
  )
}

cat("PASS: site input diagnostics\n")
