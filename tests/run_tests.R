#!/usr/bin/env Rscript

test_files <- sort(list.files(
  "tests",
  pattern = "^test_.*\\.R$",
  full.names = TRUE
))
if (length(test_files) == 0L) {
  stop("No standalone source tests found under tests/.", call. = FALSE)
}

rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)

for (test_file in test_files) {
  cat("RUN:", test_file, "\n")
  status <- system2(rscript, c("--vanilla", shQuote(test_file)))
  if (!identical(status, 0L)) {
    stop("Standalone source test failed: ", test_file, call. = FALSE)
  }
}

cat("PASS: all standalone source tests\n")
