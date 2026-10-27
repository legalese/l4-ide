#!/usr/bin/env bash
# Reads what `l4 run FILE 2>&1` printed, on standard input, and exits 1 when
# it shows that FILE is not a successful documentation example: a diagnostic
# of error severity, or an #ASSERT that a refusal stopped. Exits 0 otherwise.
#
# A refused #ASSERT leaves `l4 run` at exit 0 and its diagnostic at warning
# severity, so it is found by its result: a line "Result:", then a line that
# holds only "assertion refused:". The reason of a refusal is printed on the
# lines after that, indented, so a reason that runs over several lines and
# says "assertion refused:" on one of them, in a refusing #EVAL, is not
# mistaken for a refused #ASSERT.
#
# doc/test-docs.sh runs it on every .l4 file under doc/.

awk '
  { sub(/\r$/, "") }
  { if (tolower($0) ~ /diagnosticseverity_error/) bad = 1 }
  prev == "Result:" && $0 ~ /^[[:space:]]*assertion refused:[[:space:]]*$/ { bad = 1 }
  { prev = $0 }
  END { exit bad }
'
