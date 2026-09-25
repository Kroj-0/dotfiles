#!/bin/sh
# Claude Code status line: three lines covering the model and workspace, the
# context window, and spend and rate limits. Reads the session JSON that
# Claude Code sends on stdin. docs/statusline.md documents every segment.

LC_NUMERIC=C
input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf 'statusline: jq not found in PATH\n'
  exit 0
fi

# ── Single jq pass: every field the harness provides ──────────────────────────
eval "$(printf '%s' "$input" | jq -r '
[
  "SESSION_ID=\(.session_id // ""                                    | @sh)",
  "TRANSCRIPT=\(.transcript_path // ""                               | @sh)",
  "CWD=\(.workspace.current_dir // .cwd // ""                        | @sh)",
  "PROJ=\(.workspace.project_dir // ""                               | @sh)",
  "NADDED=\((.workspace.added_dirs // []) | length                   | @sh)",
  "SNAME=\(.session_name // ""                                       | @sh)",
  "MODEL=\(.model.display_name // "Claude"                           | @sh)",
  "MODEL_ID=\(.model.id // ""                                        | @sh)",
  "EFFORT=\(.effort.level // ""                                      | @sh)",
  "VERSION=\(.version // ""                                          | @sh)",
  "STYLE=\(.output_style.name // ""                                  | @sh)",
  "VIM=\(.vim.mode // ""                                             | @sh)",
  "FAST=\(.fast_mode // false      | tostring                        | @sh)",
  "THINK=\(.thinking.enabled // false | tostring                     | @sh)",
  "BIG=\(.exceeds_200k_tokens // false | tostring                    | @sh)",
  "COST=\(.cost.total_cost_usd // 0                                  | @sh)",
  "DUR_MS=\((.cost.total_duration_ms // 0)     | floor               | @sh)",
  "API_MS=\((.cost.total_api_duration_ms // 0) | floor               | @sh)",
  "ADD=\((.cost.total_lines_added // 0)        | floor               | @sh)",
  "DEL=\((.cost.total_lines_removed // 0)      | floor               | @sh)",
  "BURN=\(if (.cost.total_duration_ms // 0) > 0
          then ((.cost.total_cost_usd // 0) * 3600000 / .cost.total_duration_ms)
          else 0 end                                                 | @sh)",
  "CTX_PCT=\((.context_window.used_percentage // 0)  | floor         | @sh)",
  "CTX_SIZE=\((.context_window.context_window_size // 0) | floor     | @sh)",
  "CU_IN=\((.context_window.current_usage.input_tokens // 0)  | floor | @sh)",
  "CU_OUT=\((.context_window.current_usage.output_tokens // 0) | floor | @sh)",
  "CU_CW=\((.context_window.current_usage.cache_creation_input_tokens // 0) | floor | @sh)",
  "CU_CR=\((.context_window.current_usage.cache_read_input_tokens // 0)     | floor | @sh)",
  "CTX_USED=\(((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)) | floor | @sh)",
  "FIVE=\((.rate_limits.five_hour.used_percentage // -1)  | floor    | @sh)",
  "FIVE_R=\((.rate_limits.five_hour.resets_at // 0)       | floor    | @sh)",
  "SEVEN=\((.rate_limits.seven_day.used_percentage // -1) | floor    | @sh)",
  "SEVEN_R=\((.rate_limits.seven_day.resets_at // 0)      | floor    | @sh)"
] | join("\n")
' 2>/dev/null)"

[ -n "${MODEL:-}" ] || { printf 'statusline: could not parse input\n'; exit 0; }

COLS=${COLUMNS:-100}
case "$COLS" in ''|*[!0-9]*) COLS=100 ;; esac

# Detail tier: how much fits on one line at this width.
#   3 = wide (everything)  2 = normal  1 = compact  0 = narrow (essentials only)
if   [ "$COLS" -ge 150 ]; then TIER=3
elif [ "$COLS" -ge 110 ]; then TIER=2
elif [ "$COLS" -ge 88 ];  then TIER=1
else TIER=0; fi

