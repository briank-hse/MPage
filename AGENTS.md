Workspace rules:

Only modify files inside this repository.

Do not create shadow copies.

Do not copy files between directories.

Use minimal patch edits instead of rewriting entire files.

Confirm file paths before editing.

When reading or editing files in this workspace, use absolute paths rooted at:

`z:\Meds Management\MPage`

PowerShell sessions may start in `C:\WINDOWS\System32\WindowsPowerShell\v1.0` even when the tool context says the cwd is this repository. Do not rely on relative paths until `Get-Location` has confirmed the shell is actually in `z:\Meds Management\MPage`.

The `Z:` repository path may be blocked by the local sandbox on first access even for read-only commands. When using developer shell tools to read, search, diff, or inspect files under `z:\Meds Management\MPage`, request sandbox escalation up front for the narrow command instead of first running an un-escalated command that will fail with `Access is denied`.

Preferred file-read pattern:

`Get-Content "z:\Meds Management\MPage\<relative repo path>"`

Preferred search pattern:

`rg -n "<pattern>" "z:\Meds Management\MPage\<relative repo path or directory>"`

Before editing, confirm the exact absolute target path. Edit the repository file directly; do not make a temporary copy elsewhere and copy it back.



Cerner / SPA rules:

Preserve current SPA behavior unless explicitly directed otherwise.

Compile and runtime validation happen only in Cerner.

Keep XMLCCLRequest transport simple; do not add multi-call startup fan-out for a tab.

Treat large JSON/UI payload size as a primary technical risk.

For reply.ui, prefer multiple small html\_parts entries over one large HTML string.

Keep APPLINK / CCLLINK wrappers shell-owned.

Do not introduce backend-supplied executable JS.

Use phased migration with legacy fallback until module sign-off.



CernerScraper corpus rules:

For CCL examples, code-value discovery, Discern corpus searches, or prior-art lookup, consult the CernerScraper workspace here:

`C:\Users\briankehoe\Documents\Work\Python\CernerScraper\Development\CernerScraper`

Before using that corpus, read its local instructions:

`C:\Users\briankehoe\Documents\Work\Python\CernerScraper\Development\CernerScraper\AGENTS.md`

Use `agent_corpus_search.py` from the CernerScraper workspace when the user asks to search the corpus. Follow that workspace's `AGENTS.md` for the correct command shape and search workflow.

The CernerScraper workspace is reference-only for this repository unless the user explicitly asks for changes there. Do not copy files from CernerScraper into this repository; use findings as guidance and apply minimal patches directly in `z:\Meds Management\MPage`.
