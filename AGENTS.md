# AGENTS.md

How to change this repository safely. [README.md](README.md) explains what it is and how to install it; [docs/statusline.md](docs/statusline.md) describes what the status line prints.

## Layout

| Path | Language | Role |
|---|---|---|
| `zsh/.zshrc` | zsh | The shared shell configuration |
| `zsh/zshrc.local.example` | zsh | Template for the untracked `~/.zshrc.local` |
| `claude/statusline-command.sh` | POSIX sh | Claude Code status line |
| `install.sh` | bash | Symlinks the two files above into `$HOME` |
| `scripts/check.sh` | bash | Every check; CI runs exactly this |
| `scripts/render-preview.py` | Python 3, standard library | Regenerates `docs/statusline.svg` |
| `tests/fixtures/*.json` | JSON | Sample status line inputs, in the shape Claude Code sends |
| `.github/workflows/check.yml` | GitHub Actions | Runs the checks on Ubuntu and macOS, plus a gitleaks scan of the full history |

## Rules

1. **The repository is public.** Never commit a secret, token, email address, hostname, username, ssh key name, private path, or employer or client name. Those belong in `~/.zshrc.local` or `~/.zshrc.pre.local` on the machine that needs them; `.gitignore` excludes both. gitleaks catches strings that look like secrets, not names, so review every diff for personal details yourself.

2. **Edits are live.** On a machine where `install.sh` has run, `~/.zshrc` and `~/.claude/statusline-command.sh` are symlinks into the clone. A change to the checked-out branch reaches every new shell and the next status line refresh at once. Work on a separate branch or worktree, run the checks, then merge.

3. **The shell must start on a bare machine.** Guard each tool with `(( $+commands[name] ))` or a file test, and keep macOS-only plugins behind the `$OSTYPE` check. Startup must stay fast: no network calls, and cache any slow `init` output the way the oh-my-posh block does.

4. **The status line must stay cheap and portable.** It runs under dash on Ubuntu and bash on macOS, so use POSIX `sh` only. Parse the input with the single existing `jq` call, add no dependencies, and never touch the network. When something is missing it prints a one-line explanation and exits 0; keep it that way.

5. **Documentation moves with the code.** When the status line changes what it prints, update [docs/statusline.md](docs/statusline.md) and the header comment in the script, then run `scripts/render-preview.py` and commit the new `docs/statusline.svg`. When the status line reads a new input field, add it to a fixture in `tests/fixtures/`. When the shell gains or loses a feature, update "The shell" section of the README.

## Checks

```sh
./scripts/check.sh
```

It needs zsh, shellcheck and jq; the secret scan runs when gitleaks is installed and always runs in CI. It checks zsh syntax, lints the scripts with shellcheck, renders every fixture under `sh` and `bash` at three widths, confirms the status line's error messages, and runs `install.sh` against a temporary home directory. Add new checks to this script, not to the workflow file, so local runs and CI stay identical.

`scripts/check.sh` cannot see interactive behaviour. After changing `.zshrc`, also open a new shell, confirm the prompt, completions and key bindings work, and time startup with `time zsh -i -c exit`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org): `type(scope): subject` in the imperative, with a body that explains why. Keep history linear: rebase onto `main` and merge fast-forward only.
