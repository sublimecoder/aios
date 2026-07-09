---
name: one-password
description: "1Password/op: service-account first, targeted secret read/store/inject, tmux."
---

# 1Password CLI

Follow the official CLI get-started steps. Don't guess install commands.

Requires the `op` and `tmux` binaries. On macOS install the CLI with `brew install 1password-cli`.

## References

- Official docs: https://developer.1password.com/docs/cli/get-started/
- `~/.claude/skills/one-password/references/get-started.md` (install + app integration + sign-in flow)
- `~/.claude/skills/one-password/references/cli-examples.md` (real `op` examples, including safe item create/edit patterns)

## Workflow

1. Check OS + shell.
2. Verify CLI present inside tmux: `op --version`.
3. REQUIRED: create exactly one persistent named tmux session for the whole secret task.
4. Try scoped service-account access first when a matching token/workflow exists; no dialogs.
5. If service-account access is missing or lacks the exact item/field needed, automatically try the desktop-app fallback in the same session. Do not ask for chat permission first.
6. Desktop fallback: trigger app integration/unlock, then `op signin` once inside the same session. The 1Password prompt is the user approval boundary; ask in chat only if the prompt cannot be surfaced or completed.
7. Verify chosen access path inside that same session: `op whoami`.
8. If multiple accounts: use `--account` or `OP_ACCOUNT`.
9. If a command fails, reuse the same tmux session with `tmux send-keys`; do not start a second session just to retry.

## Default Account

