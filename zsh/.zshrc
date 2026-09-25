# ~/.zshrc: shared by every machine, safe to publish.
# Private or machine-specific settings live in two untracked files:
#   ~/.zshrc.pre.local  sourced first (early exec hooks, zstyles read by oh-my-zsh)
#   ~/.zshrc.local      sourced last  (secrets, ssh keys, per-machine functions)

[[ -r ~/.zshrc.pre.local ]] && source ~/.zshrc.pre.local

typeset -U path fpath                # drop duplicate PATH entries

# ── path ───────────────────────────────────────────────────
path=("$HOME/.local/bin" $path)
[[ -d $HOME/.local/share/fnm ]] && path=("$HOME/.local/share/fnm" $path)   # Linux fnm install

# ── node (fnm) ─────────────────────────────────────────────
# Before oh-my-zsh, so its fnm and npm plugins find their binaries.
(( $+commands[fnm] )) && eval "$(fnm env --use-on-cd --shell zsh)"

# ── oh-my-zsh ──────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""                         # oh-my-posh owns the prompt
[[ -d $HOME/.docker/completions ]] && fpath=("$HOME/.docker/completions" $fpath)  # before compinit

plugins=(git gh docker docker-compose fnm npm kubectl command-not-found)
[[ $OSTYPE == darwin* ]] && plugins+=(brew macos)
plugins+=(zsh-autosuggestions zsh-syntax-highlighting)   # syntax-highlighting must stay last
source $ZSH/oh-my-zsh.sh

# ── history ────────────────────────────────────────────────
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE \
       HIST_REDUCE_BLANKS EXTENDED_HISTORY HIST_VERIFY

# ── prompt ─────────────────────────────────────────────────
# `oh-my-posh init` costs ~150 ms per shell, so its output is cached and
# refreshed whenever oh-my-posh is upgraded. Each shell keeps its own session id.
if (( $+commands[oh-my-posh] )); then
  _omp_init=${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-posh/zshrc-init.zsh
  if [[ ! -s $_omp_init || $commands[oh-my-posh] -nt $_omp_init ]]; then
    mkdir -p ${_omp_init:h}
    oh-my-posh init zsh --config agnoster | sed -E 's/export POSH_SESSION_ID="[^"]*"; *//' >| $_omp_init
  fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    export POSH_SESSION_ID=$(</proc/sys/kernel/random/uuid)
  else
    export POSH_SESSION_ID=${(L)$(uuidgen)}
  fi
  source $_omp_init 2>/dev/null || { rm -f $_omp_init; eval "$(oh-my-posh init zsh --config agnoster)"; }
  unset _omp_init
fi

# ── tools ──────────────────────────────────────────────────
(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd cd)"   # cd learns your dirs; cdi = interactive
if (( $+commands[fzf] )); then
  source <(fzf --zsh 2>/dev/null)    # fzf >= 0.48
  if (( ! $+widgets[fzf-history-widget] )); then   # older distro fzf
    for f in /usr/share/doc/fzf/examples/{key-bindings,completion}.zsh; do [[ -r $f ]] && source $f; done
    unset f
  fi
fi
if (( $+commands[terraform] )); then
  autoload -U +X bashcompinit && bashcompinit
  complete -o nospace -C $commands[terraform] terraform
fi

# ── aliases ────────────────────────────────────────────────
if (( $+commands[eza] )); then
  alias ls='eza --icons=auto'
  alias ll='eza -la --git --icons=auto'
  alias lt='eza --tree --level=2 --icons=auto'
fi
(( $+commands[bat] )) && alias cat='bat'
alias zshconfig='code ~/.zshrc'
alias ohmyzsh='code ~/.oh-my-zsh'

# ── claude ─────────────────────────────────────────────────
# Claude Code's GitHub MCP plugin reads this token. Pass it to Claude only,
# instead of exporting a live token to every process the shell starts.
claude() {
  GITHUB_PERSONAL_ACCESS_TOKEN="$(command gh auth token 2>/dev/null)" command claude "$@"
}

claude-yolo() {
  local deny=(
    # ── 1. Git remote / destructive operations ──
    # "Bash(git push*)"
    "Bash(git remote *)"
    "Bash(git submodule add*)"
    "Bash(git submodule update --remote*)"
    "Bash(git subtree add*)"
    "Bash(git clone *)"
    "Bash(git filter-branch*)"
    "Bash(git rebase -i*)"
    "Bash(git rebase --interactive*)"
    "Bash(git reset --hard*)"
    # "Bash(git tag *)"

    # ── 2. Secret / credential access ──
    "Bash(cat *.env*)"
    "Bash(cat *.pem)"
    "Bash(cat *.key)"
    "Bash(cat *.p12)"
    "Bash(cat *.pfx)"
    "Bash(cat *id_rsa*)"
    "Bash(cat *id_ed25519*)"
    "Bash(cat *aws_credentials*)"
    "Bash(cat */.ssh/*)"
    "Bash(cat */.gnupg/*)"
    "Bash(cat */.aws/*)"
    "Bash(cat */.config/gcloud/*)"
    "Bash(cat */.docker/config.json*)"
    "Bash(printenv*)"
    "Bash(env)"
    "Bash(aws configure*)"
    "Bash(gcloud auth*)"
    "Bash(gh auth*)"
    "Bash(kubectl config view*)"

    # ── 3. Cloud infrastructure (non-Terraform/Ansible) ──
    "Bash(pulumi up*)"
    "Bash(pulumi destroy*)"

    # ── 4. Package publishing ──
    "Bash(npm publish*)"
    "Bash(pnpm publish*)"
    "Bash(yarn publish*)"
    "Bash(pip publish*)"
    "Bash(poetry publish*)"
    "Bash(cargo publish*)"
    "Bash(gem push*)"
    "Bash(docker push*)"
    "Bash(twine upload*)"

    # ── 5. Infrastructure changes ──
    "Bash(kubectl apply*)"
    "Bash(kubectl delete*)"
    "Bash(kubectl scale*)"
    "Bash(helm install*)"
    "Bash(helm upgrade*)"
    "Bash(helm uninstall*)"
    "Bash(docker swarm*)"
    "Bash(docker stack deploy*)"

    # ── 6. Dangerous filesystem operations ──
    "Bash(rm -rf /)"
    "Bash(rm -rf /*)"
    "Bash(rm -rf ~*)"
    "Bash(rm -rf ..*)"
    "Bash(chmod -R 777 /*)"
    "Bash(chown -R */*)"
    "Bash(mkfs*)"
    "Bash(dd if=/dev/*)"
    "Bash(mount *)"
    "Bash(umount *)"

    # ── 7. System-level changes (installs allowed) ──
    "Bash(sudo *)"
    "Bash(systemctl *)"
    "Bash(launchctl *)"
    "Bash(useradd*)"
    "Bash(usermod*)"
    "Bash(passwd*)"

    # ── 8. Background / long-running processes ──
    "Bash(nohup *)"
    "Bash(tmux new*)"
    "Bash(screen *)"
    "Bash(daemonize *)"
    "Bash(crontab *)"
    "Bash(at *)"

    # ── 9. Outbound communications ──
    "Bash(slack *)"
    "Bash(mail *)"
    "Bash(sendmail *)"
    "Bash(smtp*)"
  )

  claude --dangerously-skip-permissions \
    --allowedTools "*" \
    --disallowedTools "${deny[@]}" \
    "$@"
}

[[ -r ~/.zshrc.local ]] && source ~/.zshrc.local
