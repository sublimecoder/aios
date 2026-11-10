#!/usr/bin/env bash
# Self-check for link-global.sh. Uses a temp vault + temp dests; never touches
# ~/.claude/skills or ~/.agents/skills.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$2] got [$3]"; fails=$((fails+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# link-global.sh finds its own skills dir via `dirname "$0"` (no AIOS_VAULT
# hook), so the fixture copies the real script next to fixture skills — this
# exercises the actual code path, not a stand-in.
mkdir -p "$TMP/vault/skills/grilling" "$TMP/dest"
echo "x" > "$TMP/vault/skills/grilling/SKILL.md"
echo "flat note" > "$TMP/vault/skills/draft.md"          # must never be linked
mkdir -p "$TMP/vault/skills/notaskill"                    # no SKILL.md, must be ignored
cp "$HERE/link-global.sh" "$TMP/vault/skills/link-global.sh"
LINKER="$TMP/vault/skills/link-global.sh"

run() { AIOS_LINK_DESTS="$TMP/dest" sh "$LINKER" "$@" 2>&1; }

# 1. Links a real skill dir.
run >/dev/null
check "skill symlinked" "1" "$([ -L "$TMP/dest/grilling" ] && echo 1 || echo 0)"

# 2. Never links flat .md notes, dirs lacking SKILL.md, or the linker itself.
check "flat note not linked" "0" "$([ -e "$TMP/dest/draft.md" ] && echo 1 || echo 0)"
check "non-skill dir not linked" "0" "$([ -e "$TMP/dest/notaskill" ] && echo 1 || echo 0)"
check "linker script not linked" "0" "$([ -e "$TMP/dest/link-global.sh" ] && echo 1 || echo 0)"

# 3. Idempotent: second run does not duplicate or fail.
run >/dev/null
check "idempotent rerun" "1" "$([ -L "$TMP/dest/grilling" ] && echo 1 || echo 0)"

# 4. THE IMPORTANT ONE: refuses to clobber a real directory.
rm "$TMP/dest/grilling"; mkdir -p "$TMP/dest/grilling"; echo "precious" > "$TMP/dest/grilling/SKILL.md"
out="$(run)"
check "real dir survives" "precious" "$(cat "$TMP/dest/grilling/SKILL.md")"
check "collision reported" "1" "$(printf '%s\n' "$out" | grep -c '^COLLISION')"

# 5. Refuses a foreign symlink it did not create.
rm -rf "$TMP/dest/grilling"; ln -s /etc "$TMP/dest/grilling"
out="$(run)"
check "foreign symlink untouched" "/etc" "$(readlink "$TMP/dest/grilling")"
check "foreign symlink reported" "1" "$(printf '%s\n' "$out" | grep -c '^COLLISION')"

# 6. Space-path destination must not be word-split (AIOS_LINK_DESTS is colon-separated).
SPACE_DEST="$TMP/space dest"
out="$(AIOS_LINK_DESTS="$SPACE_DEST" sh "$LINKER" 2>&1)"
check "space-path skill symlinked in exact dir" "1" "$([ -L "$SPACE_DEST/grilling" ] && echo 1 || echo 0)"
check "no stray dir named after first word" "0" "$([ -e "$TMP/space" ] && echo 1 || echo 0)"

# 7. A symlink pointing at a DIFFERENT skill's source (stale cross-link) must
#    be reported as a collision, not silently relinked to this skill's source.
mkdir -p "$TMP/vault/skills/otherskill"
echo "y" > "$TMP/vault/skills/otherskill/SKILL.md"
rm -rf "$TMP/dest/grilling"
ln -s "$TMP/vault/skills/otherskill" "$TMP/dest/grilling"
out="$(run)"
check "cross-link reported as collision" "1" "$(printf '%s\n' "$out" | grep -c '^COLLISION')"
check "cross-link not silently relinked" "$TMP/vault/skills/otherskill" "$(readlink "$TMP/dest/grilling")"
rm -rf "$TMP/vault/skills/otherskill" "$TMP/dest/grilling"

# 8. An explicitly-EMPTY AIOS_LINK_DESTS must refuse, never fall back to the
#    user's real skill directories (`${VAR-default}` vs `${VAR:-default}`).
#    Three agents reached production through that fallback while believing
#    they were sandboxed.
out="$(AIOS_LINK_DESTS="" sh "$LINKER" 2>&1)"; rc=$?
check "empty dests exits 1" "1" "$rc"
check "empty dests refuses" "1" "$(printf '%s\n' "$out" | grep -c 'refusing to fall back')"
check "empty dests linked nothing" "0" "$(printf '%s\n' "$out" | grep -c '^LINK')"

# 9. Two colon-separated destinations both get the skill (the ~/.claude/skills
#    + ~/.agents/skills default shape).
D1="$TMP/dest1"; D2="$TMP/dest2"
out="$(AIOS_LINK_DESTS="$D1:$D2" sh "$LINKER" 2>&1)"
check "first of two dests linked" "1" "$([ -L "$D1/grilling" ] && echo 1 || echo 0)"
check "second of two dests linked" "1" "$([ -L "$D2/grilling" ] && echo 1 || echo 0)"

