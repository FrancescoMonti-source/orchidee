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
source("R/site_input_report_publication_helpers.R")

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

# Some classes are about the file rather than its contents -- an extension the
# reader refuses, an .rds holding something that is not a table -- so the case
# has to own the paths instead of taking the six CSVs write_blocks produces.
run_case_paths <- function(label, input_paths) {
  case_index <<- case_index + 1L
  slug <- sprintf("%02d_%s", case_index, label)
  report_dir <- file.path(test_root, paste0(slug, "_report"))
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

# The lock and the staging directory are named per run, so they are recognised by
# prefix rather than by an exact name. Scoping to our own prefix also keeps this
# honest where a test deliberately stands a directory in for an artifact.
orchidee_leftovers <- function(dir) {
  entries <- list.dirs(dir, recursive = FALSE, full.names = FALSE)
  entries[startsWith(entries, ".orchidee")]
}

severity_of <- function(result, block, check) {
  if (is.null(result$findings)) return(NA_character_)
  matched <- result$findings$severity[
    result$findings$block == block & result$findings$check == check
  ]
  if (length(matched) == 0L) NA_character_ else matched[[1L]]
}

# A severity alone does not say a finding is usable. Where a check exists to name
# the offending values, the assertion has to read what it actually named.
detail_of <- function(result, block, check) {
  if (is.null(result$findings)) return(NA_character_)
  matched <- result$findings$detail[
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

# The character form is not the whole value: a Date carries a day number, and a
# fractional one prints as an ordinary date while splitting the row grain in
# two. Where a fixture pins how a date is read, the number is checked as well.
bundle_sample_date_days <- function(result) {
  sir_wide_path <- file.path(
    test_root,
    paste0(result$label, "_bundle"),
    "bundle_v3",
    "sir_wide.rds"
  )
  if (!file.exists(sir_wide_path)) {
    return(NULL)
  }
  sort(unclass(readRDS(sir_wide_path)$DATEPRELEV))
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

# One antibiogram cell, two answers. The builder keeps whichever row comes last,
# so the value published for this isolate depends on the order the site wrote
# its rows in. The two causes are told apart because the correction differs.
contradictory_sir_result <- run_case(
  "contradictory_sir",
  add_observation(clean_blocks, sir_result = "R")
)

# Same cell, but reached through two different local labels that the site's own
# antibiotic_mapping sends to one ORCHIDEE antibiotic. Measured on the Rouen
# bundle, this is the dominant cause by an order of magnitude, and it is not a
# laboratory contradiction: AUGMENTIN CYSTITE and AUGMENTIN AUTRES CONTEXTES are
# the same drug read against different breakpoints, and both answers are right.
collapsed_atb_blocks <- add_observation(
  clean_blocks,
  antibiotic_local = "Cefotaxime cystite",
  sir_result = "R"
)
collapsed_atb_blocks$antibiotic_mapping <- data.frame(
  antibiotic_local = c("Cefotaxime", "Cefotaxime cystite"),
  atb_norm = c("cefotaxime", "cefotaxime"),
  stringsAsFactors = FALSE
)
collapsed_atb_result <- run_case("collapsed_atb_mapping", collapsed_atb_blocks)

# A mixed cell must not let the presence of a second label hide a contradiction
# inside the first one. Here Cefotaxime says S and R while the cystitis label
# says S; only the former defect is established until Cefotaxime is corrected.
mixed_sir_blocks <- add_observation(clean_blocks, sir_result = "R")
mixed_sir_blocks <- add_observation(
  mixed_sir_blocks,
  antibiotic_local = "Cefotaxime cystite",
  sir_result = "S"
)
mixed_sir_blocks$antibiotic_mapping <- data.frame(
  antibiotic_local = c("Cefotaxime", "Cefotaxime cystite"),
  atb_norm = c("cefotaxime", "cefotaxime"),
  stringsAsFactors = FALSE
)
mixed_sir_result <- run_case("mixed_sir_causes", mixed_sir_blocks)

# A value ORCHIDEE cannot read is not a second opinion. This cell holds "S" and
# a word, and the site has one thing to correct, not two.
unreadable_sir_result <- run_case(
  "unreadable_sir_in_shared_cell",
  add_observation(clean_blocks, sir_result = "ZZZ")
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

# A timestamp suffix is tolerated on a date, but nothing downstream validates it:
# as.Date() ignores the suffix whole, so accepting it on shape alone would let
# "2024-03-12 25:99:99" through as a date while the contract promises to refuse
# what it cannot interpret.
impossible_time_observations <- clean_blocks$microbiology_observations
impossible_time_observations$DATEPRELEV <- c(
  "2024-03-12 25:99:99", "2024-04-02 10:00:00"
)
impossible_time_result <- run_case(
  "impossible_timestamp_suffix",
  with_blocks(microbiology_observations = impossible_time_observations)
)

# The same clock has to read the same way wherever it arrives. HEUREPRELEV
# counted digits and left the ranges to strptime, which takes a leap second as
# the next minute and hour 24 as the next midnight, so "09:15:60" was refused
# above as a suffix on a date and accepted here as 09:16. "24:00:00" was worse
# than inconsistent: it parsed to 86400 seconds, the value the difftime branch
# of the same function already refuses as outside a day.
out_of_range_time_observations <- clean_blocks$microbiology_observations
out_of_range_time_observations$HEUREPRELEV <- c("09:15:60", "24:00:00")
out_of_range_time_result <- run_case(
  "out_of_range_time",
  with_blocks(microbiology_observations = out_of_range_time_observations)
)

# The tolerated suffix has a positive half, and it is the half the decision was
# taken for: an HDW export carrying a timestamp in the date column must pass and
# reach the bundle as the day it names, with nothing of the time left in it.
datetime_suffix_observations <- clean_blocks$microbiology_observations
datetime_suffix_observations$DATEPRELEV <- c(
  "2024-03-12 09:15:00", "2024-04-02T23:59:59"
)
datetime_suffix_result <- run_case(
  "tolerated_timestamp_suffix",
  with_blocks(microbiology_observations = datetime_suffix_observations)
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
  wrapper_technical_staging <-
    length(orchidee_leftovers(wrapper_technical_report)) > 0L

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

## Classes reached through the file rather than its contents ------------------

# An extension the reader refuses. The block is dropped, and the other five must
# still be checked -- that is the whole promise of a single pass.
unreadable_paths <- write_blocks(
  file.path(test_root, "unreadable_inputs"),
  clean_blocks
)
unreadable_target <- sub("\\.csv$", ".dat", unreadable_paths[[2L]])
stopifnot(file.rename(unreadable_paths[[2L]], unreadable_target))
unreadable_paths[[2L]] <- unreadable_target
unreadable_result <- run_case_paths("unreadable_input", unreadable_paths)

# An .rds that holds something other than a table.
not_a_table_paths <- write_blocks(
  file.path(test_root, "not_a_table_inputs"),
  clean_blocks
)
not_a_table_target <- sub("\\.csv$", ".rds", not_a_table_paths[[3L]])
saveRDS(c("Urine", "urines"), not_a_table_target)
unlink(not_a_table_paths[[3L]], force = TRUE)
not_a_table_paths[[3L]] <- not_a_table_target
not_a_table_result <- run_case_paths("not_a_table", not_a_table_paths)

# read.table keeps duplicate header names, so the block reaches the contract
# check with two columns of the same name and no way to say which one is meant.
duplicate_column_dir <- file.path(test_root, "duplicate_column_inputs")
duplicate_column_paths <- write_blocks(duplicate_column_dir, clean_blocks)
duplicate_column_lines <- readLines(duplicate_column_paths[[5L]], warn = FALSE)
duplicate_column_lines[[1L]] <- paste0(
  duplicate_column_lines[[1L]], ",\"SEJUF\""
)
duplicate_column_lines[-1L] <- paste0(
  duplicate_column_lines[-1L], ",\"UFDIAG1\""
)
writeLines(duplicate_column_lines, duplicate_column_paths[[5L]])
duplicate_column_result <- run_case_paths(
  "duplicate_columns",
  duplicate_column_paths
)

## Classes reached through the block contents ---------------------------------

# Exactly one diagnostic-scope column is required; two candidates present is as
# unusable as none, because nothing says which one governs the exclusion.
two_scope_observations <- clean_blocks$microbiology_observations
two_scope_observations$diagnostic_scope <- c(TRUE, TRUE)
two_scope_result <- run_case(
  "two_diagnostic_scope_columns",
  with_blocks(microbiology_observations = two_scope_observations)
)

# A scope column that is not readable as a flag.
scope_values_observations <- clean_blocks$microbiology_observations
scope_values_observations$ratb_diagnostic_scope <- c("yes", "maybe")
scope_values_result <- run_case(
  "unreadable_diagnostic_scope",
  with_blocks(microbiology_observations = scope_values_observations)
)

# Every row flagged as screening leaves nothing to build from.
all_screening_observations <- clean_blocks$microbiology_observations
all_screening_observations$ratb_diagnostic_scope <- c(FALSE, FALSE)
all_screening_result <- run_case(
  "no_rows_in_scope",
  with_blocks(microbiology_observations = all_screening_observations)
)

# souche_id belongs to the row grain, but a missing one is audit-only: builder
# and diagnostics both derive a stand-in from sample type and bacterium. That
# merges distinct isolates of one species, which is worth a warning and is not a
# reason to refuse a handoff the build completes.
missing_souche_observations <- clean_blocks$microbiology_observations
missing_souche_observations$souche_id <- c("I1", NA_character_)
missing_souche_result <- run_case(
  "missing_souche_id",
  with_blocks(microbiology_observations = missing_souche_observations)
)

# The same local label mapped to two different canonical values: the builder
# cannot choose, and a first-match rule would silently pick one.
conflicting_mapping_result <- run_case(
  "conflicting_duplicate_keys",
  with_blocks(
    bacteria_mapping = data.frame(
      bacteria_local = c("E. coli", "E. coli"),
      bact_norm = c("escherichia_coli", "klebsiella_pneumoniae"),
      stringsAsFactors = FALSE
    )
  )
)

# unit_mapping with no usable de_domain_ref cannot place a single unit in the
# perimeter.
no_domain_result <- run_case(
  "no_de_domain_ref",
  with_blocks(
    unit_mapping = data.frame(
      SEJUF = "UFDIAG1",
      CODE_TA = "03",
      CODE_DE = "102",
      de_domain_ref = NA_character_,
      stringsAsFactors = FALSE
    )
  )
)

# The profile registry pairs midnight_presence with patient_days. Another unit
# against that profile is not a denominator ORCHIDEE knows how to read.
bad_profile_exposure <-
  clean_blocks$incidence_exposure_by_year_um_uf_ta_de_profile
bad_profile_exposure$exposure_unit <- "admissions"
bad_profile_result <- run_case(
  "unsupported_denominator_profile",
  with_blocks(
    incidence_exposure_by_year_um_uf_ta_de_profile = bad_profile_exposure
  )
)

## Manifest ordering ---------------------------------------------------------
##
## A manifest that survives its own removal would certify the artifacts replaced
## after it, so the run must stop before touching any of them. The writability
## preflight cannot cover this: a handle taken after it passes still blocks
## removal. A read handle reproduces exactly that -- it satisfies the preflight's
## append check and prevents the unlink -- so this is the post-preflight case,
## not a second test of the preflight.
##
## Only the way the condition is induced is Windows-specific, not the behaviour:
## an open handle prevents deletion there, while POSIX unlink() removes the name
## regardless and leaves the content to the descriptor. There is no portable way
## to make one file undeletable inside a directory the run must still write to,
## so the case runs where the operator runs it.
manifest_report_dir <- file.path(test_root, "manifest_report")
manifest_pass <- run_case(
  "manifest_pass",
  clean_blocks,
  report_dir = manifest_report_dir
)
manifest_path <- file.path(manifest_report_dir, "report_manifest.txt")
manifest_removal_blockable <- identical(.Platform$OS.type, "windows")
manifest_blocked <- NULL
manifest_before <- NULL
manifest_after <- NULL
manifest_blocked_staging <- NULL
if (manifest_removal_blockable) {
  manifest_before <- tools::md5sum(
    list.files(manifest_report_dir, full.names = TRUE)
  )
  manifest_handle <- file(manifest_path, open = "rb")
  manifest_blocked <- run_case(
    "manifest_blocked",
    clean_blocks,
    report_dir = manifest_report_dir
  )
  close(manifest_handle)
  manifest_after <- tools::md5sum(
    list.files(manifest_report_dir, full.names = TRUE)
  )
  manifest_blocked_staging <-
    length(orchidee_leftovers(manifest_report_dir)) > 0L
}

## Publication lock -----------------------------------------------------------
##
## The manifest's write-last ordering guards against interruption, not against a
## second run publishing into the same directory. Holding the lock stands in for
## that other run deterministically.
lock_report_dir <- file.path(test_root, "lock_report")
lock_pass <- run_case("lock_pass", clean_blocks, report_dir = lock_report_dir)
# A run that completes owns nothing afterwards: no lock, no staging.
lock_released <- length(orchidee_leftovers(lock_report_dir)) == 0L
lock_before <- tools::md5sum(list.files(lock_report_dir, full.names = TRUE))
lock_path <- file.path(lock_report_dir, ".orchidee_diagnostics.lock")
dir.create(lock_path)
lock_contended <- run_case(
  "lock_contended",
  clean_blocks,
  report_dir = lock_report_dir
)
lock_after <- tools::md5sum(list.files(lock_report_dir, full.names = TRUE))
lock_survived <- dir.exists(lock_path)
# The refused run must not have left a staging directory of its own beside the
# lock it did not touch.
lock_contended_leftovers <- setdiff(
  orchidee_leftovers(lock_report_dir),
  basename(lock_path)
)
unlink(lock_path, recursive = TRUE, force = TRUE)

## Releasing ownership --------------------------------------------------------
##
## Publication releases the lock and then keeps going -- it still has a report to
## print -- so the error handler can fire after the release. A second release
## must do nothing at all: by then another run may hold the lock, and taking it
## away would let a third one into a directory being published into. Reproducing
## that through the CLI would need two interleaved processes and a failure with
## no natural trigger, so the property is asserted on the unit that owns it.
release_dir <- file.path(test_root, "release_unit")
dir.create(release_dir, recursive = TRUE, showWarnings = FALSE)
release_lock <- file.path(release_dir, orchidee_diagnostics_lock_name())
release_state <- orchidee_publication_state()
release_staging <- file.path(release_dir, ".orchidee_staging_unit")
dir.create(release_staging)
orchidee_publication_track_staging(release_state, release_staging)
release_acquired <- orchidee_publication_acquire(release_state, release_dir)
release_owned <- identical(
  orchidee_publication_lock_owner(release_lock),
  release_state$token
)
# What the release reports is the state of the directory: a caller cannot check
# for itself whether a lock it no longer owns is gone.
release_reported <- orchidee_publication_release(release_state)
release_cleared <- !dir.exists(release_lock) && !dir.exists(release_staging)

# Another run takes the lock the moment the first one lets it go.
dir.create(release_lock)
writeLines("another-run", file.path(release_lock, "owner.txt"))
release_second_reported <- orchidee_publication_release(release_state)
release_second_kept <- dir.exists(release_lock)
release_second_owner <- orchidee_publication_lock_owner(release_lock)

# The token makes ownership a property of the lock rather than of what the run
# remembers: a lock this run did not mark is left alone. What is pinned is that
# check, not safety from a lock removed by hand mid-run -- reading the owner and
# removing the directory are two operations, and a swap between them is outside
# what a directory lock can defend. The helper says so, and the operator text
# calls that removal unsupported rather than merely inadvisable.
foreign_state <- orchidee_publication_state()
foreign_state$lock <- release_lock
orchidee_publication_release(foreign_state)
foreign_lock_kept <- dir.exists(release_lock)
unlink(release_lock, recursive = TRUE, force = TRUE)

# dir.create() reports the same failure for a lock that is already there and for
# one that cannot be created at all. Telling an operator to wait for a run that
# does not exist would send them looking in the wrong place.
held_state <- orchidee_publication_state()
dir.create(release_lock)
held_outcome <- orchidee_publication_acquire(held_state, release_dir)
held_untouched <- is.null(held_state$lock)
unlink(release_lock, recursive = TRUE, force = TRUE)
unavailable_target <- file.path(test_root, "not_a_report_dir")
writeLines("not a directory", unavailable_target)
unavailable_outcome <- orchidee_publication_acquire(
  orchidee_publication_state(),
  unavailable_target
)

## Command-line contract ------------------------------------------------------
##
## 0 means a published report with no blocking finding. An invocation that never
## looked at anybody's data must not borrow it, nor borrow 1.
help_result <- run_script("scripts/diagnose_site_inputs.R", "--help")
no_args_result <- run_script("scripts/diagnose_site_inputs.R", character())
short_args_result <- run_script(
  "scripts/diagnose_site_inputs.R",
  clean_result$input_paths
)

## Typed .rds inputs ----------------------------------------------------------
##
## An .rds is as much a site handoff as a CSV, and it arrives pre-typed: the text
## shapes never see it. A difftime outside the day, or a non-finite one, must be
## refused on its own terms rather than trusted for having the right class.
typed_time_dir <- file.path(test_root, "typed_time_inputs")
typed_time_paths <- write_blocks(typed_time_dir, clean_blocks)
typed_observations <- clean_blocks$microbiology_observations
typed_observations$HEUREPRELEV <- as.difftime(
  c(90000, 33300),
  units = "secs"
)
typed_time_target <- file.path(typed_time_dir, "microbiology_observations.rds")
saveRDS(typed_observations, typed_time_target)
unlink(typed_time_paths[[1L]], force = TRUE)
typed_time_paths[[1L]] <- typed_time_target
typed_time_result <- run_case_paths("typed_time_out_of_day", typed_time_paths)

typed_negative_dir <- file.path(test_root, "typed_negative_inputs")
typed_negative_paths <- write_blocks(typed_negative_dir, clean_blocks)
typed_negative_observations <- clean_blocks$microbiology_observations
typed_negative_observations$HEUREPRELEV <- as.difftime(
  c(-3600, 33300),
  units = "secs"
)
typed_negative_target <- file.path(
  typed_negative_dir,
  "microbiology_observations.rds"
)
saveRDS(typed_negative_observations, typed_negative_target)
unlink(typed_negative_paths[[1L]], force = TRUE)
typed_negative_paths[[1L]] <- typed_negative_target
typed_negative_result <- run_case_paths(
  "typed_time_negative",
  typed_negative_paths
)

typed_date_dir <- file.path(test_root, "typed_date_inputs")
typed_date_paths <- write_blocks(typed_date_dir, clean_blocks)
typed_date_observations <- clean_blocks$microbiology_observations
typed_date_observations$DATEPRELEV <- structure(
  c(Inf, 19815),
  class = "Date"
)
typed_date_target <- file.path(typed_date_dir, "microbiology_observations.rds")
saveRDS(typed_date_observations, typed_date_target)
unlink(typed_date_paths[[1L]], force = TRUE)
typed_date_paths[[1L]] <- typed_date_target
typed_date_result <- run_case_paths("typed_date_not_finite", typed_date_paths)

# R lets a Date carry a fractional day, and hides it: 19814.5 and 19814 both
# print as the same date while staying two values in the row grain. A typed
# handoff is the only way one can arrive, and both typed forms take their own
# branch, so both are pinned.
fractional_day_dir <- file.path(test_root, "fractional_day_inputs")
fractional_day_paths <- write_blocks(fractional_day_dir, clean_blocks)
fractional_day_observations <- clean_blocks$microbiology_observations
fractional_day_observations$DATEPRELEV <- structure(
  c(19814.5, 19815),
  class = "Date"
)
fractional_day_target <- file.path(
  fractional_day_dir,
  "microbiology_observations.rds"
)
saveRDS(fractional_day_observations, fractional_day_target)
unlink(fractional_day_paths[[1L]], force = TRUE)
fractional_day_paths[[1L]] <- fractional_day_target
fractional_day_result <- run_case_paths(
  "typed_date_fractional_day",
  fractional_day_paths
)

fractional_numeric_dir <- file.path(test_root, "fractional_numeric_inputs")
fractional_numeric_paths <- write_blocks(fractional_numeric_dir, clean_blocks)
fractional_numeric_observations <- clean_blocks$microbiology_observations
fractional_numeric_observations$DATEPRELEV <- c(19814.5, 19815)
fractional_numeric_target <- file.path(
  fractional_numeric_dir,
  "microbiology_observations.rds"
)
saveRDS(fractional_numeric_observations, fractional_numeric_target)
unlink(fractional_numeric_paths[[1L]], force = TRUE)
fractional_numeric_paths[[1L]] <- fractional_numeric_target
fractional_numeric_result <- run_case_paths(
  "numeric_date_fractional_day",
  fractional_numeric_paths
)

# Half a day is the visible case. A fraction of 1e-9 is the same defect at the
# size where a tolerance would have let it through: still a double of its own,
# still 2024-04-02 on the page, still two rows in the grain. It also pins how
# the value is quoted, since format() shows seven significant digits and would
# report this one as the whole day number it is not.
tiny_fraction_dir <- file.path(test_root, "tiny_fraction_inputs")
tiny_fraction_paths <- write_blocks(tiny_fraction_dir, clean_blocks)
tiny_fraction_observations <- clean_blocks$microbiology_observations
tiny_fraction_observations$DATEPRELEV <- structure(
  c(19815 + 1e-9, 19815),
  class = "Date"
)
tiny_fraction_target <- file.path(
  tiny_fraction_dir,
  "microbiology_observations.rds"
)
saveRDS(tiny_fraction_observations, tiny_fraction_target)
unlink(tiny_fraction_paths[[1L]], force = TRUE)
tiny_fraction_paths[[1L]] <- tiny_fraction_target
tiny_fraction_result <- run_case_paths(
  "typed_date_tiny_fraction",
  tiny_fraction_paths
)

# A fractional minute is not a form anyone writes; the fraction belongs to the
# seconds.
fractional_minute_observations <- clean_blocks$microbiology_observations
fractional_minute_observations$DATEPRELEV <- c(
  "2024-03-12 09:15.123", "2024-04-02"
)
fractional_minute_result <- run_case(
  "fractional_minute_suffix",
  with_blocks(microbiology_observations = fractional_minute_observations)
)

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
# Every published file, not just the summary: the coverage tables and the value
# lists carry local vocabulary, and the claim is about the report as a whole.
report_text <- paste(
  unlist(lapply(
    list.files(broken_result$report_dir, full.names = TRUE),
    readLines,
    warn = FALSE,
    encoding = "UTF-8"
  )),
  collapse = "\n"
)
report_files_scanned <- list.files(broken_result$report_dir)

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
  french_date_result, trailing_time_result, impossible_time_result,
  out_of_range_time_result,
  contradictory_sir_result, collapsed_atb_result, mixed_sir_result,
  unreadable_sir_result,
  unreadable_result, not_a_table_result, duplicate_column_result,
  two_scope_result, scope_values_result, all_screening_result,
  missing_souche_result, conflicting_mapping_result, no_domain_result,
  bad_profile_result, typed_time_result, typed_negative_result,
  typed_date_result, fractional_minute_result, datetime_suffix_result,
  fractional_day_result, fractional_numeric_result, tiny_fraction_result,
  reused_pass, reused_schema_failure, manifest_pass, lock_pass
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

  # A timestamp in the date column is accepted and the time is dropped, which is
  # the reason the suffix is tolerated at all. Checked on the day numbers as
  # well: a leftover fraction would print as the right date anyway.
  identical(datetime_suffix_result$status, 0L),
  identical(
    bundle_sample_dates(datetime_suffix_result),
    c("2024-03-12", "2024-04-02")
  ),
  identical(
    bundle_sample_date_days(datetime_suffix_result),
    round(bundle_sample_date_days(datetime_suffix_result))
  ),
  identical(length(bundle_sample_date_days(datetime_suffix_result)), 2L),

  # A fractional day is refused on both typed branches rather than rounded away.
  identical(fractional_day_result$status, 1L),
  identical(
    severity_of(
      fractional_day_result,
      "microbiology_observations",
      "dateprelev_format"
    ),
    "BLOCKING"
  ),
  # The message quotes the day number: as.character() would show an ordinary
  # date and read as a broken tool.
  any(grepl("day number 19814.5", fractional_day_result$output, fixed = TRUE)),
  identical(fractional_numeric_result$status, 1L),
  identical(
    severity_of(
      fractional_numeric_result,
      "microbiology_observations",
      "dateprelev_format"
    ),
    "BLOCKING"
  ),

  # And a fraction below any tolerance worth writing, since the comparison is
  # exact. The day number is quoted at the precision that distinguishes it from
  # the whole day it prints as; anything shorter reads as a tool refusing an
  # ordinary date.
  identical(tiny_fraction_result$status, 1L),
  identical(
    severity_of(
      tiny_fraction_result,
      "microbiology_observations",
      "dateprelev_format"
    ),
    "BLOCKING"
  ),
  any(grepl(
    "day number 19815.000000001",
    tiny_fraction_result$output,
    fixed = TRUE
  )),

  # A tolerated timestamp suffix is still validated, not counted.
  identical(impossible_time_result$status, 1L),
  identical(
    severity_of(
      impossible_time_result,
      "microbiology_observations",
      "dateprelev_format"
    ),
    "BLOCKING"
  ),

  # A time of day is range-checked wherever it appears, so the two paths cannot
  # disagree about what a valid clock reads. Both values are named: a site
  # correcting an export needs to see which ones, and "24:00:00" in particular
  # used to parse to a quantity the same function refuses as a difftime.
  identical(out_of_range_time_result$status, 1L),
  identical(
    severity_of(
      out_of_range_time_result,
      "microbiology_observations",
      "heureprelev_format"
    ),
    "BLOCKING"
  ),
  grepl(
    "09:15:60",
    detail_of(
      out_of_range_time_result,
      "microbiology_observations",
      "heureprelev_format"
    ),
    fixed = TRUE
  ),
  grepl(
    "24:00:00",
    detail_of(
      out_of_range_time_result,
      "microbiology_observations",
      "heureprelev_format"
    ),
    fixed = TRUE
  ),

  # An antibiogram cell with two answers is refused rather than resolved by row
  # order, and the two causes are kept apart: the fixture that contradicts
  # itself under one label must not be reported as a mapping problem, and the
  # one whose labels collapse must not be reported as a laboratory
  # contradiction. Each names what a site has to look at -- the label, or the
  # group of labels and the antibiotic they landed on.
  identical(contradictory_sir_result$status, 1L),
  identical(
    severity_of(
      contradictory_sir_result,
      "microbiology_observations",
      "contradictory_sir_result"
    ),
    "BLOCKING"
  ),
  grepl(
    "Cefotaxime",
    detail_of(
      contradictory_sir_result,
      "microbiology_observations",
      "contradictory_sir_result"
    ),
    fixed = TRUE
  ),
  is.na(severity_of(
    contradictory_sir_result,
    "microbiology_observations",
    "conflicting_sir_after_atb_mapping"
  )),

  identical(collapsed_atb_result$status, 1L),
  identical(
    severity_of(
      collapsed_atb_result,
      "microbiology_observations",
      "conflicting_sir_after_atb_mapping"
    ),
    "BLOCKING"
  ),
  grepl(
    "Cefotaxime + Cefotaxime cystite -> cefotaxime",
    detail_of(
      collapsed_atb_result,
      "microbiology_observations",
      "conflicting_sir_after_atb_mapping"
    ),
    fixed = TRUE
  ),
  is.na(severity_of(
    collapsed_atb_result,
    "microbiology_observations",
    "contradictory_sir_result"
  )),

  # In a mixed cell, a second label must not hide the contradiction carried by
  # Cefotaxime itself. With only one internally stable label, no independent
  # mapping conflict has yet been established.
  identical(mixed_sir_result$status, 1L),
  identical(
    severity_of(
      mixed_sir_result,
      "microbiology_observations",
      "contradictory_sir_result"
    ),
    "BLOCKING"
  ),
  grepl(
    "Cefotaxime",
    detail_of(
      mixed_sir_result,
      "microbiology_observations",
      "contradictory_sir_result"
    ),
    fixed = TRUE
  ),
  is.na(severity_of(
    mixed_sir_result,
    "microbiology_observations",
    "conflicting_sir_after_atb_mapping"
  )),

  # An unreadable value sharing a cell with a real one is one defect, not two.
  identical(unreadable_sir_result$status, 1L),
  identical(
    severity_of(
      unreadable_sir_result,
      "microbiology_observations",
      "unsupported_sir_values"
    ),
    "BLOCKING"
  ),
  is.na(severity_of(
    unreadable_sir_result,
    "microbiology_observations",
    "contradictory_sir_result"
  )),

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
  # The remaining blocking classes, one fixture each. Together with the cases
  # above this covers every BLOCKING class the command can emit.
  identical(unreadable_result$status, 1L),
  identical(
    severity_of(unreadable_result, "bacteria_mapping", "unreadable_input"),
    "BLOCKING"
  ),
  # A block dropped at the door does not silence the other five.
  identical(
    severity_of(unreadable_result, "microbiology_observations", "rows_read"),
    "INFO"
  ),

  identical(not_a_table_result$status, 1L),
  identical(
    severity_of(not_a_table_result, "sample_type_mapping", "not_a_table"),
    "BLOCKING"
  ),

  identical(duplicate_column_result$status, 1L),
  identical(
    severity_of(duplicate_column_result, "unit_mapping", "duplicate_columns"),
    "BLOCKING"
  ),

  identical(two_scope_result$status, 1L),
  identical(
    severity_of(
      two_scope_result,
      "microbiology_observations",
      "diagnostic_scope_column"
    ),
    "BLOCKING"
  ),

  identical(scope_values_result$status, 1L),
  identical(
    severity_of(
      scope_values_result,
      "microbiology_observations",
      "diagnostic_scope_values"
    ),
    "BLOCKING"
  ),

  identical(all_screening_result$status, 1L),
  identical(
    severity_of(
      all_screening_result,
      "microbiology_observations",
      "no_rows_in_scope"
    ),
    "BLOCKING"
  ),

  # A field the row grain needs and cannot get. The existing missing-bacterium
  # fixture already reached this, unasserted: with no bacteria_local there is no
  # bact_norm to key the row on.
  identical(
    severity_of(
      missing_bacteria_label_result,
      "microbiology_observations",
      "missing_row_grain_value"
    ),
    "BLOCKING"
  ),

  # A missing souche_id is not that case: both sides derive a stand-in, so it
  # stays a warning and the build completes.
  identical(missing_souche_result$status, 0L),
  identical(
    severity_of(
      missing_souche_result,
      "microbiology_observations",
      "isolate_identifier_missing"
    ),
    "WARNING"
  ),

  identical(conflicting_mapping_result$status, 1L),
  identical(
    severity_of(
      conflicting_mapping_result,
      "bacteria_mapping",
      "conflicting_duplicate_keys"
    ),
    "BLOCKING"
  ),

  identical(no_domain_result$status, 1L),
  identical(
    severity_of(no_domain_result, "unit_mapping", "no_de_domain_ref"),
    "BLOCKING"
  ),

  identical(bad_profile_result$status, 1L),
  identical(
    severity_of(
      bad_profile_result,
      "incidence_exposure_by_year_um_uf_ta_de_profile",
      "unsupported_denominator_profile"
    ),
    "BLOCKING"
  ),

  # A second run publishing into the same directory is refused, and refused
  # without touching the report the first one left or the lock it holds.
  identical(lock_pass$status, 0L),
  isTRUE(lock_released),
  identical(lock_contended$status, 2L),
  isTRUE(lock_survived),
  identical(lock_contended_leftovers, character()),
  identical(lock_before, lock_after),
  any(grepl(
    "Another diagnostics run is publishing into",
    lock_contended$output,
    fixed = TRUE
  )),

  # Only an explicit help request may exit 0 without a report behind it.
  identical(help_result$status, 0L),
  identical(no_args_result$status, 2L),
  identical(short_args_result$status, 2L),

  # Typed .rds inputs are validated, not trusted for their class.
  identical(typed_time_result$status, 1L),
  identical(
    severity_of(
      typed_time_result,
      "microbiology_observations",
      "heureprelev_format"
    ),
    "BLOCKING"
  ),
  identical(typed_negative_result$status, 1L),
  identical(
    severity_of(
      typed_negative_result,
      "microbiology_observations",
      "heureprelev_format"
    ),
    "BLOCKING"
  ),
  identical(typed_date_result$status, 1L),
  identical(
    severity_of(
      typed_date_result,
      "microbiology_observations",
      "dateprelev_format"
    ),
    "BLOCKING"
  ),

  # The tolerated timestamp suffix does not extend to a fractional minute.
  identical(fractional_minute_result$status, 1L),
  identical(
    severity_of(
      fractional_minute_result,
      "microbiology_observations",
      "dateprelev_format"
    ),
    "BLOCKING"
  ),

  # Values are attributable to the finding that reported them: block and check
  # do not identify one, because some checks are emitted once per field.
  "finding_id" %in% names(broken_result$findings),
  all(
    read_report_table(broken_result$report_dir, "finding_values.csv")$finding_id
      %in% broken_result$findings$finding_id
  ),

  # Publishing into a directory whose previous report is intact is the ordinary
  # case; the blocked-manifest half is asserted below, where it can be induced.
  identical(manifest_pass$status, 0L),

  # Ownership of the report directory is given up once and for all. The lock is
  # released, and a release that comes after another run has taken it -- the
  # error handler firing behind a successful publication -- leaves it alone.
  identical(release_acquired, "acquired"),
  isTRUE(release_owned),
  isTRUE(release_cleared),
  isTRUE(release_reported),
  identical(release_second_reported, FALSE),
  isTRUE(release_second_kept),
  identical(release_second_owner, "another-run"),
  isTRUE(foreign_lock_kept),
  identical(held_outcome, "held"),
  isTRUE(held_untouched),
  identical(unavailable_outcome, "unavailable"),

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

  # The report carries aggregate counts and local vocabulary, never patients --
  # asserted over every file it publishes, the manifest included.
  "report_manifest.txt" %in% report_files_scanned,
  "finding_values.csv" %in% report_files_scanned,
  length(report_files_scanned) >= 5L,
  !any(vapply(
    patient_identifiers,
    function(identifier) grepl(identifier, report_text, fixed = TRUE),
    logical(1)
  ))
)

# A manifest that cannot be removed stops the run before a single artifact is
# replaced, so the previous report stays whole and its manifest keeps telling the
# truth about it. Asserted where an open handle blocks the removal; the run's
# behaviour is not Windows-specific, the way of inducing it is.
if (manifest_removal_blockable) {
  stopifnot(
    identical(manifest_blocked$status, 2L),
    file.exists(manifest_path),
    identical(manifest_before, manifest_after),
    isFALSE(manifest_blocked_staging),
    any(grepl(
      "manifest of the previous report cannot be removed",
      manifest_blocked$output,
      fixed = TRUE
    )),
    !any(grepl("PASS:", manifest_blocked$output, fixed = TRUE))
  )
}

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
