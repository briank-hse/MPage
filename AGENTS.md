Workspace rules:

Only modify files inside this repository.

Do not create shadow copies.

Do not copy files between directories.

Use minimal patch edits instead of rewriting entire files.

Confirm file paths before editing.



Cerner / SPA rules:

Preserve current SPA behavior unless explicitly directed otherwise.

Compile and runtime validation happen only in Cerner.

Keep XMLCCLRequest transport simple; do not add multi-call startup fan-out for a tab.

Treat large JSON/UI payload size as a primary technical risk.

For reply.ui, prefer multiple small html\_parts entries over one large HTML string.

Keep APPLINK / CCLLINK wrappers shell-owned.

Do not introduce backend-supplied executable JS.

Use phased migration with legacy fallback until module sign-off.

