# RATB report display helpers extracted from orchidee_ratb_indicators.qmd


ratb_report_helper_env <- new.env(parent = emptyenv())

initialize_ratb_report_helpers <- function(
  download_dir = "downloads",
  datatable_digits = 3L,
  datatable_filter_default = "top",
  datatable_initial_zoom = 0.95,
  datatable_zoom_step = 0.05
) {
  ratb_report_helper_env$config <- list(
    download_dir = download_dir,
    datatable_digits = as.integer(datatable_digits),
    datatable_filter_default = datatable_filter_default,
    datatable_initial_zoom = as.numeric(datatable_initial_zoom),
    datatable_zoom_step = as.numeric(datatable_zoom_step)
  )
  if (!dir.exists(download_dir)) {
    dir.create(download_dir, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(ratb_report_helper_env$config)
}

get_ratb_report_helper_config <- function() {
  cfg <- ratb_report_helper_env$config
  if (is.null(cfg)) {
    initialize_ratb_report_helpers()
    cfg <- ratb_report_helper_env$config
  }
  cfg
}

slugify_filename <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  if (!nzchar(x)) {
    x <- "artifact"
  }
  x
}

build_download_path <- function(file_stem, extension) {
  cfg <- get_ratb_report_helper_config()
  file.path(cfg$download_dir, paste0(slugify_filename(file_stem), ".", extension))
}

lookup_ratb_dataset_label <- function(x, label_map) {
  x_chr <- as.character(x)
  mapped <- unname(label_map[x_chr])
  mapped[is.na(mapped)] <- x_chr[is.na(mapped)]
  mapped
}

emit_html <- function(x) {
  rendered <- htmltools::renderTags(x)
  if (length(rendered$dependencies) > 0L) {
    knitr::knit_meta_add(rendered$dependencies)
  }
  cat(rendered$html, "\n")
  invisible(NULL)
}

show_download_button <- function(path, label) {
  stopifnot(length(path) == length(label))

  if (knitr::is_html_output()) {
    btn_nodes <- Map(
      function(p, lbl) {
        htmltools::tags$a(
          href = p,
          download = basename(p),
          class = "btn btn-outline-primary btn-sm orchidee-download-btn",
          style = paste(
            "display:inline-block;",
            "margin:4px 0 10px 0;",
            "text-decoration:none;"
          ),
          lbl
        )
      },
      path,
      label
    )
    return(do.call(htmltools::tagList, btn_nodes))
  }

  knitr::asis_output(
    paste(
      sprintf("[%s](%s)", label, path),
      collapse = "\n\n"
    )
  )
}

save_plot_pdf <- function(plot_obj, file_stem, width = 14, height = 8) {
  path <- build_download_path(file_stem, "pdf")
  ggplot2::ggsave(
    filename = path,
    plot = plot_obj,
    width = width,
    height = height,
    units = "in"
  )
  path
}

save_plot_png <- function(
  plot_obj,
  file_stem,
  width = 14,
  height = 8,
  dpi = 192
) {
  path <- build_download_path(file_stem, "png")
  ggplot2::ggsave(
    filename = path,
    plot = plot_obj,
    width = width,
    height = height,
    dpi = dpi,
    units = "in"
  )
  path
}

render_plot_png_inline <- function(
  plot_obj,
  file_stem,
  width = 14,
  height = 8,
  dpi = 192
) {
  path <- save_plot_png(
    plot_obj = plot_obj,
    file_stem = file_stem,
    width = width,
    height = height,
    dpi = dpi
  )

  cat(sprintf("![](%s)\n\n", path))
  invisible(path)
}

save_table_xlsx <- function(df, file_stem) {
  path <- build_download_path(file_stem, "xlsx")
  openxlsx::write.xlsx(df, path, overwrite = TRUE)
  path
}

infer_decimal_cols <- function(data, tol = 1e-9) {
  numeric_cols <- names(data)[vapply(data, is.numeric, logical(1))]
  if (length(numeric_cols) == 0L) {
    return(character())
  }

  numeric_cols[vapply(
    data[numeric_cols],
    function(x) {
      vals <- x[is.finite(x)]
      length(vals) > 0L && any(abs(vals - round(vals)) > tol)
    },
    logical(1)
  )]
}

table_counter_env <- new.env(parent = emptyenv())
table_counter_env$n <- 0L

next_table_number <- function() {
  table_counter_env$n <- table_counter_env$n + 1L
  table_counter_env$n
}

resolve_table_title <- function(file_stem, caption = NULL) {
  caption_text <- if (is.null(caption)) {
    ""
  } else {
    trimws(paste(as.character(caption), collapse = " "))
  }
  if (!nzchar(caption_text)) {
    caption_text <- tools::toTitleCase(gsub("_+", " ", file_stem))
  }
  caption_text
}

resolve_table_note_lines <- function(file_stem, caption = NULL) {
  stem <- slugify_filename(file_stem)

  exact_map <- list(
    completion_gate = c(
      "This table summarizes whether each completion strategy passes the core safety invariants.",
      "Read it as a gate table: any failed invariant or unexpected drift should block interpretation of downstream outputs."
    ),
    completion_conflict_consistency = c(
      "This table checks whether the two conflict detectors agree on the same sampled pairs.",
      "Any non-zero mismatch means the helper logic and matrix logic diverge and need investigation."
    ),
    completion_group_kpis = c(
      "This table summarizes fill activity and workload at the completion-group level.",
      "Use it to see whether completion gains are diffuse or concentrated in a small number of groups."
    ),
    completion_top_fills = c(
      "This table lists the groups with the largest numbers of filled cells.",
      "Treat it as a drill-down on where completion changed data most, not as a safety verdict."
    ),
    strategy_impact_summary = c(
      "This table combines safety, fill activity, and row drift versus raw for each completion strategy.",
      "Compare strategies row-wise: the useful ones improve completeness without breaking invariants."
    ),
    strategy_drift_summary = c(
      "This table compares row content between pairs of completion strategies.",
      "Any non-zero drift means strategy choice changes the completed dataset before dedup is even applied."
    ),
    completion_safety_checks = c(
      "This table reports the core structural and value-safety invariants for each completion dataset.",
      "Read the count columns as hard-failure checks: anything non-zero in overwrite, loss, or ZIT fill needs investigation."
    ),
    conflict_consistency = c(
      "This table audits agreement between the helper-based and matrix-based conflict detectors.",
      "A clean table should show zero mismatches across all sampled comparisons."
    ),
    dedup_summary = c(
      "This table summarizes dedup outcomes by dataset and scope.",
      "Use retained rows, multi-class rates, and order-sensitivity together to judge baseline dedup stability."
    ),
    dedup_impact_summary = c(
      "This table compares dedup outputs against the raw baseline.",
      "Representative drift can be meaningful even when retained row counts stay nearly unchanged."
    ),
    partition_drift_summary = c(
      "This table counts episode-level phenotype class changes versus the raw baseline.",
      "Low values mean completion mostly preserves class boundaries; higher values mean class structure is moving."
    ),
    partition_drift_episodes = c(
      "This table lists only the episodes whose class count or partition changed versus raw.",
      "Use it for case review after the summary table tells you where structural drift is occurring."
    ),
    swap_decomposition_summary = c(
      "This table splits representative swaps into partition-driven changes versus same-partition re-ranking.",
      "Dominant same-partition swaps mean completion is mostly changing which row is retained, not which rows belong together."
    ),
    swap_decomposition_episodes = c(
      "This table lists episodes with representative swap activity and whether the underlying partition changed.",
      "Use it to inspect concrete swap cases after locating the main signal in the summary table."
    ),
    c3g_indicator_impact_summary = c(
      "This table summarizes how deduped C3G indicator cells move relative to the raw baseline.",
      "Read count drift and comparable-rate drift together; missing rate deltas usually reflect denominator non-comparability, not errors."
    ),
    c3g_indicator_top_changes = c(
      "This table lists the largest cell-level C3G changes by dataset and scope.",
      "Use it to find which year, type, and species combinations are driving the summary metrics."
    ),
    c3g_indicator_decision_metrics = c(
      "This table condenses the main C3G drift magnitudes across all compared cells.",
      "Use it as a headline diagnostic, then drill into the impact or top-change tables for context."
    ),
    c3g_rate_global_dedup = c(
      "This table reports operational C3G resistance rates after dedup for each dataset.",
      "Compare datasets within the same year and species, and check tested denominators before reading the percentages."
    ),
    c3g_rate_by_type_dedup = c(
      "This table reports operational C3G resistance rates after dedup by sample type.",
      "Use it to compare type-specific patterns, but always read `n_tested` before comparing percentages."
    ),
    c3g_rate_global_drift_vs_raw = c(
      "This table compares operational C3G rates against the raw dedup baseline.",
      "Interpret count and rate deltas together; rate deltas are only meaningful where tested denominators remain comparable."
    ),
    c3g_rate_by_type_drift_vs_raw = c(
      "This table compares by-type operational C3G rates against the raw dedup baseline.",
      "Use it to isolate where type-specific denominator changes are driving the observed rate drift."
    ),
    res_indicator_testing_gain_summary = c(
      "This table compares molecule-level tested-count gains with class-level tested-isolate gains for the same class filters.",
      "Large pairwise gains with small class gains mean completion mostly adds informative molecules to isolates already counted as class-tested."
    ),
    resistance_pairwise_global_compare = c(
      "This table reports the full deduplicated ATB-by-species panel for the selected comparison datasets.",
      "Use the filters to isolate one antibiotic, year, or species before comparing `n_tested`, `n_resistant`, and `%R` across datasets."
    ),
    resistance_pairwise_by_type_compare = c(
      "This table reports the full deduplicated ATB-by-species panel by sample type for the selected comparison datasets.",
      "Filter by type, antibiotic, and species first; the table is intended for targeted lookup rather than whole-table scanning."
    ),
    res_class_availability = c(
      "This table shows which antibiotic classes are supported by the configured molecule universe.",
      "Read it as coverage metadata for downstream indicators rather than as a substantive analytical result; a supported molecule can still be absent from the current extract."
    ),
    ratb_scope_exclusion_summary = c(
      "This table summarizes PMSI status context before the TA/DE analytical perimeter is applied.",
      "Use it to separate rows with PMSI episode structure from unmatched rows; mixed status is audit context, not an exclusion by itself."
    ),
    ratb_scope_join_audit = c(
      "This table audits the `(PATID, EVTID)` join between microbiology rows and PMSI stays.",
      "Focus on missing PMSI matches, mixed statuses, and `evtid_multi_pat` to understand where TA/DE scope assignment can fail or need review."
    ),
    ratb_indicator_spec = c(
      "Cette table présente une synthèse du catalogue des indicateurs publiés dans ce rapport RATB.",
      "Une ligne correspond à une combinaison taxon / métrique / vue / signal ; la colonne `Indicateurs publiés` regroupe les indicateurs couverts par cette même logique de lecture."
    ),
    ratb_indicator_spec_validation = c(
      "This table checks each spec row against the current artifact, dictionaries, and supported rule families.",
      "Treat hard-validation failures as blockers; partial molecule availability can still matter even when execution stays allowed."
    ),
    ratb_indicator_coverage_audit = c(
      "This table turns the spec and validation results into separate publication statuses for annual proportions and annual incidence.",
      "Use `proportion_execution_status`, `incidence_execution_status`, and `coverage_note` to distinguish what is published, what is intentionally not requested for one metric family, and what is truly blocked."
    ),
    ratb_indicator_panel_global = c(
      "This table is the common annual indicator panel after sample-level TA/DE scoping and deduplication.",
      "Compare `n_tested`, `n_resistant`, and `pct_resistant` within the same taxon and year; low denominators need caution."
    ),
    ratb_indicator_panel_by_type = c(
      "This table is the common annual indicator panel split by sample type.",
      "Read `sample_type` and `n_tested` first; percentage differences without comparable denominators are easy to over-interpret."
    ),
    ratb_perimeter_rules = c(
      "This table contains the current rules used to apply the TA/DE perimeter to microbiology samples and PMSI activity.",
      "Read it as the TA/DE policy surface: eligible UFs are defined positively from CONSORES `CODE_TA` and `CODE_DE`, while `PMSISTATUT` remains audit context."
    ),
    ratb_episode_exclusion_summary = c(
      "This table summarizes how PMSI episodes move through the TA/DE denominator perimeter.",
      "Use it to see which exclusion reasons dominate before interpreting incidence denominators."
    ),
    hospital_days_year_summary_provisional = c(
      "This table reports annual eligible hospital nights after applying TA/DE to PMSI activity independently from microbiology rows.",
      "Use it to inspect denominator magnitude by year while the night-count rule remains under review."
    ),
    ratb_numerator_scope_impact_audit = c(
      "This table quantifies how many microbiology rows are retained or removed when the TA/DE analytical perimeter is applied.",
      "Use it as an impact audit for the perimeter correction before interpreting changes in proportions or incidence."
    ),
    ratb_episode_scope_audit = c(
      "This table lists episode-level cases that are excluded, zero-night, or cross-year under the current TA/DE incidence perimeter.",
      "Use it as a review queue for perimeter rules and edge cases rather than as a summary metric."
    ),
    hospital_stay_validation_summary = c(
      "This table summarizes stay-level validation results before annual splitting.",
      "Check missing bounds, negative elapsed time, and cross-year counts here before trusting any hospital-day denominator."
    ),
    hospital_days_year_summary = c(
      "This table compares annual hospital-day aggregates across the candidate counting conventions.",
      "Use it to understand how elapsed-day, rounded-day, and period-split views differ before fixing the final denominator rule."
    ),
    hospital_stays_validation_audit = c(
      "This table lists raw stays that are invalid or cross-year in the generic hospital-day validation layer.",
      "Review these rows when denominator counts look surprising; they are the main edge cases driving validation risk."
    )
  )

  if (!is.null(exact_map[[stem]])) {
    return(exact_map[[stem]])
  }

  if (grepl("_structural_distribution$", stem)) {
    return(c(
      "This table shows how many groups share the same structural profile at the current grain.",
      "Use the frequency and cumulative columns to see whether structure is concentrated in a few simple profiles or spread across a long tail."
    ))
  }

  if (grepl("_structural_outliers$", stem)) {
    return(c(
      "This table lists groups with unusual structural patterns or linkage inconsistencies.",
      "Treat it as a review queue: the point is to inspect unusual cases, not to estimate prevalence from these rows."
    ))
  }

  if (startsWith(stem, "res_indicator_") && grepl("_global$", stem)) {
    return(c(
      "This table reports class-indicator counts and resistance percentages by dataset, year, and species.",
      "Check `n_tested` before comparing `pct_resistant`, so small denominators do not dominate the interpretation."
    ))
  }

  if (startsWith(stem, "res_indicator_") && grepl("_by_type$", stem)) {
    return(c(
      "This table reports class-indicator counts and resistance percentages by dataset, year, type, and species.",
      "Use it to compare type-specific patterns, and read `n_tested` before treating percentage differences as meaningful."
    ))
  }

  if (startsWith(stem, "ratb_pending_")) {
    return(c(
      "This table lists the rows in the current organism section that are not published in at least one metric family.",
      "Use `proportion_execution_status`, `incidence_execution_status`, and `coverage_note` to distinguish an intentional metric restriction from a real support gap."
    ))
  }

  if (startsWith(stem, "ratb_cov_")) {
    return(c(
      "This table summarizes wave-1 coverage status for one reported taxon.",
      "Read it before the taxon-specific panels so you know which indicators are fully supported versus only partially covered."
    ))
  }

  if (startsWith(stem, "ratb_global_")) {
    return(c(
      "Cette table présente, pour un taxon donné, une ligne par jeu comparé, indicateur et année pour les proportions annuelles de résistance en vue globale.",
      "Lire d'abord le nombre testé et le nombre résistant ; le pourcentage de résistance s'interprète ensuite à année et indicateur constants."
    ))
  }

  if (startsWith(stem, "ratb_incidence_global_")) {
    return(c(
      "Cette table présente, pour un taxon donné, une ligne par jeu comparé, indicateur et année pour la densité d'incidence annuelle en vue globale.",
      "La densité publiée correspond au nombre d'isolats résistants pour 1000 nuits d'hospitalisation éligibles ; lire ensemble le nombre de résistants et le nombre de nuits."
    ))
  }

  if (startsWith(stem, "ratb_by_type_")) {
    return(c(
      "Cette table présente, pour un taxon donné, une ligne par jeu comparé, type de prélèvement, indicateur et année pour les proportions annuelles de résistance.",
      "Dans ce rapport, cette vue est volontairement limitée à `hemoculture` et `urines` ; il faut lire le type de prélèvement et le nombre testé avant toute comparaison."
    ))
  }

  character(0)
}

build_table_heading_block <- function(file_stem, caption = NULL) {
  table_number <- next_table_number()
  title_text <- resolve_table_title(file_stem = file_stem, caption = caption)
  note_lines <- resolve_table_note_lines(
    file_stem = file_stem,
    caption = caption
  )
  note_block <- if (length(note_lines) > 0L) {
    htmltools::tags$div(
      class = "orchidee-table-note",
      lapply(note_lines, function(line) htmltools::tags$p(line))
    )
  } else {
    NULL
  }

  htmltools::tags$div(
    class = "orchidee-table-header",
    htmltools::tags$div(
      class = "orchidee-table-title",
      paste0("Table ", table_number, ". ", title_text)
    ),
    note_block
  )
}

figure_counter_env <- new.env(parent = emptyenv())
figure_counter_env$n <- 0L

next_figure_number <- function() {
  figure_counter_env$n <- figure_counter_env$n + 1L
  figure_counter_env$n
}

resolve_plot_note_lines <- function(file_stem, caption = NULL) {
  stem <- slugify_filename(file_stem)

  if (startsWith(stem, "ratb_global_heatmap_")) {
    return(c(
      "Cette figure représente, pour un taxon donné, les proportions annuelles de résistance en vue globale.",
      "Chaque case correspond à un jeu comparé, une année et un indicateur ; la couleur code le pourcentage de résistance et le texte dans la case rappelle la valeur et le nombre testé."
    ))
  }

  if (startsWith(stem, "ratb_incidence_global_heatmap_")) {
    return(c(
      "Cette figure représente, pour un taxon donné, la densité d'incidence annuelle en vue globale.",
      "Chaque case correspond à un jeu comparé, une année et un indicateur ; la couleur code la densité pour 1000 nuits d'hospitalisation et le texte dans la case rappelle la valeur et le nombre d'isolats résistants."
    ))
  }

  if (startsWith(stem, "ratb_by_type_heatmap_")) {
    return(c(
      "Cette figure représente, pour un taxon donné, les proportions annuelles de résistance par type de prélèvement.",
      "Chaque panneau correspond à une combinaison type de prélèvement / jeu comparé ; chaque case correspond ensuite à une année et un indicateur, avec la valeur affichée et le nombre testé."
    ))
  }

  character(0)
}

build_plot_heading_block <- function(file_stem, caption = NULL) {
  figure_number <- next_figure_number()
  title_text <- resolve_table_title(file_stem = file_stem, caption = caption)
  note_lines <- resolve_plot_note_lines(
    file_stem = file_stem,
    caption = caption
  )
  note_block <- if (length(note_lines) > 0L) {
    htmltools::tags$div(
      class = "orchidee-table-note",
      lapply(note_lines, function(line) htmltools::tags$p(line))
    )
  } else {
    NULL
  }

  htmltools::tags$div(
    class = "orchidee-table-header",
    htmltools::tags$div(
      class = "orchidee-table-title",
      paste0("Figure ", figure_number, ". ", title_text)
    ),
    note_block
  )
}

datatable_with_xlsx_button <- function(
  data,
  file_stem,
  caption = NULL,
  rownames = FALSE,
  filter = NULL,
  options = list(),
  format_round_cols = NULL,
  digits = NULL
) {
  cfg <- get_ratb_report_helper_config()
  if (is.null(filter)) {
    filter <- cfg$datatable_filter_default
  }
  if (is.null(digits)) {
    digits <- cfg$datatable_digits
  }

  xlsx_path <- save_table_xlsx(data, file_stem)
  download_btn <- show_download_button(
    xlsx_path,
    paste0("Télécharger en .xlsx (", basename(xlsx_path), ")")
  )

  html_output <- knitr::is_html_output()
  dt_language_defaults <- list(
    search = "Recherche :",
    lengthMenu = "Afficher _MENU_ lignes",
    info = "Affichage de _START_ à _END_ sur _TOTAL_ lignes",
    infoEmpty = "Aucune ligne à afficher",
    infoFiltered = "(filtré à partir de _MAX_ lignes)",
    zeroRecords = "Aucun résultat",
    emptyTable = "Aucune donnée disponible",
    paginate = list(
      first = "Premier",
      previous = "Précédent",
      `next` = "Suivant",
      last = "Dernier"
    )
  )
  if (is.null(options$language)) {
    options$language <- dt_language_defaults
  } else {
    options$language <- modifyList(dt_language_defaults, options$language)
  }

  dt_args <- list(
    data = data,
    caption = if (html_output) NULL else caption,
    rownames = rownames,
    options = options
  )
  if (!(isFALSE(filter) || identical(filter, "none") || is.null(filter))) {
    dt_args$filter <- filter
  }
  dt <- do.call(DT::datatable, dt_args)
  if (html_output && !is.null(dt$x$filterHTML)) {
    dt$x$filterHTML <- gsub(
      'placeholder="All"',
      'placeholder="Filtrer"',
      dt$x$filterHTML,
      fixed = TRUE
    )
  }

  decimal_cols <- infer_decimal_cols(data)
  format_cols <- if (is.null(format_round_cols)) {
    decimal_cols
  } else {
    intersect(format_round_cols, decimal_cols)
  }

  if (length(format_cols) > 0L) {
    dt <- DT::formatRound(dt, columns = format_cols, digits = digits)
  }

  if (html_output) {
    table_heading <- build_table_heading_block(
      file_stem = file_stem,
      caption = caption
    )
    zoom_id <- paste0("dt_zoom_", as.integer(stats::runif(1, 1e8, 9e8)))
    zoom_init <- as.numeric(cfg$datatable_initial_zoom)
    zoom_step <- as.numeric(cfg$datatable_zoom_step)
    zoom_reflow_js <- paste0(
      "var adjust=function(){",
      "if(!(window.jQuery&&jQuery.fn&&jQuery.fn.dataTable))return;",
      "jQuery('#",
      zoom_id,
      "').find('table.dataTable').each(function(){",
      "if(jQuery.fn.dataTable.isDataTable(this)){",
      "var api=jQuery(this).DataTable();",
      "api.columns.adjust();",
      "api.draw(false);",
      "}",
      "});",
      "window.dispatchEvent(new Event('resize'));",
      "};",
      "if(window.requestAnimationFrame){requestAnimationFrame(adjust);}else{setTimeout(adjust,0);}",
      "setTimeout(adjust,120);"
    )

    zoom_controls <- htmltools::tags$div(
      class = "dt-zoom-controls",
      style = paste(
        "display:flex;",
        "gap:6px;",
        "align-items:center;",
        "flex-wrap:wrap;",
        "margin:2px 0 8px 0;"
      ),
      htmltools::tags$span(
        class = "dt-zoom-label",
        "Zoom tableau :"
      ),
      htmltools::tags$button(
        type = "button",
        class = "btn btn-outline-secondary btn-sm",
        "Zoom -",
        onclick = paste0(
          "var el=document.getElementById('",
          zoom_id,
          "');",
          "if(!el)return;",
          "var z=parseFloat(el.dataset.zoom||'",
          sprintf("%.3f", zoom_init),
          "');",
          "z=Math.max(0.75,z-",
          sprintf("%.3f", zoom_step),
          ");",
          "el.dataset.zoom=z.toFixed(3);",
          "el.style.fontSize=(z*100)+'%';",
          zoom_reflow_js
        )
      ),
      htmltools::tags$button(
        type = "button",
        class = "btn btn-outline-secondary btn-sm",
        "Zoom +",
        onclick = paste0(
          "var el=document.getElementById('",
          zoom_id,
          "');",
          "if(!el)return;",
          "var z=parseFloat(el.dataset.zoom||'",
          sprintf("%.3f", zoom_init),
          "');",
          "z=Math.min(1.25,z+",
          sprintf("%.3f", zoom_step),
          ");",
          "el.dataset.zoom=z.toFixed(3);",
          "el.style.fontSize=(z*100)+'%';",
          zoom_reflow_js
        )
      ),
      htmltools::tags$button(
        type = "button",
        class = "btn btn-outline-secondary btn-sm",
        "Réinitialiser",
        onclick = paste0(
          "var el=document.getElementById('",
          zoom_id,
          "');",
          "if(!el)return;",
          "var z=",
          sprintf("%.3f", zoom_init),
          ";",
          "el.dataset.zoom=z.toFixed(3);",
          "el.style.fontSize=(z*100)+'%';",
          zoom_reflow_js
        )
      )
    )

    dt_zoom_wrap <- htmltools::tags$div(
      id = zoom_id,
      class = "dt-zoom-target",
      `data-zoom` = sprintf("%.3f", zoom_init),
      style = paste0("font-size:", sprintf("%.1f", 100 * zoom_init), "%;"),
      dt
    )

    return(htmltools::tags$div(
      class = "orchidee-table-block",
      table_heading,
      download_btn,
      zoom_controls,
      dt_zoom_wrap
    ))
  }

  dt
}

show_audit_table <- function(
  data,
  file_stem,
  caption,
  page_length = 25,
  scroll_y = "500px",
  filter = NULL,
  format_round_cols = NULL,
  digits = NULL
) {
  datatable_with_xlsx_button(
    data = data,
    file_stem = file_stem,
    caption = caption,
    rownames = FALSE,
    filter = filter,
    options = list(
      pageLength = page_length,
      scrollX = TRUE,
      scrollY = scroll_y
    ),
    format_round_cols = format_round_cols,
    digits = digits
  )
}

new_ratb_report_context <- function(
  panel_global,
  panel_incidence_global,
  panel_by_type_report,
  indicator_spec,
  dataset_display_map,
  dataset_levels,
  selected_sample_types,
  report_config
) {
  structure(
    list(
      panel_global = panel_global,
      panel_incidence_global = panel_incidence_global,
      panel_by_type_report = panel_by_type_report,
      indicator_spec = indicator_spec,
      dataset_display_map = dataset_display_map,
      dataset_levels = dataset_levels,
      selected_sample_types = selected_sample_types,
      report_config = report_config
    ),
    class = "ratb_report_context"
  )
}


build_ratb_report_context <- function(
  panel_global,
  panel_incidence_global,
  panel_by_type_report,
  indicator_spec,
  dataset_display_map,
  dataset_levels,
  selected_sample_types,
  report_settings
) {
  if (!is.list(report_settings)) {
    stop("`report_settings` must be a named list.", call. = FALSE)
  }
  report_settings <- as.list(report_settings)
  if (!is.null(report_settings$datatable_digits)) {
    report_settings$datatable_digits <- as.integer(report_settings$datatable_digits)
  }

  new_ratb_report_context(
    panel_global = panel_global,
    panel_incidence_global = panel_incidence_global,
    panel_by_type_report = panel_by_type_report,
    indicator_spec = indicator_spec,
    dataset_display_map = dataset_display_map,
    dataset_levels = dataset_levels,
    selected_sample_types = selected_sample_types,
    report_config = report_settings
  )
}

prepare_ratb_indicator_heatmap <- function(
  df,
  min_n,
  dataset_levels,
  indicator_levels,
  dataset_display_map
) {
  min_n <- as.integer(max(0L, min_n))
  df %>%
    mutate(
      dataset_label = factor(
        lookup_ratb_dataset_label(dataset, dataset_display_map),
        levels = dataset_levels
      ),
      dedup_year = factor(dedup_year, levels = sort(unique(dedup_year))),
      indicator_label = factor(indicator_label, levels = rev(indicator_levels)),
      pct_resistant_plot = if_else(n_tested >= min_n, pct_resistant, NA_real_),
      cell_label = case_when(
        n_tested == 0L ~ "n=0",
        n_tested < min_n ~ paste0("n=", n_tested),
        TRUE ~ paste0(sprintf("%.1f", pct_resistant), "%\n(n=", n_tested, ")")
      )
    )
}

prepare_ratb_incidence_heatmap <- function(
  df,
  dataset_levels,
  indicator_levels,
  dataset_display_map
) {
  df %>%
    mutate(
      dataset_label = factor(
        lookup_ratb_dataset_label(dataset, dataset_display_map),
        levels = dataset_levels
      ),
      dedup_year = factor(dedup_year, levels = sort(unique(dedup_year))),
      indicator_label = factor(indicator_label, levels = rev(indicator_levels)),
      incidence_density_plot = incidence_density_per_1000,
      cell_label = paste0(
        sprintf("%.2f", incidence_density_per_1000),
        "\n(R=",
        n_resistant,
        ")"
      )
    )
}

prepare_ratb_by_type_combined_heatmap <- function(
  df,
  min_n,
  dataset_levels,
  indicator_levels,
  sample_type_levels,
  dataset_display_map
) {
  panel_levels <- as.vector(t(outer(
    sample_type_levels,
    dataset_levels,
    paste,
    sep = "\n"
  )))

  df %>%
    mutate(
      dataset_label = factor(
        lookup_ratb_dataset_label(dataset, dataset_display_map),
        levels = dataset_levels
      ),
      sample_type_label = factor(sample_type, levels = sample_type_levels),
      panel_label = factor(
        paste0(
          as.character(sample_type_label),
          "\n",
          as.character(dataset_label)
        ),
        levels = panel_levels
      ),
      dedup_year = factor(dedup_year, levels = sort(unique(dedup_year))),
      indicator_label = factor(indicator_label, levels = rev(indicator_levels)),
      pct_resistant_plot = if_else(n_tested >= min_n, pct_resistant, NA_real_),
      cell_label = case_when(
        n_tested == 0L ~ "n=0",
        n_tested < min_n ~ paste0("n=", n_tested),
        TRUE ~ paste0(sprintf("%.1f", pct_resistant), "%\n(n=", n_tested, ")")
      )
    )
}

wrap_html_output <- function(x) {
  if (inherits(x, c("htmlwidget", "shiny.tag", "shiny.tag.list"))) {
    return(htmltools::browsable(x))
  }
  x
}

empty_html_output <- function() {
  wrap_html_output(htmltools::tagList())
}

prepare_plot_for_print <- function(plot_obj, width = NULL, height = NULL) {
  if (inherits(plot_obj, "ggplot")) {
    if (!is.null(width)) {
      knitr::opts_current$set(fig.width = width)
    }
    if (!is.null(height)) {
      knitr::opts_current$set(fig.height = height)
    }
    return(plot_obj)
  }

  if (
    is.character(plot_obj) &&
      length(plot_obj) == 1L &&
      grepl("\\.(png|jpg|jpeg|svg)$", plot_obj, ignore.case = TRUE)
  ) {
    return(knitr::include_graphics(plot_obj))
  }

  plot_obj
}

build_fill_scale_gradientn <- function(
  colors,
  limits,
  na_value,
  name,
  breaks,
  labels,
  transform = "identity",
  oob = NULL
) {
  scale_args <- list(
    colors = colors,
    limits = limits,
    na.value = na_value,
    name = name,
    breaks = breaks,
    labels = labels
  )
  if (!is.null(oob)) {
    scale_args$oob <- oob
  }

  if (!is.null(transform) && !identical(transform, "identity")) {
    scale_try <- tryCatch(
      do.call(
        ggplot2::scale_fill_gradientn,
        c(scale_args, list(transform = transform))
      ),
      error = function(e) NULL
    )
    if (!is.null(scale_try)) {
      return(scale_try)
    }
    scale_try <- tryCatch(
      do.call(
        ggplot2::scale_fill_gradientn,
        c(scale_args, list(trans = transform))
      ),
      error = function(e) NULL
    )
    if (!is.null(scale_try)) {
      return(scale_try)
    }
    warning(
      "Could not apply fill transform; falling back to identity scale.",
      call. = FALSE
    )
  }

  do.call(ggplot2::scale_fill_gradientn, scale_args)
}

build_family_indicator_note <- function(taxon, indicator_spec) {
  has_family_indicator <- indicator_spec %>%
    filter(report_taxon_label == taxon, indicator_kind == "class_any_r") %>%
    nrow() >
    0L

  base_note <- "\nDans chaque case, le n affiché est le dénominateur de la proportion : il correspond au nombre d'isolats testés pour l'indicateur considéré."

  if (!has_family_indicator) {
    return(base_note)
  }

  paste0(
    base_note,
    " Pour un groupe d'antibiotiques, un isolat est compté dans ce n dès qu'au moins une molécule du groupe est renseignée en S ou R. ",
    "Il ne s'agit donc pas de la somme des n des molécules individuelles. ",
    "Une molécule définie dans le groupe mais absente de l'extrait actuel est traitée comme non renseignée, pas comme exclue du groupe."
  )
}


build_ratb_global_output_block <- function(taxon, context) {
  panel_global <- context$panel_global
  indicator_spec <- context$indicator_spec
  dataset_display_map <- context$dataset_display_map
  dataset_levels <- context$dataset_levels
  report_config <- context$report_config
  global_tbl <- panel_global %>%
    filter(report_taxon_label == taxon) %>%
    mutate(
      dataset = lookup_ratb_dataset_label(dataset, dataset_display_map)
    ) %>%
    arrange(match(dataset, dataset_levels), dedup_year, indicator_label)

  if (nrow(global_tbl) == 0L) {
    note <- wrap_html_output(htmltools::tags$p(
      "Aucune sortie de proportion globale n'est disponible pour ce taxon."
    ))
    return(list(
      table = note,
      plot = empty_html_output(),
      plot_width = NULL,
      plot_height = NULL,
      pdf_button = empty_html_output()
    ))
  }

  indicator_levels <- indicator_spec %>%
    filter(report_taxon_label == taxon) %>%
    arrange(display_order) %>%
    pull(indicator_label) %>%
    unique()

  table_obj <- wrap_html_output(show_audit_table(
    data = global_tbl %>%
      select(
        dataset,
        indicator_label,
        dedup_year,
        n_isolates,
        n_tested,
        n_resistant,
        n_o,
        pct_resistant
      ) %>%
      rename(
        `Jeu comparé` = dataset,
        `Indicateur` = indicator_label,
        `Année` = dedup_year,
        `N isolats` = n_isolates,
        `N testés` = n_tested,
        `N résistants` = n_resistant,
        `N non testés` = n_o,
        `% résistants parmi les testés` = pct_resistant
      ),
    file_stem = paste0("ratb_global_", slugify_filename(taxon)),
    caption = paste0(
      taxon,
      " - tableau annuel des proportions de résistance (vue globale)"
    ),
    page_length = 20,
    scroll_y = "320px",
    digits = report_config$datatable_digits
  ))

  global_heatmap <- panel_global %>%
    filter(report_taxon_label == taxon) %>%
    prepare_ratb_indicator_heatmap(
      min_n = report_config$indicator_min_n,
      dataset_levels = dataset_levels,
      indicator_levels = indicator_levels,
      dataset_display_map = dataset_display_map
    )

  global_height_in <- max(
    report_config$global_height_min_in,
    length(indicator_levels) *
      report_config$global_height_per_indicator_in +
      report_config$global_height_padding_in
  )
  global_width_in <- max(
    report_config$global_width_min_in,
    length(dataset_levels) * report_config$global_width_per_dataset_in
  )

  p_global <- ggplot(
    global_heatmap,
    aes(x = dedup_year, y = indicator_label, fill = pct_resistant_plot)
  ) +
    geom_tile(color = "white", linewidth = 0.2) +
    geom_text(
      aes(label = cell_label),
      size = report_config$label_size_global,
      lineheight = 0.9
    ) +
    facet_grid(cols = vars(dataset_label)) +
    build_fill_scale_gradientn(
      colors = report_config$fill_palette_proportion,
      limits = c(0, 100),
      na_value = "grey90",
      name = "%R",
      breaks = report_config$fill_breaks_proportion,
      labels = \(x) paste0(x, "%"),
      transform = report_config$fill_transform
    ) +
    labs(
      title = paste0(
        taxon,
        " - proportions annuelles de résistance (vue globale)"
      ),
      subtitle = paste0(
        "Proportions annuelles sur le périmètre analytique RATB hospitalisation. Seuil n_tested = ",
        report_config$indicator_min_n,
        build_family_indicator_note(taxon, indicator_spec)
      ),
      x = "Année",
      y = NULL
    ) +
    theme_minimal() +
    theme(
      panel.grid = element_blank(),
      axis.text.x = element_text(size = report_config$axis_text_x_size),
      axis.text.y = element_text(size = report_config$axis_text_y_size),
      strip.text.x = element_text(
        size = report_config$strip_text_size,
        face = "bold"
      )
    )

  global_png_path <- save_plot_png(
    p_global,
    paste0("ratb_global_heatmap_", slugify_filename(taxon)),
    width = global_width_in,
    height = global_height_in
  )

  global_pdf_path <- save_plot_pdf(
    p_global,
    paste0("ratb_global_heatmap_", slugify_filename(taxon)),
    width = global_width_in,
    height = global_height_in
  )

  list(
    table = table_obj,
    plot_heading = wrap_html_output(build_plot_heading_block(
      file_stem = paste0("ratb_global_heatmap_", slugify_filename(taxon)),
      caption = paste0(
        taxon,
        " - carte thermique annuelle des proportions de résistance (vue globale)"
      )
    )),
    plot = global_png_path,
    plot_width = global_width_in,
    plot_height = global_height_in,
    pdf_button = wrap_html_output(show_download_button(
      global_pdf_path,
      paste0(
        "Télécharger la carte thermique PDF des proportions globales pour ",
        taxon,
        " (",
        basename(global_pdf_path),
        ")"
      )
    ))
  )
}

build_ratb_global_incidence_output_block <- function(taxon, context) {
  panel_incidence_global <- context$panel_incidence_global
  indicator_spec <- context$indicator_spec
  dataset_display_map <- context$dataset_display_map
  dataset_levels <- context$dataset_levels
  report_config <- context$report_config
  incidence_tbl <- panel_incidence_global %>%
    filter(report_taxon_label == taxon) %>%
    mutate(
      dataset = lookup_ratb_dataset_label(dataset, dataset_display_map)
    ) %>%
    arrange(match(dataset, dataset_levels), dedup_year, indicator_label)

  if (nrow(incidence_tbl) == 0L) {
    note <- wrap_html_output(htmltools::tags$p(
      "Aucune sortie globale de densité d'incidence n'est disponible pour ce taxon."
    ))
    return(list(
      table = note,
      plot = empty_html_output(),
      plot_width = NULL,
      plot_height = NULL,
      pdf_button = empty_html_output()
    ))
  }

  indicator_levels <- indicator_spec %>%
    filter(report_taxon_label == taxon) %>%
    arrange(display_order) %>%
    pull(indicator_label) %>%
    unique()

  table_obj <- wrap_html_output(show_audit_table(
    data = incidence_tbl %>%
      select(
        dataset,
        indicator_label,
        dedup_year,
        n_isolates,
        n_resistant,
        hospital_nights,
        incidence_density_per_1000
      ) %>%
      rename(
        `Jeu comparé` = dataset,
        `Indicateur` = indicator_label,
        `Année` = dedup_year,
        `N isolats` = n_isolates,
        `N résistants` = n_resistant,
        `N nuits hospitalisation` = hospital_nights,
        `Densité pour 1000 nuits` = incidence_density_per_1000
      ),
    file_stem = paste0("ratb_incidence_global_", slugify_filename(taxon)),
    caption = paste0(
      taxon,
      " - tableau annuel de densité d'incidence (vue globale)"
    ),
    page_length = 20,
    scroll_y = "320px",
    digits = report_config$datatable_digits
  ))

  incidence_heatmap <- panel_incidence_global %>%
    filter(report_taxon_label == taxon) %>%
    prepare_ratb_incidence_heatmap(
      dataset_levels = dataset_levels,
      indicator_levels = indicator_levels,
      dataset_display_map = dataset_display_map
    )

  incidence_fill_limit <- report_config$incidence_fill_limit

  incidence_denominator_note <- incidence_tbl %>%
    distinct(dedup_year, hospital_nights) %>%
    arrange(dedup_year) %>%
    transmute(
      label = paste0(
        dedup_year,
        " = ",
        format(hospital_nights, big.mark = " ", scientific = FALSE, trim = TRUE)
      )
    ) %>%
    pull(label) %>%
    paste(collapse = " ; ")

  incidence_height_in <- max(
    report_config$incidence_height_min_in,
    length(indicator_levels) *
      report_config$incidence_height_per_indicator_in +
      report_config$incidence_height_padding_in
  )
  incidence_width_in <- max(
    report_config$incidence_width_min_in,
    length(dataset_levels) * report_config$incidence_width_per_dataset_in
  )

  p_incidence <- ggplot(
    incidence_heatmap,
    aes(x = dedup_year, y = indicator_label, fill = incidence_density_plot)
  ) +
    geom_tile(color = "white", linewidth = 0.2) +
    geom_text(
      aes(label = cell_label),
      size = report_config$label_size_incidence,
      lineheight = 0.9
    ) +
    facet_grid(cols = vars(dataset_label)) +
    build_fill_scale_gradientn(
      colors = report_config$fill_palette_incidence,
      limits = c(0, incidence_fill_limit),
      na_value = "grey90",
      name = "Densité\n/1000 nuits",
      breaks = report_config$fill_breaks_incidence,
      labels = \(x) sprintf("%.2f", x),
      transform = report_config$fill_transform,
      oob = scales::squish
    ) +
    labs(
      title = paste0(taxon, " - densité d'incidence annuelle (vue globale)"),
      subtitle = paste0(
        "Densité d'incidence annuelle sur le même périmètre analytique ; dénominateur = nuits d'hospitalisation éligibles. Borne supérieure commune = ",
        sprintf("%.2f", incidence_fill_limit),
        ".\nNuits d'hospitalisation éligibles communes : ",
        incidence_denominator_note
      ),
      x = "Année",
      y = NULL
    ) +
    theme_minimal() +
    theme(
      panel.grid = element_blank(),
      axis.text.x = element_text(size = report_config$axis_text_x_size),
      axis.text.y = element_text(size = report_config$axis_text_y_size),
      strip.text.x = element_text(
        size = report_config$strip_text_size,
        face = "bold"
      )
    )

  incidence_png_path <- save_plot_png(
    p_incidence,
    paste0("ratb_incidence_global_heatmap_", slugify_filename(taxon)),
    width = incidence_width_in,
    height = incidence_height_in
  )

  incidence_pdf_path <- save_plot_pdf(
    p_incidence,
    paste0("ratb_incidence_global_heatmap_", slugify_filename(taxon)),
    width = incidence_width_in,
    height = incidence_height_in
  )

  list(
    table = table_obj,
    plot_heading = wrap_html_output(build_plot_heading_block(
      file_stem = paste0(
        "ratb_incidence_global_heatmap_",
        slugify_filename(taxon)
      ),
      caption = paste0(
        taxon,
        " - carte thermique annuelle de densité d'incidence (vue globale)"
      )
    )),
    plot = incidence_png_path,
    plot_width = incidence_width_in,
    plot_height = incidence_height_in,
    pdf_button = wrap_html_output(show_download_button(
      incidence_pdf_path,
      paste0(
        "Télécharger la carte thermique PDF de densité d'incidence globale pour ",
        taxon,
        " (",
        basename(incidence_pdf_path),
        ")"
      )
    ))
  )
}

build_ratb_by_type_output_block <- function(taxon, context) {
  panel_by_type_report <- context$panel_by_type_report
  indicator_spec <- context$indicator_spec
  dataset_display_map <- context$dataset_display_map
  dataset_levels <- context$dataset_levels
  selected_sample_types <- context$selected_sample_types
  report_config <- context$report_config
  by_type_tbl <- panel_by_type_report %>%
    filter(report_taxon_label == taxon) %>%
    mutate(
      dataset = lookup_ratb_dataset_label(dataset, dataset_display_map)
    ) %>%
    arrange(
      match(sample_type, selected_sample_types),
      match(dataset, dataset_levels),
      dedup_year,
      indicator_label
    )

  if (nrow(by_type_tbl) == 0L) {
    note <- wrap_html_output(htmltools::tags$p(
      "Aucune sortie par type n'est disponible avec le filtre de types de prélèvement retenu pour ce rapport."
    ))
    return(list(
      table = note,
      plot = empty_html_output(),
      plot_width = NULL,
      plot_height = NULL,
      pdf_button = empty_html_output()
    ))
  }

  table_obj <- wrap_html_output(show_audit_table(
    data = by_type_tbl %>%
      select(
        dataset,
        sample_type,
        indicator_label,
        dedup_year,
        n_isolates,
        n_tested,
        n_resistant,
        n_o,
        pct_resistant
      ) %>%
      rename(
        `Jeu comparé` = dataset,
        `Type de prélèvement` = sample_type,
        `Indicateur` = indicator_label,
        `Année` = dedup_year,
        `N isolats` = n_isolates,
        `N testés` = n_tested,
        `N résistants` = n_resistant,
        `N non testés` = n_o,
        `% résistants parmi les testés` = pct_resistant
      ),
    file_stem = paste0("ratb_by_type_", slugify_filename(taxon)),
    caption = paste0(
      taxon,
      " - tableau annuel des proportions de résistance (par type)"
    ),
    page_length = 20,
    scroll_y = "320px",
    digits = report_config$datatable_digits
  ))

  indicator_levels <- indicator_spec %>%
    filter(report_taxon_label == taxon) %>%
    arrange(display_order) %>%
    pull(indicator_label) %>%
    unique()

  by_type_heatmap <- panel_by_type_report %>%
    filter(report_taxon_label == taxon) %>%
    prepare_ratb_by_type_combined_heatmap(
      min_n = report_config$indicator_min_n,
      dataset_levels = dataset_levels,
      indicator_levels = indicator_levels,
      sample_type_levels = selected_sample_types,
      dataset_display_map = dataset_display_map
    )

  by_type_height_in <- max(
    report_config$by_type_height_min_in,
    length(indicator_levels) *
      report_config$by_type_height_per_indicator_and_type_in *
      max(1L, length(selected_sample_types)) +
      report_config$by_type_height_padding_in
  )
  by_type_width_in <- max(
    report_config$by_type_width_min_in,
    length(dataset_levels) * report_config$by_type_width_per_dataset_in
  )

  p_by_type <- ggplot(
    by_type_heatmap,
    aes(x = dedup_year, y = indicator_label, fill = pct_resistant_plot)
  ) +
    geom_tile(color = "white", linewidth = 0.2) +
    geom_text(
      aes(label = cell_label),
      size = report_config$label_size_by_type,
      lineheight = 0.9
    ) +
    facet_wrap(~panel_label, ncol = length(dataset_levels)) +
    build_fill_scale_gradientn(
      colors = report_config$fill_palette_proportion,
      limits = c(0, 100),
      na_value = "grey90",
      name = "%R",
      breaks = report_config$fill_breaks_proportion,
      labels = \(x) paste0(x, "%"),
      transform = report_config$fill_transform
    ) +
    labs(
      title = paste0(
        taxon,
        " - proportions annuelles de résistance par type de prélèvement"
      ),
      subtitle = paste0(
        "Vue par type du rapport limitée à ",
        paste(selected_sample_types, collapse = " et "),
        ". Seuil n_tested = ",
        report_config$indicator_min_n,
        build_family_indicator_note(taxon, indicator_spec)
      ),
      x = "Année",
      y = NULL
    ) +
    theme_minimal() +
    theme(
      panel.grid = element_blank(),
      axis.text.x = element_text(size = report_config$axis_text_x_size),
      axis.text.y = element_text(size = report_config$axis_text_y_size),
      strip.text = element_text(
        size = report_config$strip_text_size,
        face = "bold"
      ),
      strip.background = element_rect(fill = "grey96", color = "grey80")
    )

  by_type_png_path <- save_plot_png(
    p_by_type,
    paste0("ratb_by_type_heatmap_", slugify_filename(taxon)),
    width = by_type_width_in,
    height = by_type_height_in
  )

  by_type_pdf_path <- save_plot_pdf(
    p_by_type,
    paste0("ratb_by_type_heatmap_", slugify_filename(taxon)),
    width = by_type_width_in,
    height = by_type_height_in
  )

  list(
    table = table_obj,
    plot_heading = wrap_html_output(build_plot_heading_block(
      file_stem = paste0("ratb_by_type_heatmap_", slugify_filename(taxon)),
      caption = paste0(
        taxon,
        " - carte thermique annuelle des proportions de résistance par type de prélèvement"
      )
    )),
    plot = by_type_png_path,
    plot_width = by_type_width_in,
    plot_height = by_type_height_in,
    pdf_button = wrap_html_output(show_download_button(
      by_type_pdf_path,
      paste0(
        "Télécharger la carte thermique PDF des proportions par type pour ",
        taxon,
        " (",
        basename(by_type_pdf_path),
        ")"
      )
    ))
  )
}

build_ratb_taxon_outputs <- function(taxon, context) {
  list(
    global = build_ratb_global_output_block(taxon, context),
    incidence = build_ratb_global_incidence_output_block(taxon, context),
    by_type = build_ratb_by_type_output_block(taxon, context)
  )
}

build_ratb_phenotype_proportion_table_block <- function(
  indicator_ids,
  file_stem,
  caption,
  context,
  sample_type_filter = NULL
) {
  indicator_spec <- context$indicator_spec
  panel_global <- context$panel_global
  panel_by_type_report <- context$panel_by_type_report
  dataset_display_map <- context$dataset_display_map
  dataset_levels <- context$dataset_levels
  report_config <- context$report_config

  spec_subset <- indicator_spec %>%
    filter(indicator_id %in% indicator_ids) %>%
    arrange(display_order) %>%
    select(indicator_id, indicator_label)

  if (nrow(spec_subset) == 0L) {
    return(wrap_html_output(htmltools::tags$p(
      "Aucun indicateur phénotypique n'est défini pour ce bloc."
    )))
  }

  source_tbl <- if (is.null(sample_type_filter)) {
    panel_global
  } else {
    panel_by_type_report %>%
      filter(sample_type == sample_type_filter)
  }

  phenotype_tbl <- source_tbl %>%
    filter(indicator_id %in% spec_subset$indicator_id) %>%
    mutate(
      dataset = lookup_ratb_dataset_label(dataset, dataset_display_map),
      indicator_id = factor(indicator_id, levels = spec_subset$indicator_id),
      n_non_positive = pmax(n_isolates - n_resistant, 0L)
    ) %>%
    arrange(match(dataset, dataset_levels), dedup_year, indicator_id)

  if (nrow(phenotype_tbl) == 0L) {
    note_text <- if (is.null(sample_type_filter)) {
      "Aucune sortie phénotypique de proportion globale n'est disponible pour ce bloc."
    } else {
      paste0(
        "Aucune sortie phénotypique de proportion n'est disponible pour le type de prélèvement `",
        sample_type_filter,
        "`."
      )
    }
    return(wrap_html_output(htmltools::tags$p(note_text)))
  }

  display_tbl <- if (is.null(sample_type_filter)) {
    phenotype_tbl %>%
      transmute(
        `Jeu comparé` = dataset,
        `Indicateur` = indicator_label,
        `Année` = dedup_year,
        `N isolats` = n_isolates,
        `N positifs` = n_resistant,
        `N non positifs` = n_non_positive,
        `% positifs parmi tous les isolats` = pct_resistant
      )
  } else {
    phenotype_tbl %>%
      transmute(
        `Jeu comparé` = dataset,
        `Type de prélèvement` = sample_type,
        `Indicateur` = indicator_label,
        `Année` = dedup_year,
        `N isolats` = n_isolates,
        `N positifs` = n_resistant,
        `N non positifs` = n_non_positive,
        `% positifs parmi tous les isolats` = pct_resistant
      )
  }

  wrap_html_output(show_audit_table(
    data = display_tbl,
    file_stem = file_stem,
    caption = caption,
    page_length = 20,
    scroll_y = "320px",
    digits = report_config$datatable_digits
  ))
}

build_ratb_phenotype_incidence_table_block <- function(
  indicator_ids,
  file_stem,
  caption,
  context
) {
  indicator_spec <- context$indicator_spec
  panel_incidence_global <- context$panel_incidence_global
  dataset_display_map <- context$dataset_display_map
  dataset_levels <- context$dataset_levels
  report_config <- context$report_config

  spec_subset <- indicator_spec %>%
    filter(indicator_id %in% indicator_ids) %>%
    arrange(display_order) %>%
    select(indicator_id, indicator_label)

  if (nrow(spec_subset) == 0L) {
    return(wrap_html_output(htmltools::tags$p(
      "Aucun indicateur phénotypique n'est défini pour ce bloc."
    )))
  }

  incidence_tbl <- panel_incidence_global %>%
    filter(indicator_id %in% spec_subset$indicator_id) %>%
    mutate(
      dataset = lookup_ratb_dataset_label(dataset, dataset_display_map),
      indicator_id = factor(indicator_id, levels = spec_subset$indicator_id)
    ) %>%
    arrange(match(dataset, dataset_levels), dedup_year, indicator_id)

  if (nrow(incidence_tbl) == 0L) {
    return(wrap_html_output(htmltools::tags$p(
      "Aucune sortie phénotypique d'incidence globale n'est disponible pour ce bloc."
    )))
  }

  wrap_html_output(show_audit_table(
    data = incidence_tbl %>%
      transmute(
        `Jeu comparé` = dataset,
        `Indicateur` = indicator_label,
        `Année` = dedup_year,
        `N isolats` = n_isolates,
        `N positifs` = n_resistant,
        `N nuits hospitalisation` = hospital_nights,
        `Densité pour 1000 nuits` = incidence_density_per_1000
      ),
    file_stem = file_stem,
    caption = caption,
    page_length = 20,
    scroll_y = "320px",
    digits = report_config$datatable_digits
  ))
}
