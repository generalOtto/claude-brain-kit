#!/usr/bin/env bash
# claude-brain-kit — setup. Run once after cloning your (private!) brain repo.
#
#   bash setup.sh              # personalize + wire via @import stub (default)
#   bash setup.sh --symlink    # wire via symlink instead of the import stub
#   bash setup.sh --no-personalize   # skip the name/email prompts (let Claude's
#                                    # first-run interview fill placeholders instead)
#
# Idempotent: safe to re-run. Never deletes anything — existing files are backed up
# with a timestamp suffix. Requires: bash, git, python3 (for settings.json edit).
set -euo pipefail

BRAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
ENTRY="${CLAUDE_DIR}/CLAUDE.md"
TARGET="${BRAIN_DIR}/CLAUDE.md"
MODE="import"
PERSONALIZE="yes"

for arg in "$@"; do
  case "$arg" in
    --symlink) MODE="symlink" ;;
    --no-personalize) PERSONALIZE="no" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "── claude-brain-kit setup ──"
echo "Brain repo: ${BRAIN_DIR}"

# ── 0. Privacy check: warn loudly if this repo looks public ─────────────────────
if command -v gh >/dev/null 2>&1; then
  vis="$(cd "${BRAIN_DIR}" && gh repo view --json visibility -q .visibility 2>/dev/null || true)"
  if [ "${vis}" = "PUBLIC" ]; then
    echo ""
    echo "⚠️  WARNING: this repo is PUBLIC on GitHub. Your brain will contain personal"
    echo "   information — make it private before putting anything real in it:"
    echo "     gh repo edit --visibility private --accept-visibility-change-consequences"
    echo ""
  fi
fi

# ── 1. Personalize {{PLACEHOLDERS}} ────────────────────────────────────────────
if [ "${PERSONALIZE}" = "yes" ] && grep -rql '{{YOUR_NAME}}' "${BRAIN_DIR}" --include='*.md' 2>/dev/null; then
  default_name="$(git config user.name 2>/dev/null || true)"
  printf "Your name [%s]: " "${default_name:-}"
  read -r name
  name="${name:-$default_name}"
  if [ -n "${name}" ]; then
    # Portable in-place sed (BSD/macOS and GNU)
    find "${BRAIN_DIR}" -name '*.md' -not -path '*/.git/*' -exec grep -l '{{YOUR_NAME}}' {} + 2>/dev/null \
      | while IFS= read -r f; do
          tmp="${f}.tmp.$$"
          sed "s/{{YOUR_NAME}}/${name}/g" "${f}" > "${tmp}" && mv "${tmp}" "${f}"
        done
    echo "✓ Personalized placeholders for: ${name}"
  else
    echo "· Skipped personalization (no name given) — Claude's first-run interview will handle it."
  fi
else
  echo "· No placeholders to personalize (already done, or --no-personalize)."
fi

# ── 2. Wire the bootloader into ~/.claude/CLAUDE.md ────────────────────────────
mkdir -p "${CLAUDE_DIR}"
STUB="@${TARGET}"

backup_existing() {
  if [ -e "${ENTRY}" ] && [ ! -L "${ENTRY}" ]; then
    b="${ENTRY}.pre-brain.$(date +%Y%m%d%H%M%S)"
    echo "· Backing up existing ${ENTRY} -> ${b}"
    mv "${ENTRY}" "${b}"
  elif [ -L "${ENTRY}" ]; then
    rm "${ENTRY}"
  fi
}

if [ "${MODE}" = "symlink" ]; then
  if [ -L "${ENTRY}" ] && [ "$(readlink "${ENTRY}")" = "${TARGET}" ]; then
    echo "✓ Already symlinked: ${ENTRY} -> ${TARGET}"
  else
    backup_existing
    ln -s "${TARGET}" "${ENTRY}"
    echo "✓ Symlinked: ${ENTRY} -> ${TARGET}"
  fi
else
  if [ -f "${ENTRY}" ] && [ ! -L "${ENTRY}" ] && grep -qxF "${STUB}" "${ENTRY}" 2>/dev/null; then
    echo "✓ Import stub already in place: ${ENTRY} contains '${STUB}'"
  else
    backup_existing
    printf '%s\n' "${STUB}" > "${ENTRY}"
    echo "✓ Wrote import stub: ${ENTRY} -> '${STUB}'"
  fi
fi

# ── 3. Transcript retention ────────────────────────────────────────────────────
# Claude Code deletes session transcripts idle longer than cleanupPeriodDays
# (default 30). Raise it so your history survives — recall depends on it.
SETTINGS="${CLAUDE_DIR}/settings.json" python3 - <<'PY'
import json, os
p = os.environ["SETTINGS"]
d = json.load(open(p)) if os.path.exists(p) else {}
if d.get("cleanupPeriodDays", 0) < 3650:
    d["cleanupPeriodDays"] = 3650
    tmp = p + ".tmp"
    json.dump(d, open(tmp, "w"), indent=2)
    os.replace(tmp, p)
    print("✓ cleanupPeriodDays set to 3650 in", p)
else:
    print("✓ cleanupPeriodDays already >= 3650")
PY

# ── 4. Optional: gitleaks pre-commit hook ──────────────────────────────────────
HOOK="${BRAIN_DIR}/.git/hooks/pre-commit"
if command -v gitleaks >/dev/null 2>&1; then
  if [ ! -e "${HOOK}" ]; then
    printf "Install gitleaks pre-commit hook (blocks committing secrets)? [Y/n]: "
    read -r yn
    if [ "${yn:-Y}" != "n" ] && [ "${yn:-Y}" != "N" ]; then
      cat > "${HOOK}" <<'EOF'
#!/usr/bin/env bash
exec gitleaks protect --staged --config "$(git rev-parse --show-toplevel)/.gitleaks.toml"
EOF
      chmod +x "${HOOK}"
      echo "✓ gitleaks pre-commit hook installed"
    fi
  else
    echo "· pre-commit hook already exists — left untouched."
  fi
else
  echo "· gitleaks not installed — skipping pre-commit hook (CI still scans on push)."
  echo "  To add later: install gitleaks (brew install gitleaks) and re-run setup.sh"
fi

echo ""
echo "Done. Verify: start a Claude Code session anywhere and ask \"what do you know"
echo "about me?\" — or run /context and check that CLAUDE.md loaded. On a brand-new"
echo "brain, Claude will offer to interview you. Let it."
