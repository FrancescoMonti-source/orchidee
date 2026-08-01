## Ownership of the site input diagnostics report directory.
##
## A run owns two pieces of filesystem state while it publishes: the lock that
## makes it the only writer, and the staging directory holding the report being
## composed. Both have to be given up on every exit path, including the error
## handler -- which can fire after a successful release. Giving them up is
## therefore a thing worth asserting on its own, so it lives here rather than
## inline in the diagnostics script.

orchidee_diagnostics_lock_name <- function() {
  ".orchidee_diagnostics.lock"
}

orchidee_publication_state <- function() {
  state <- new.env(parent = emptyenv())
  # Ownership is written into the lock, not merely remembered by the run that
  # took it. The refusal message tells an operator to remove a stale lock by
  # hand; if they do so while its run is alive, the next run takes the lock and
  # ours would otherwise remove it on the way out.
  state$token <- paste0(Sys.getpid(), "-", basename(tempfile("")))
  state$lock <- NULL
  state$staging <- NULL
  state
}

orchidee_publication_lock_owner <- function(lock_path) {
  owner_file <- file.path(lock_path, "owner.txt")
  if (!file.exists(owner_file)) {
    return(NA_character_)
  }
  owner <- tryCatch(
    readLines(owner_file, warn = FALSE),
    error = function(e) NA_character_
  )
  if (length(owner) == 0L) NA_character_ else owner[[1L]]
}

# dir.create() either creates the directory or reports that it did not,
# atomically, which is what makes it usable as the lock. It reports the same
# FALSE whether the directory was already there or could not be created at all,
# and those are different problems: one is another run, the other is a report
# directory this run cannot write into. Only the first is worth waiting out.
orchidee_publication_acquire <- function(state, report_dir) {
  lock_path <- file.path(report_dir, orchidee_diagnostics_lock_name())
  if (!dir.create(lock_path, showWarnings = FALSE)) {
    return(if (dir.exists(lock_path)) "held" else "unavailable")
  }
  written <- tryCatch(
    {
      writeLines(state$token, file.path(lock_path, "owner.txt"))
      TRUE
    },
    error = function(e) FALSE
  )
  if (!isTRUE(written)) {
    # An unmarked lock could never be released, so this run does not keep it.
    unlink(lock_path, recursive = TRUE, force = TRUE)
    return("unavailable")
  }
  state$lock <- lock_path
  "acquired"
}

orchidee_publication_track_staging <- function(state, staging_dir) {
  state$staging <- staging_dir
  invisible(state)
}

# A release is final: each path leaves the state before it is unlinked, so a
# second release has nothing to act on and cannot reach a lock another run has
# taken in the meantime. The token is verified for the same reason, one step
# further out -- a lock this run did not mark is somebody else's.
orchidee_publication_release <- function(state) {
  staging <- state$staging
  state$staging <- NULL
  if (!is.null(staging)) {
    unlink(staging, recursive = TRUE, force = TRUE)
  }
  lock <- state$lock
  state$lock <- NULL
  if (is.null(lock)) {
    return(invisible(FALSE))
  }
  if (!identical(orchidee_publication_lock_owner(lock), state$token)) {
    return(invisible(FALSE))
  }
  unlink(lock, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}