# ── Palette (real ESC bytes, so payload text is never re-interpreted) ─────────
E=$(printf '\033')
RST="${E}[0m";  BOLD="${E}[1m";  ITAL="${E}[3m"
# Three deliberate gray levels. Nothing stacks the SGR "dim" attribute on top of
# a color: dim + bright-black lands near 3:1 contrast on a dark background,
# which is what made the old palette hard to read.
TXT="${E}[38;5;252m"    # values that are secondary but still meant to be read
MUTE="${E}[38;5;247m"   # unit labels, annotations   (~7:1 on #1e1e1e)
FAINT="${E}[38;5;243m"  # purely structural glyphs   (~3.7:1, decoration only)
RED="${E}[38;5;210m";    GREEN="${E}[38;5;114m";  YELLOW="${E}[38;5;222m"
BLUE="${E}[38;5;111m";   MAGENTA="${E}[38;5;176m"; CYAN="${E}[38;5;80m"
WHITE="${E}[38;5;255m"
SEP="${FAINT} │ ${RST}"
DOT="${FAINT} · ${RST}"

# ── Helpers ───────────────────────────────────────────────────────────────────
pct_color() {
  if   [ "$1" -lt 50 ]; then printf '%s' "$GREEN"
  elif [ "$1" -lt 70 ]; then printf '%s' "$CYAN"
  elif [ "$1" -lt 85 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$RED"; fi
}

# bar <pct> <width> <fill-char> <empty-char>
bar() {
  p=$1; w=$2; f=$3; e=$4
  [ "$p" -lt 0 ] && p=0
  [ "$p" -gt 100 ] && p=100
  n=$(( p * w / 100 ))
  [ "$n" -eq 0 ] && [ "$p" -gt 0 ] && n=1
  fill=''; i=0
  while [ "$i" -lt "$n" ]; do fill="${fill}${f}"; i=$((i+1)); done
  trough=''
  while [ "$i" -lt "$w" ]; do trough="${trough}${e}"; i=$((i+1)); done
  printf '%s%s%s%s%s' "$(pct_color "$p")" "$fill" "$FAINT" "$trough" "$RST"
}

# fmt_tok <int>  →  912 / 9.1k / 51k / 1.2M
fmt_tok() {
  t=$1
  if   [ "$t" -ge 1000000 ]; then printf '%d.%01dM' $((t/1000000)) $(((t%1000000)/100000))
  elif [ "$t" -ge 100000 ];  then printf '%dk' $((t/1000))
  elif [ "$t" -ge 1000 ];    then printf '%d.%01dk' $((t/1000)) $(((t%1000)/100))
  else printf '%d' "$t"; fi
}

# fmt_dur <ms> → 43s / 7m12s / 2h05m
fmt_dur() {
  s=$(( $1 / 1000 ))
  if   [ "$s" -ge 3600 ]; then printf '%dh%02dm' $((s/3600)) $(((s%3600)/60))
  elif [ "$s" -ge 60 ];   then printf '%dm%02ds' $((s/60)) $((s%60))
  else printf '%ds' "$s"; fi
}

# fmt_eta <epoch> <now> → 9m / 2h13m / 1d7h
fmt_eta() {
  d=$(( $1 - $2 ))
  if   [ "$d" -le 0 ];    then printf 'now'
  elif [ "$d" -lt 3600 ]; then printf '%dm' $((d/60))
  elif [ "$d" -lt 86400 ]; then printf '%dh%02dm' $((d/3600)) $(((d%3600)/60))
  else printf '%dd%dh' $((d/86400)) $(((d%86400)/3600)); fi
}

# trunc <string> <max-chars>  (no subprocess; counts characters in bash, bytes in dash)
trunc() {
  s=$1; m=$2
  [ "$m" -lt 4 ] && { printf ''; return; }
  while [ ${#s} -gt "$m" ]; do s=${s%?}; done
  [ "$s" != "$1" ] && s="${s%?}…"
  printf '%s' "$s"
}

now_line=$(date '+%s %H:%M')
NOW=${now_line% *}
CLOCK=${now_line#* }

# ══ LINE 1 ════════════════════════════════════════════════════════════════════

# model — pull the context-size suffix out of the display name into a badge
CTX_BADGE=''
case "$MODEL" in
  *' (1M context)') MODEL=${MODEL% (1M context)}; CTX_BADGE='1M' ;;
esac
l1="${BOLD}${CYAN}${MODEL}${RST}"
[ -n "$CTX_BADGE" ] && l1="${l1}${BLUE} ${CTX_BADGE}${RST}"

# reasoning effort (authoritative, from .effort.level)
case "$EFFORT" in
  low)     l1="${l1}${BLUE} lo${RST}" ;;
  medium)  l1="${l1}${CYAN} med${RST}" ;;
  high)    l1="${l1}${YELLOW} hi${RST}" ;;
  xhigh)   l1="${l1}${MAGENTA} xhi${RST}" ;;
  max)     l1="${l1}${BOLD}${MAGENTA} max${RST}" ;;
  '') ;;
  *)       l1="${l1}${MUTE} ${EFFORT}${RST}" ;;
