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
  # took it, so a run that meets a lock it never marked leaves it alone. What
  # that buys is a shorter interval, not a guarantee -- see the release below.
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
# taken in the meantime. That much the release settles on its own.
#
# The token settles less, and the boundary is worth stating rather than
# implying. Reading the owner and removing the directory are two operations, so
# a lock replaced between them is still removed by the wrong run; the same gap
# exists on the way in, between creating the lock and marking it. Both need the
# same thing to happen first -- somebody removing a lock while its run is alive
# -- which is why that is documented as unsupported instead of defended against.
# Defending against it needs a lock the operating system holds: a directory
# anyone may delete cannot make "remove this only while it is still mine" a
# single operation, and no base-R call does it either. The token stays because
# it shortens the exposure from the length of a publication to the length of two
# filesystem calls, which is the difference between a likely accident and an
# unlucky one.
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
  # What is reported is the state of the directory, not the fact that removal
  # was attempted: a filesystem that refuses the removal leaves a lock behind,
  # and a release that claimed success anyway would be the one thing a caller
  # could not check for itself. The ownership is given up either way -- retrying
  # later is what the emptied state exists to prevent -- so a lock that survives
  # is left to the documented procedure for one abandoned by an interrupted run.
  unlink(lock, recursive = TRUE, force = TRUE)
  invisible(!dir.exists(lock))
}