- Default account for personal/work secrets is `my.1password.com` (1Password's standard account domain).
- Do not silently use `my.1password.eu` unless explicitly asked.
- Pass `--account my.1password.com` on every `op` command when storing or reading secrets. Do not rely on ambient account selection.
- `op account list` is metadata-only, but still must run inside tmux. Use it to confirm account names when routing is unclear.
- `op signin --account my.1password.com` can return status 0 with no useful output and still not make a later shell signed in. Prefer doing sign-in, create/edit/get, and verification in the same tmux shell.

## Service account tokens

- Prefer service-account tokens before any interactive 1Password flow. User dialogs are fallback only.
- 1Password service accounts are non-interactive tokens for a specific vault/scope, useful for automation without unlocking the desktop app.
- Set your own: export a service-account token as `OP_SERVICE_ACCOUNT_TOKEN` (e.g. from `~/.profile`), scoped to a restricted vault you create for automation. `OP_SERVICE_ACCOUNT_TOKEN` is 1Password's real env var name — use it as-is.
- If the token is not already exported, not applicable, or cannot read the exact known item/field required, use the desktop-app 1Password flow below automatically. Ask only when an actual unlock or other user interaction remains blocked.
- Export/pass it only for the single command that needs it: `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" op item get "<your-item>" --vault "<your-vault>" ...`.
- Service-account `op` reads require an explicit vault query; omitting `--vault "<your-vault>"` fails even when the token is valid.
- Keep the tmux rule: every `op` command, including service-account reads, still runs inside one named tmux session.
- Do not enumerate vaults/items with service accounts by default. If the user explicitly asks to search, gives a screenshot/listing, or gives only a fuzzy item name, use the safe metadata search below before desktop fallback.
- Print presence/shape only, never token or secret values.

## Required Persistent Tmux Session

The shell tool uses a fresh TTY per command. Run `op` inside one dedicated tmux session and keep using that same session until the whole secret task is done. Service-account commands still run here, but must not trigger app prompts.

Example:

```bash
SOCKET_DIR="${OP_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/op-tmux-sockets}"
mkdir -p "$SOCKET_DIR"
SOCKET="$SOCKET_DIR/op-work.sock"
SESSION="op-work"

tmux -S "$SOCKET" has-session -t "$SESSION" 2>/dev/null ||
  tmux -S "$SOCKET" new -d -s "$SESSION" -n shell
tmux -S "$SOCKET" send-keys -t "$SESSION:" -- "op signin --account my.1password.com" Enter
tmux -S "$SOCKET" send-keys -t "$SESSION:" -- "op whoami" Enter
tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION:" -S -200
```

Do not create a new tmux session after a quoting, item-name, or command failure. Send a corrected command into the existing session.
Target the session as `$SESSION:` instead of assuming window `0`; older sessions may have window indexes starting at `1`.

## Service-Specific Workflows

- Keep service-specific auth details (per-registry tokens, non-interactive auth wrappers) in the owning tool or skill, not here.
- This skill owns only the generic 1Password rules: tmux-only `op`, targeted reads, one persistent session, no broad enumeration, no secret output.

## Known working secret-write pattern

Use the persistent tmux session. Write the exact secret task to a temp script, then send that script into `op-work`; do not create a second tmux session for retries.

```bash
SOCKET_DIR="${OP_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/op-tmux-sockets}"
SOCKET="$SOCKET_DIR/op-work.sock"
SESSION="op-work"
tmux -S "$SOCKET" has-session -t "$SESSION" 2>/dev/null ||
  tmux -S "$SOCKET" new -d -s "$SESSION" -n shell

cat > /tmp/op-store-secret.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
set +x
ACCOUNT="my.1password.com"
ITEM_TITLE="Service API Tokens"
FIELD_NAME="api_token"
EXPECTED_PREFIX=""
NOTES="Created via tmux-safe op workflow"
TOKEN="$(pbpaste)"
if [ -n "$EXPECTED_PREFIX" ]; then
  case "$TOKEN" in "$EXPECTED_PREFIX"*) ;; *) echo "clipboard value does not match expected prefix" >&2; exit 2;; esac
fi
op item create --account "$ACCOUNT" --category "API Credential" --title "$ITEM_TITLE" "$FIELD_NAME[password]=$TOKEN" "notesPlain=$NOTES" >/dev/null
op item get "$ITEM_TITLE" --account "$ACCOUNT" --fields "label=$FIELD_NAME" >/dev/null
echo "stored and verified secret field without printing it"
SCRIPT
chmod 700 /tmp/op-store-secret.sh
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "bash /tmp/op-store-secret.sh; rm -f /tmp/op-store-secret.sh" C-m
```

The `op` category string is human-readable and case-sensitive in this CLI build; use `"API Credential"`, not `api_credential`.

## Exact field reads

For a known item, verify the field shape before using it live: length, expected prefix, newline count, never value. `op --field NAME` and `--fields label=NAME` can return the wrong concealed field when an item has duplicate/legacy credential fields. If shape is wrong, read the known item as JSON and extract the exact label.

```bash
cat > /tmp/op-read-field.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
set +x
ITEM_TITLE="Known API Credential Item"
FIELD_LABEL="api_token"
VAULT="<your-vault>"
value="$(
  OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" \
    op item get "$ITEM_TITLE" --vault "$VAULT" --format json |
    FIELD_LABEL="$FIELD_LABEL" node -e 'let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{const item=JSON.parse(s); const f=(item.fields||[]).find(x=>x.label===process.env.FIELD_LABEL); if(!f?.value) process.exit(2); process.stdout.write(f.value);})'
)"
echo "field_len:${#value}"
case "$value" in sk-*) echo "field_prefix:sk" ;; *) echo "field_prefix:other" ;; esac
echo "field_has_newline:$(printf %s "$value" | wc -l | tr -d ' ')"
SCRIPT
chmod 700 /tmp/op-read-field.sh
tmux -S "$SOCKET" send-keys -t "$SESSION:" -- "bash /tmp/op-read-field.sh; rm -f /tmp/op-read-field.sh" C-m
```

Keep JSON extraction scoped to the known item and vault. Do not enumerate vaults/items to discover candidates.

## Explicit item search

Only use this when the user explicitly asks to search, gives a screenshot/listing, or the exact title guess failed and the user asks for regex/fuzzy lookup. Stay vault-scoped and metadata-only; print candidate titles/ids/categories/vault names, never fields or values. Prefer exact visible strings from screenshots first: vault name, item title, and field label.

```bash
cat > /tmp/op-find-item.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
set +x
VAULT="<your-vault>"
QUERY="<search-term>"
OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" \
  op item list --vault "$VAULT" --format json |
  QUERY="$QUERY" VAULT="$VAULT" node -e '
let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
  const q=process.env.QUERY.toLowerCase();
  const vault=process.env.VAULT;
  const items=JSON.parse(s).filter(x => [
    x.title, x.id, x.category, ...(x.tags || [])
  ].filter(Boolean).join("\n").toLowerCase().includes(q));
  for (const item of items.slice(0, 10)) {
    console.log(`title:${item.title} id:${item.id} category:${item.category || ""} vault:${vault}`);
  }
  console.log(`matches:${items.length}`);
})'
SCRIPT
chmod 700 /tmp/op-find-item.sh
tmux -S "$SOCKET" send-keys -t "$SESSION:" -- "bash /tmp/op-find-item.sh; rm -f /tmp/op-find-item.sh" C-m
```

After choosing a candidate, switch back to exact item/field JSON extraction and shape-only validation. An exact known personal item may use desktop fallback automatically; do not broadly enumerate personal vaults unless the user asked to search.

## Redacted debugging

Keep the whole pipeline inside the same tmux session. Inspect status and output length, never secret values.

```bash
cat > /tmp/op-debug.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
set +x
SIGNIN_OUTPUT="$(op signin --account my.1password.com 2>&1 || true)"
echo "signin output bytes: ${#SIGNIN_OUTPUT}"
op account list 2>&1 | sed -E "s/(xox[baprs]-)[A-Za-z0-9-]+/\\1REDACTED/g; s/(xapp-)[A-Za-z0-9-]+/\\1REDACTED/g"
SCRIPT
chmod 700 /tmp/op-debug.sh
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "bash /tmp/op-debug.sh; rm -f /tmp/op-debug.sh" C-m
```

## Guardrails

- Never paste secrets into logs, chat, or code.
- Prefer `op run` / `op inject` over writing secrets to disk.
- If sign-in without app integration is needed, use `op account add`.
- If a command returns "account is not signed in", re-run `op signin` inside tmux and authorize in the app.
- Let the desktop 1Password unlock prompt request user interaction directly; do not add a separate chat permission round trip first.
- Do not run `op` outside tmux; stop and ask if tmux is unavailable.