esac

[ "$THINK" = "true" ] && l1="${l1}${MAGENTA} ∴${RST}"
[ "$FAST" = "true" ]  && l1="${l1}${BOLD}${YELLOW} ⚡${RST}"

# permission mode — from the transcript, memoised so it survives long sessions
PM=''
PM_CACHE=''
if [ -n "$SESSION_ID" ]; then
  PM_DIR="${HOME}/.claude/cache/statusline"
  PM_CACHE="${PM_DIR}/${SESSION_ID}.mode"
fi
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  PM=$(tail -c 262144 "$TRANSCRIPT" 2>/dev/null | awk '
    match($0, /"permissionMode":"[a-zA-Z]+"/) {
      s = substr($0, RSTART + 18, RLENGTH - 19)
    } END { print s }')
fi
if [ -n "$PM" ]; then
  if [ -n "$PM_CACHE" ]; then
    [ -d "$PM_DIR" ] || mkdir -p "$PM_DIR" 2>/dev/null
    cached=''; [ -f "$PM_CACHE" ] && IFS= read -r cached < "$PM_CACHE" 2>/dev/null
    [ "$PM" = "$cached" ] || printf '%s\n' "$PM" >"$PM_CACHE" 2>/dev/null
  fi
elif [ -n "$PM_CACHE" ] && [ -f "$PM_CACHE" ]; then
  IFS= read -r PM < "$PM_CACHE" 2>/dev/null
fi
case "$PM" in
  bypassPermissions) l1="${l1} ${BOLD}${RED}[bypass]${RST}" ;;
  plan)              l1="${l1} ${BOLD}${BLUE}[plan]${RST}" ;;
  acceptEdits)       l1="${l1} ${YELLOW}[accept]${RST}" ;;
  auto)              l1="${l1} ${YELLOW}[auto]${RST}" ;;
  default|'') ;;
  *)                 l1="${l1} ${MUTE}[${PM}]${RST}" ;;
esac

# vim mode
case "$VIM" in
  NORMAL) l1="${l1} ${BOLD}${BLUE}N${RST}" ;;
  INSERT) l1="${l1} ${BOLD}${GREEN}I${RST}" ;;
  '') ;;
  *)      l1="${l1} ${MUTE}${VIM}${RST}" ;;
esac

# non-default output style
case "$STYLE" in
  ''|default|normal) ;;
  *) l1="${l1}${MUTE} ⚑${STYLE}${RST}" ;;
esac

# cwd — ~-collapsed, last two segments, marked when not at the project root
disp=$CWD
if [ -n "$disp" ]; then
case "$disp" in "$HOME") disp='~' ;; "$HOME"/*) disp="~${disp#"$HOME"}" ;; esac
short=$disp
case "$disp" in
  */*/*) tail2=${disp#"${disp%/*/*}/"}; [ "$tail2" != "$disp" ] && short="…/$tail2" ;;
esac
l1="${l1}${SEP}${WHITE}${short}${RST}"
[ -n "$PROJ" ] && [ "$CWD" != "$PROJ" ] && l1="${l1}${YELLOW}*${RST}"
[ "${NADDED:-0}" -gt 0 ] && l1="${l1}${MUTE}+${NADDED}d${RST}"
fi

