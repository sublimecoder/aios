# ✂️ Ponytail amendment — dead-code asymmetry

**An extension to the ponytail plugin.** Kept in the vault (not inline in the
plugin cache) so a plugin upgrade can't clobber it, and version-controlled here
like [[effort-table]] and [[reasoning-doctrine]]. Import it from your global agent
config so it reaches every repo on the machine.

**Scope-neutral infra** — pure code hygiene, no identity content, so the import
crosses no wall.

## Rule
When editing existing code:
- Orphans **your** change created (now-unused imports/vars/functions) → remove them.
- Pre-existing dead code → mention it, don't delete unless asked.

Ponytail preaches "deletion over addition"; this draws the line it leaves implicit —
your mess is yours to clean, the codebase's pre-existing mess is not yours to touch.

## Changelog
- Created; the one rule from the Karpathy guidelines (§3, Surgical Changes) not
  already covered by ponytail + [[reasoning-doctrine]]. Wired as a global import.
