`%||%` <- function(x, y) if (!is.null(x)) x else y

# Deterministic accent stripper vendored from the former `fmckage::rm_accent`
# dependency, so the project no longer needs that non-CRAN package. Uses
# `chartr` character maps, which are platform-independent (unlike a
# locale-sensitive `iconv(..., "ASCII//TRANSLIT")`).
rm_accent <- function(str) {
  if (!is.character(str)) {
    str <- as.character(str)
  }

  symbols <- c(
    acute = "áéíóúÁÉÍÓÚýÝ",
    grave = "àèìòùÀÈÌÒÙ",
    circunflex = "âêîôûÂÊÎÔÛ",
    tilde = "ãõÃÕñÑ",
    umlaut = "äëïöüÄËÏÖÜÿ",
    cedil = "çÇ"
  )

  nudeSymbols <- c(
    acute = "aeiouAEIOUyY",
    grave = "aeiouAEIOU",
    circunflex = "aeiouAEIOU",
    tilde = "aoAOnN",
    umlaut = "aeiouAEIOUy",
    cedil = "cC"
  )

  chartr(
    paste(symbols, collapse = ""),
    paste(nudeSymbols, collapse = ""),
    str
  )
}