# git — 1 rev-parse + 1 porcelain=v2 scan, stash counted from the reflog file
GITROOT=$CWD
[ -d "$GITROOT" ] || GITROOT=.
GITDIR=$(git -C "$GITROOT" rev-parse --absolute-git-dir 2>/dev/null)
if [ -n "$GITDIR" ]; then
  gs=$(git -C "$GITROOT" status --porcelain=v2 --branch 2>/dev/null | awk '
    /^# branch\.head /     { head = $3 }
    /^# branch\.upstream / { up = $3 }
    /^# branch\.ab /       { ahead = substr($3,2) + 0; behind = substr($4,2) + 0 }
    /^[12] / { x = substr($2,1,1); y = substr($2,2,1)
               if (x != ".") staged++
               if (y != ".") dirty++ }
    /^u /    { conflict++ }
    /^\? /   { untracked++ }
    END { printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d",
                 head, (up == "" ? "-" : "+"), ahead, behind,
                 staged, dirty, conflict, untracked }')
  OIFS=$IFS; IFS='	'   # a literal tab: the field separator awk printed above
  # shellcheck disable=SC2086
  set -- $gs
  IFS=$OIFS
  gbranch=${1:-}; gup=${2:--}; gahead=${3:-0}; gbehind=${4:-0}
  gstaged=${5:-0}; gdirty=${6:-0}; gconf=${7:-0}; guntr=${8:-0}

  gstash=0
  if [ -f "$GITDIR/logs/refs/stash" ]; then
    while IFS= read -r _; do gstash=$((gstash+1)); done < "$GITDIR/logs/refs/stash"
  fi

  if [ -n "$gbranch" ]; then
    case "$gbranch" in
      '(detached)') gseg="${MAGENTA}⌥ detached${RST}" ;;
      *)            gseg="${MAGENTA}⌥ $(trunc "$gbranch" 24)${RST}" ;;
    esac
    [ "$gup" = "-" ] && gseg="${gseg}${MUTE}↯${RST}"
    [ "$gstaged" -gt 0 ] && gseg="${gseg} ${GREEN}●${gstaged}${RST}"
    [ "$gdirty"  -gt 0 ] && gseg="${gseg} ${YELLOW}✚${gdirty}${RST}"
    [ "$guntr"   -gt 0 ] && gseg="${gseg} ${MUTE}?${guntr}${RST}"
    [ "$gconf"   -gt 0 ] && gseg="${gseg} ${BOLD}${RED}!${gconf}${RST}"
    [ "$gstash"  -gt 0 ] && gseg="${gseg} ${BLUE}⚑${gstash}${RST}"
    [ "$gahead"  -gt 0 ] && gseg="${gseg} ${CYAN}↑${gahead}${RST}"
    [ "$gbehind" -gt 0 ] && gseg="${gseg} ${RED}↓${gbehind}${RST}"
    l1="${l1}  ${gseg}"
  fi
fi

# session title — up to COLUMNS-62 characters, at most 44
if [ -n "$SNAME" ]; then
  budget=$(( COLS - 62 ))
  [ "$budget" -gt 44 ] && budget=44
  if [ "$budget" -ge 8 ]; then
    l1="${l1}${SEP}${ITAL}${MUTE}$(trunc "$SNAME" "$budget")${RST}"
  fi
fi

# ══ LINE 2 — context ══════════════════════════════════════════════════════════

if   [ "$COLS" -ge 120 ]; then BW=22
elif [ "$COLS" -ge 100 ]; then BW=18
elif [ "$COLS" -ge 80 ];  then BW=14
else BW=10; fi

CTX_FREE=$(( CTX_SIZE - CTX_USED ))
[ "$CTX_FREE" -lt 0 ] && CTX_FREE=0
CC=$(pct_color "$CTX_PCT")

if [ "$CTX_SIZE" -ge 1000000 ]; then csize="$(( CTX_SIZE / 1000000 ))M"
elif [ "$CTX_SIZE" -ge 1000 ]; then csize="$(( CTX_SIZE / 1000 ))k"
else csize="$CTX_SIZE"; fi

l2="${MUTE}ctx${RST} $(bar "$CTX_PCT" "$BW" '━' '╌') ${CC}${BOLD}$(printf '%3d' "$CTX_PCT")%${RST}"
l2="${l2}${TXT} $(fmt_tok "$CTX_USED")${MUTE}/${csize}${RST}"
if [ "$TIER" -ge 1 ]; then
  l2="${l2}${DOT}${GREEN}$(fmt_tok "$CTX_FREE")${RST}${MUTE} free${RST}"
