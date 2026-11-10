#!/bin/sh
# Self-check for classify-skill.sh. Run: sh AIOS/Systems/test-classify-skill.sh
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
CLS="$HERE/classify-skill.sh"
VAULT=$(CDPATH= cd "$HERE/../.." && pwd)
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$2] got [$3]"; fails=$((fails+1)); fi; }
field() { AIOS_VAULT="$VAULT" sh "$CLS" "$1" 2>/dev/null | sed -n "s/^$2=//p"; }
fieldv() { AIOS_VAULT="$2" sh "$CLS" "$1" 2>/dev/null | sed -n "s/^$3=//p"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
VAULT_FIX="$TMP/fixvault"; mkdir -p "$VAULT_FIX"

# 1. A portable, model-invoked skill in the vault.
mkdir -p "$VAULT_FIX/skills/modelinv"
printf -- '---\nname: modelinv\ndescription: use when auditing skills for drift\n---\n# modelinv\n' > "$VAULT_FIX/skills/modelinv/SKILL.md"
check "portable kind"       "portable" "$(fieldv "$VAULT_FIX/skills/modelinv/SKILL.md" "$VAULT_FIX" KIND)"
check "portable ownership"  "vault"    "$(fieldv "$VAULT_FIX/skills/modelinv/SKILL.md" "$VAULT_FIX" OWNERSHIP)"
check "portable invocation" "model"    "$(fieldv "$VAULT_FIX/skills/modelinv/SKILL.md" "$VAULT_FIX" INVOCATION)"
[ "$(fieldv "$VAULT_FIX/skills/modelinv/SKILL.md" "$VAULT_FIX" DESC_TOKENS)" -gt 0 ] \
  && echo "ok   - portable costs tokens" || { echo "FAIL - portable DESC_TOKENS not > 0"; fails=$((fails+1)); }

# 2. A portable, user-invoked skill: zero per-turn cost.
mkdir -p "$VAULT_FIX/skills/userinv"
printf -- '---\nname: userinv\ndescription: d\ndisable-model-invocation: true\n---\n# userinv\n' > "$VAULT_FIX/skills/userinv/SKILL.md"
check "user-invoked invocation"  "user" "$(fieldv "$VAULT_FIX/skills/userinv/SKILL.md" "$VAULT_FIX" INVOCATION)"
check "user-invoked desc tokens" "0"    "$(fieldv "$VAULT_FIX/skills/userinv/SKILL.md" "$VAULT_FIX" DESC_TOKENS)"

# 3. A real flat vault note from this repo: different format, never symlinked, no invocation mode.
check "vault-note kind"       "vault-note" "$(field "$VAULT/AIOS/Skills/propagate.md" KIND)"
check "vault-note invocation" "na"         "$(field "$VAULT/AIOS/Skills/propagate.md" INVOCATION)"
check "vault-note ownership"  "vault"      "$(field "$VAULT/AIOS/Skills/propagate.md" OWNERSHIP)"

# 4. THE IMPORTANT ONE: an upstream skill is never marked editable.
mkdir -p "$TMP/fakehome/.claude/plugins/p/skills/thing"
printf -- '---\nname: thing\ndescription: does a thing\n---\n' > "$TMP/fakehome/.claude/plugins/p/skills/thing/SKILL.md"
check "plugin skill is upstream" "upstream" \
  "$(HOME="$TMP/fakehome" AIOS_VAULT="$VAULT" sh "$CLS" "$TMP/fakehome/.claude/plugins/p/skills/thing/SKILL.md" | sed -n 's/^OWNERSHIP=//p')"

# 5. A symlink pointing OUT of the vault is classified by where it really lives.
mkdir -p "$TMP/elsewhere/foo"
printf -- '---\nname: foo\ndescription: d\n---\n' > "$TMP/elsewhere/foo/SKILL.md"
ln -s "$TMP/elsewhere/foo/SKILL.md" "$TMP/link-SKILL.md"
check "symlink resolves to real location" "upstream" "$(field "$TMP/link-SKILL.md" OWNERSHIP)"

# 6. Unreadable path exits 1.
AIOS_VAULT="$VAULT" sh "$CLS" "$TMP/nope/SKILL.md" >/dev/null 2>&1
check "missing path exits 1" "1" "$?"

# 7. THE CRITICAL CASE: a symlink INSIDE a temp vault pointing OUTSIDE it
# must not inherit vault ownership just because the link itself lives
# under the vault root.
mkdir -p "$TMP/fakevault/skills/x" "$TMP/outside7"
printf -- '---\nname: outside7\ndescription: d\n---\n' > "$TMP/outside7/SKILL.md"
ln -s "$TMP/outside7/SKILL.md" "$TMP/fakevault/skills/x/SKILL.md"
check "inside-vault symlink to outside is upstream" "upstream" \
  "$(fieldv "$TMP/fakevault/skills/x/SKILL.md" "$TMP/fakevault" OWNERSHIP)"

# 8. Frontmatter-scoped invocation: a body line that merely starts with
# "disable-model-invocation: true" must not suppress model invocation.
mkdir -p "$TMP/bodytrap"
cat > "$TMP/bodytrap/SKILL.md" <<'EOF'
---
name: bodytrap
description: a skill about how to write skills, including this exact field
---

# Bodytrap

Setting the frontmatter field looks like this in the body:
disable-model-invocation: true
That line must not be read as real frontmatter.
EOF
check "body disable-model-invocation ignored" "model" "$(field "$TMP/bodytrap/SKILL.md" INVOCATION)"
[ "$(field "$TMP/bodytrap/SKILL.md" DESC_TOKENS)" -gt 0 ] \
  && echo "ok   - bodytrap still costs tokens" || { echo "FAIL - bodytrap DESC_TOKENS not > 0"; fails=$((fails+1)); }

# 9. tags: buried after several other frontmatter fields must still be found.
mkdir -p "$TMP/latevn"
cat > "$TMP/latevn/note.md" <<'EOF'
---
title: Some Note
author: me
system: Janitor
trigger: "whatever"
source: "somewhere"
status: draft
tags: [aios, skill]
---
# note
EOF
check "late tags still vault-note" "vault-note" "$(field "$TMP/latevn/note.md" KIND)"

# 10. Trailing-slash AIOS_VAULT must still resolve a genuine vault file as vault.
check "trailing-slash vault ownership" "vault" \
  "$(AIOS_VAULT="$VAULT/" sh "$CLS" "$VAULT/AIOS/Skills/propagate.md" 2>/dev/null | sed -n 's/^OWNERSHIP=//p')"

# 11. Prefix-directory attack: a sibling dir whose name merely starts with
# the vault path must not match the vault prefix. (Regression guard.)
mkdir -p "$TMP/vaultdir" "$TMP/vaultdir-evil/skills/x"
printf -- '---\nname: evil\ndescription: d\n---\n' > "$TMP/vaultdir-evil/skills/x/SKILL.md"
check "prefix-directory attack is upstream" "upstream" \
  "$(fieldv "$TMP/vaultdir-evil/skills/x/SKILL.md" "$TMP/vaultdir" OWNERSHIP)"

echo "---"; [ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails FAILED"; exit 1; }