# 10. --dry-run creates nothing: no destination root, no links.
D3="$TMP/dest-dry"
out="$(AIOS_LINK_DESTS="$D3" sh "$LINKER" --dry-run 2>&1)"
check "dry-run creates no dest root" "0" "$([ -e "$D3" ] && echo 1 || echo 0)"
check "dry-run reports DRY lines" "1" "$(printf '%s\n' "$out" | grep -c '^DRY')"

# 11. A destination root that is itself a symlink resolving into the vault is
#     skipped, never written into (would otherwise recurse symlinks back into
#     our own tree).
D4="$TMP/dest-vault-link"
ln -s "$TMP/vault" "$D4"
out="$(AIOS_LINK_DESTS="$D4" sh "$LINKER" 2>&1)"
check "vault-recursion dest skipped" "1" "$(printf '%s\n' "$out" | grep -c '^SKIP')"
check "vault-recursion dest gets no LINK line" "0" "$(printf '%s\n' "$out" | grep -c '^LINK')"

# 12. --adopt: replaces a REAL directory only when it is byte-identical to the
#     vault's copy, and never otherwise. This is the mode that reclaims the 21
#     skill directories jcode's own installer copied into ~/.jcode/skills, so
#     both halves matter: adopting an identical tree is a no-op for every reader
#     and makes vault edits live, while adopting a DIFFERING tree would delete
#     whatever made it differ. The branch runs `rm -rf`, so the refusal half is
#     the one that keeps that safe.
D5="$TMP/dest-adopt"
mkdir -p "$D5/grilling"
cp "$TMP/vault/skills/grilling/SKILL.md" "$D5/grilling/SKILL.md"     # identical copy

# Default (no flag) still refuses — adoption must never be implicit.
out="$(AIOS_LINK_DESTS="$D5" sh "$LINKER" 2>&1)"
check "identical copy refused without --adopt" "0" "$([ -L "$D5/grilling" ] && echo 1 || echo 0)"
check "refusal mentions --adopt as the way forward" "1" "$(printf '%s\n' "$out" | grep -c -- '--adopt')"

# --dry-run --adopt reports the adoption without performing it.
out="$(AIOS_LINK_DESTS="$D5" sh "$LINKER" --adopt --dry-run 2>&1)"
check "dry-run adopt reports ADOPT" "1" "$(printf '%s\n' "$out" | grep -c 'DRY  ADOPT')"
check "dry-run adopt changes nothing" "0" "$([ -L "$D5/grilling" ] && echo 1 || echo 0)"

# The real thing: identical copy becomes a symlink to the vault.
out="$(AIOS_LINK_DESTS="$D5" sh "$LINKER" --adopt 2>&1)"
check "identical copy adopted" "1" "$([ -L "$D5/grilling" ] && echo 1 || echo 0)"
# Compare against the PHYSICAL vault path: the script resolves its own location
# with `pwd -P` (deliberately, per its header), and on macOS $TMPDIR lives under
# /var -> /private/var, so the link legitimately reads /private/var/... while
# $TMP still says /var/.... Asserting the raw $TMP string fails on a correct link.
VAULT_P="$(CDPATH= cd "$TMP/vault/skills/grilling" && pwd -P)"
check "adopted link points at the vault" "$VAULT_P" "$(readlink "$D5/grilling")"

# A DIFFERING directory is refused even with --adopt, and its content survives.
D6="$TMP/dest-adopt-diff"
mkdir -p "$D6/grilling"
cp "$TMP/vault/skills/grilling/SKILL.md" "$D6/grilling/SKILL.md"
echo "local edit" >> "$D6/grilling/SKILL.md"
out="$(AIOS_LINK_DESTS="$D6" sh "$LINKER" --adopt 2>&1)"
check "differing copy NOT adopted" "0" "$([ -L "$D6/grilling" ] && echo 1 || echo 0)"
check "differing copy content preserved" "1" "$(grep -c 'local edit' "$D6/grilling/SKILL.md")"
check "differing copy reported as DIFFERS" "1" "$(printf '%s\n' "$out" | grep -c 'DIFFERS')"

# A skill is its whole TREE, not just SKILL.md: a matching SKILL.md beside a
# differing helper file must still refuse, or --adopt deletes the helper.
D7="$TMP/dest-adopt-tree"
mkdir -p "$TMP/vault/skills/grilling/scripts" "$D7/grilling/scripts"
echo "real helper" > "$TMP/vault/skills/grilling/scripts/run.sh"
cp "$TMP/vault/skills/grilling/SKILL.md" "$D7/grilling/SKILL.md"
echo "DIFFERENT helper" > "$D7/grilling/scripts/run.sh"
out="$(AIOS_LINK_DESTS="$D7" sh "$LINKER" --adopt 2>&1)"
check "tree with differing helper NOT adopted" "0" "$([ -L "$D7/grilling" ] && echo 1 || echo 0)"
check "differing helper preserved" "1" "$(grep -c 'DIFFERENT helper' "$D7/grilling/scripts/run.sh")"
rm -rf "$TMP/vault/skills/grilling/scripts"

echo "---"; [ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails FAILED"; exit 1; }
