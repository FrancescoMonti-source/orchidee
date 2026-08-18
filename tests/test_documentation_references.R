#!/usr/bin/env Rscript

# Why: methods.md names a file and a function for every decision it records,
# and nothing checked that those pointers still resolve. A rename, a move or a
# deletion turns a row into a silent lie, which has already happened twice in
# this repository's history. This test makes the pointers mechanical.
#
# It checks that references resolve, not that they are true. A row can name a
# function that exists and still describe it wrongly; only reading catches
# that.

register_path <- "documentation/methods.md"

extract_backticked <- function(text) {
  matches <- regmatches(text, gregexpr("`[^`]+`", text))[[1L]]
  if (length(matches) == 0L) {
    return(character(0))
  }
  gsub("^`|`$", "", matches)
}

register_lines <- readLines(register_path, warn = FALSE)
table_lines <- register_lines[startsWith(register_lines, "|")]

decision_rows <- list()
for (line in table_lines) {
  inner <- sub("\\|\\s*$", "", sub("^\\|", "", line))
  cells <- trimws(strsplit(inner, "|", fixed = TRUE)[[1L]])
  if (length(cells) != 3L) {
    next
  }
  if (identical(cells[[1L]], "Décision") || grepl("^[-: ]+$", cells[[1L]])) {
    next
  }
  decision_rows[[length(decision_rows) + 1L]] <- cells
}

if (length(decision_rows) == 0L) {
  stop("No decision rows parsed from ", register_path, call. = FALSE)
}

# Index every function definition, by the file that holds it.
source_files <- unlist(lapply(
  c("R", "scripts", "config"),
  function(dir) list.files(dir, pattern = "\\.R$", full.names = TRUE)
), use.names = FALSE)

definitions_by_file <- lapply(source_files, function(path) {
  src <- readLines(path, warn = FALSE)
  headers <- regmatches(
    src,
    regexpr("^\\s*[.A-Za-z][.A-Za-z0-9_]*\\s*<-\\s*function", src)
  )
  trimws(sub("<-.*$", "", headers))
})
names(definitions_by_file) <- source_files
all_definitions <- unique(unlist(definitions_by_file, use.names = FALSE))

problems <- character(0)
note <- function(row_label, message) {
  problems <<- c(problems, paste0(message, "\n    row: ", row_label))
}

for (cells in decision_rows) {
  row_label <- substr(cells[[1L]], 1L, 70L)
  tokens <- extract_backticked(cells[[2L]])

  referenced_paths <- tokens[grepl("/", tokens, fixed = TRUE) |
    grepl("\\.(R|csv|qmd)$", tokens)]
  referenced_funs <- sub("\\(\\)$", "", tokens[endsWith(tokens, "()")])

  for (path in referenced_paths) {
    if (!file.exists(path)) {
      note(row_label, paste0("  referenced path does not exist: ", path))
    }
  }

  # Strict pairing: a row that names both a file and a function must name the
  # file that actually defines it, so a function moving between files cannot
  # leave the row behind.
  named_r_files <- referenced_paths[grepl("\\.R$", referenced_paths)]
  named_r_files <- named_r_files[file.exists(named_r_files)]

  # An existing R file outside the indexed directories would otherwise reach
  # definitions_by_file[[path]], where a missing name is an error in R rather
  # than NULL: the check would crash instead of reporting. Say so instead.
  unindexed <- setdiff(named_r_files, names(definitions_by_file))
  if (length(unindexed) > 0L) {
    note(row_label, paste0(
      "  referenced R file sits outside the indexed directories",
      " (R, scripts, config), so its functions cannot be checked: ",
      paste(unindexed, collapse = ", ")
    ))
  }
  named_r_files <- intersect(named_r_files, names(definitions_by_file))

  for (fun in referenced_funs) {
    if (length(named_r_files) == 0L) {
      # A row may carry the function alone, inheriting the file from the row
      # above. Those are checked against the whole index instead.
      if (!fun %in% all_definitions) {
        note(row_label, paste0("  referenced function is not defined: ", fun, "()"))
      }
      next
    }
    holders <- named_r_files[vapply(
      named_r_files,
      function(path) fun %in% definitions_by_file[[path]],
      logical(1)
    )]
    if (length(holders) == 0L) {
      actual <- names(definitions_by_file)[vapply(
        definitions_by_file,
        function(defs) fun %in% defs,
        logical(1)
      )]
      note(row_label, paste0(
        "  ", fun, "() is not defined in the file the row names (",
        paste(named_r_files, collapse = ", "), ")",
        if (length(actual) > 0L) {
          paste0("; it is defined in ", paste(actual, collapse = ", "))
        } else {
          "; it is not defined anywhere indexed"
        }
      ))
    }
  }
}

if (length(problems) > 0L) {
  stop(
    "Stale references in ", register_path, ":\n",
    paste(problems, collapse = "\n"),
    call. = FALSE
  )
}

cat("PASS: methods.md references resolve (", length(decision_rows), " rows)\n", sep = "")
