#!/usr/bin/env bash
# Run every check that CI runs. Stops at the first failure.
# Needs zsh, shellcheck and jq; the secret scan runs when gitleaks is installed.
set -euo pipefail

cd "$(dirname "$0")/.."
repo=$PWD
statusline=claude/statusline-command.sh

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

step "zsh syntax"
for file in zsh/.zshrc zsh/zshrc.local.example; do
  zsh -n "$file" || fail "$file"
done

step "shellcheck"
shellcheck install.sh scripts/check.sh
shellcheck --shell=sh "$statusline"

step "python syntax"
python3 -m py_compile scripts/render-preview.py
rm -rf scripts/__pycache__

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

step "status line renders every fixture"
# One width per level of detail: below 88, 88-109, 110-149, 150 and up.
for shell in sh bash; do
  for fixture in tests/fixtures/*.json; do
    model=$(jq -r '.model.display_name | sub(" \\(1M context\\)$"; "")' "$fixture")
    for columns in 60 100 130 160; do
      label="$shell, $(basename "$fixture"), $columns columns"
      output=$(COLUMNS=$columns "$shell" "$statusline" < "$fixture" 2> "$scratch/stderr")
      [ ! -s "$scratch/stderr" ] || fail "$label: wrote to stderr: $(head -n 1 "$scratch/stderr")"
      [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 3 ] || fail "$label: expected 3 lines"
      printf '%s\n' "$output" | head -n 1 | grep -qF "$model" || fail "$label: model name missing"
    done
  done
  echo "ok  $shell"
done

step "status line explains bad input instead of failing"
[ "$(printf '' | sh "$statusline")" = "statusline: could not parse input" ] || fail "empty input"
mkdir "$scratch/bin"
ln -s "$(command -v cat)" "$scratch/bin/cat"   # a PATH with cat but no jq
[ "$(PATH=$scratch/bin /bin/sh "$statusline" < tests/fixtures/minimal.json)" = "statusline: jq not found in PATH" ] \
  || fail "missing jq"
echo "ok"

step "install.sh links, is idempotent, and backs up changed files"
home=$scratch/home
mkdir "$home"
HOME=$home ./install.sh > /dev/null
[ "$(readlink "$home/.zshrc")" = "$repo/zsh/.zshrc" ] || fail ".zshrc not linked"
[ "$(readlink "$home/.claude/statusline-command.sh")" = "$repo/$statusline" ] || fail "status line not linked"
[ "$(HOME=$home ./install.sh | grep -c '^ok ')" -eq 2 ] || fail "second run was not a no-op"
rm "$home/.zshrc"
echo "# edited by hand" > "$home/.zshrc"
HOME=$home ./install.sh > /dev/null
[ -L "$home/.zshrc" ] || fail "changed file not replaced by link"
ls "$home"/.zshrc.bak-* > /dev/null 2>&1 || fail "changed file not backed up"
echo "ok"

step "no secrets in history"
if command -v gitleaks > /dev/null; then
  gitleaks git --no-banner --redact --log-level warn . || fail "gitleaks found secrets"
  echo "ok"
else
  echo "skipped: gitleaks not installed"
fi

printf '\nAll checks passed.\n'