else
  l2="${l2}${MUTE} (${RST}${GREEN}$(fmt_tok "$CTX_FREE")${MUTE})${RST}"
fi

# cache efficiency of the current window
cin=$(( CU_IN + CU_CW + CU_CR ))
if [ "$cin" -gt 0 ] && [ "$TIER" -ge 1 ]; then
  hit=$(( CU_CR * 100 / cin ))
  if [ "$hit" -ge 80 ]; then hc=$GREEN; elif [ "$hit" -ge 50 ]; then hc=$YELLOW; else hc=$RED; fi
  l2="${l2}${DOT}${MUTE}cache${RST} ${hc}${hit}%${RST}"
  [ "$TIER" -ge 3 ] && l2="${l2}${MUTE} (rd $(fmt_tok "$CU_CR") wr $(fmt_tok "$CU_CW") new $(fmt_tok "$CU_IN"))${RST}"
fi

if [ "$ADD" -gt 0 ] || [ "$DEL" -gt 0 ]; then
  l2="${l2}${SEP}${GREEN}+${ADD}${RST}${FAINT}/${RST}${RED}-${DEL}${RST}"
fi

# long-context pricing tier
[ "$BIG" = "true" ] && l2="${l2}${DOT}${BOLD}${YELLOW}≫200k${RST}"

# heads-up before auto-compaction
if [ "$CTX_PCT" -ge 90 ]; then
  [ "$TIER" -ge 2 ] && l2="${l2}${DOT}${BOLD}${RED}⚠ compacting soon${RST}" || l2="${l2} ${BOLD}${RED}⚠${RST}"
elif [ "$CTX_PCT" -ge 80 ]; then
  [ "$TIER" -ge 2 ] && l2="${l2}${DOT}${YELLOW}⚠ ctx filling${RST}" || l2="${l2} ${YELLOW}⚠${RST}"
fi

# ══ LINE 3 — spend & limits ═══════════════════════════════════════════════════

l3="${GREEN}\$$(printf '%.2f' "$COST")${RST}"
if [ "$DUR_MS" -gt 30000 ] && [ "$TIER" -ge 1 ]; then
  l3="${l3}${MUTE} \$$(printf '%.2f' "$BURN")/h${RST}"
fi

if [ "$DUR_MS" -gt 0 ]; then
  l3="${l3}${SEP}${TXT}$(fmt_dur "$DUR_MS")${RST}"
  if [ "$API_MS" -gt 0 ] && [ "$TIER" -ge 2 ]; then
    apct=$(( API_MS * 100 / DUR_MS ))
    if [ "$TIER" -ge 3 ]; then
      l3="${l3}${MUTE} (api $(fmt_dur "$API_MS") ${apct}%)${RST}"
    else
      l3="${l3}${MUTE} (api ${apct}%)${RST}"
    fi
  fi
fi

if [ "$FIVE" -ge 0 ]; then
  seg="${MUTE}5h${RST} $(bar "$FIVE" 5 '▮' '▯') $(pct_color "$FIVE")$(printf '%2d' "$FIVE")%${RST}"
  [ "$FIVE_R" -gt 0 ] && [ "$TIER" -ge 1 ] && seg="${seg}${MUTE}→$(fmt_eta "$FIVE_R" "$NOW")${RST}"
  l3="${l3}${SEP}${seg}"
fi
if [ "$SEVEN" -ge 0 ]; then
  seg="${MUTE}7d${RST} $(bar "$SEVEN" 5 '▮' '▯') $(pct_color "$SEVEN")$(printf '%2d' "$SEVEN")%${RST}"
  [ "$SEVEN_R" -gt 0 ] && [ "$TIER" -ge 1 ] && seg="${seg}${MUTE}→$(fmt_eta "$SEVEN_R" "$NOW")${RST}"
  l3="${l3}${DOT}${seg}"
fi

[ "$TIER" -ge 1 ] && l3="${l3}${SEP}${MUTE}${CLOCK}${RST}"
[ -n "$VERSION" ] && [ "$TIER" -ge 2 ] && l3="${l3}${MUTE} v${VERSION}${RST}"

# ══ Output ════════════════════════════════════════════════════════════════════
printf '%s\n%s\n%s\n' "$l1" "$l2" "$l3"
