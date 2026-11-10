---
description: Drain the oldest open rows of the after-action register — one register-worker per row opens its target, verdicts apply-or-decline, and the batch is applied on your confirm. Pass --draft to annotate only.
disable-model-invocation: true
---

Read and follow **Mode B** of `AIOS/Skills/after-action.md`.

Arguments: `$ARGUMENTS` — an optional row count (default 5) and/or `--draft`.

`--draft` is the unattended shape: verdict every row and write the verdicts into the
register, apply nothing, leave every `Status` at `open`.
