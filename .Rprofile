if (
  identical(Sys.getenv("ORCHIDEE_SETUP"), "1") &&
    .Platform$OS.type == "windows" &&
    is.null(getOption("download.file.method")) &&
    nzchar(Sys.which("curl"))
) {
  local({
    curl_help <- tryCatch(
      system2(
        Sys.which("curl"),
        c("--help", "all"),
        stdout = TRUE,
        stderr = TRUE
      ),
      error = function(...) character()
    )
    if (
      any(grepl("--ssl-revoke-best-effort", curl_help, fixed = TRUE))
    ) {
      # Use Windows Schannel during setup. Revocation remains enabled when its
      # distribution point is reachable, while managed hosts can tolerate an
      # unavailable revocation service without disabling certificate checks.
      options(download.file.method = "curl")
      if (is.null(getOption("download.file.extra"))) {
        options(download.file.extra = "--ssl-revoke-best-effort")
      }
      message(
        "ORCHIDEE setup: Schannel TLS revocation uses best-effort mode; ",
        "certificate-chain validation remains enabled."
      )
    }
  })
}

source("renv/activate.R")
