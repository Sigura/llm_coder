Rules that prevent the most common broken files:
- Bash: never put a single quote (') anywhere inside a single-quoted awk or sed program, comments included ("doesn't" ends the program and bash runs the rest as shell). Write \047 for a quote, or pass the program through a quoted heredoc.
- Kotlin: Kotlin has no \f, \a or \v escapes (use \u000C and similar); import everything you use; keep nullable and non-null types apart (V? is not V).
