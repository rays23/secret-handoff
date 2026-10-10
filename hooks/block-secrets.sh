#!/usr/bin/env bash
# secret-handoff guard hook (PreToolUse).
# Blocks tool calls that would pull secret values into the Claude Code context.
# Exit 0 = allow. Exit 2 = block (stderr goes to Claude as the reason).
# Compatible with bash 3.2 (macOS system bash).
#
# This is a heuristic guard, not a sandbox. See README "Limitations".
#
# How a Bash command is checked:
#   1. The two exact forms 'dset NAME' and 'dpush NAME PROJECT CONFIG' are allowed at once.
#   2. Heredoc bodies and quoted text are removed, so words inside arguments (a grep pattern,
#      a commit message) do not trigger rules. Text that the shell would execute stays
#      ($(...), backticks, expansions inside double quotes).
#   3. The rules look for dangerous words at command position (start of the command, after
#      ; & | ( or --, after sudo/env/VAR=x prefixes).
#   4. Interpreters and wrappers (bash -c, eval, python, node, xargs, ...) run code from strings
#      that we cannot parse. For those the rules also run over the whole text, like a grep.

command -v jq >/dev/null 2>&1 || {
  echo "secret-handoff: jq is missing, the guard hook is NOT active. Install jq." >&2
  exit 1
}

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"

block() {
  echo "BLOCKED (secret-handoff): $1" >&2
  exit 2
}

# ---------- .env and credential files ----------

RE_ENVFILE='(^|[^[:alnum:]_])\.env(\.[[:alnum:]_-]+)?([^[:alnum:]_.-]|$)'
RE_CREDFILE='(^|[^[:alnum:]_])\.doppler([^[:alnum:]_-]|$)'

refs_envfile() {
  local s="${1//.env.example/}"
  [[ "$s" =~ $RE_ENVFILE ]]
}

refs_credfile() {
  [[ "$1" =~ $RE_CREDFILE ]]
}

# ---------- preprocessing: heredocs ----------

RE_HEREDOC=$'(^|[^<])<<(-?)[[:space:]]*(\'[^\']*\'|"[^"]*"|\\\\?[A-Za-z_][A-Za-z0-9_]*)'

# Removes heredoc bodies. Bodies of quoted heredocs (<<'EOF') are plain text and are dropped.
# Bodies of unquoted heredocs undergo expansion, so each line is kept as a double-quoted string.
preprocess() {
  local raw="$1" line cmp d body out="" in_hd=0 hd_delim="" hd_dash=0 hd_quoted=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hd)); then
      cmp="$line"
      if ((hd_dash)); then cmp="${cmp#"${cmp%%[!$'\t']*}"}"; fi
      if [[ "$cmp" == "$hd_delim" ]]; then
        in_hd=0
        continue
      fi
      if ((!hd_quoted)); then
        body="${line//\\/\\\\}"
        body="${body//\"/\\\"}"
        out+="\"$body\""$'\n'
      fi
      continue
    fi
    out+="$line"$'\n'
    if [[ "$line" =~ $RE_HEREDOC ]]; then
      d="${BASH_REMATCH[3]}"
      hd_dash=0
      [[ "${BASH_REMATCH[2]}" == "-" ]] && hd_dash=1
      in_hd=1
      case "${d:0:1}" in
        "'" | '"') hd_delim="${d:1:${#d}-2}"; hd_quoted=1 ;;
        '\') hd_delim="${d:1}"; hd_quoted=1 ;;
        *) hd_delim="$d"; hd_quoted=0 ;;
      esac
    fi
  done <<<"$raw"
  printf '%s' "$out"
}

# ---------- tokenizer: build the "skeleton" ----------
# Output (global SK): the command with quoted text removed. Kept: unquoted text, command
# substitutions, variable references inside double quotes, and quoted text that is a single
# plain word (so that pb''paste is still seen as pbpaste).
# UNTERM=1 means the command has unbalanced quotes or parentheses.

s=""
n=0
i=0
out=""
UNTERM=0
DQRAW=""

RE_PLAINWORD='^[A-Za-z0-9_./=:@%+,-]*$'

emit_literal() {
  if [[ "$1" =~ $RE_PLAINWORD ]]; then
    out+="$1"
  else
    out+=" "
  fi
}

# Called after the opening double quote. Consumes through the closing quote.
scan_dq() {
  local start=$i c rest
  while ((i < n)); do
    c="${s:i:1}"
    if [[ "$c" == '\' ]]; then
      i=$((i + 2))
      continue
    fi
    if [[ "$c" == '"' ]]; then
      DQRAW="${s:start:i-start}"
      i=$((i + 1))
      return 0
    fi
    if [[ "$c" == '$' ]]; then
      if [[ "${s:i:2}" == '$(' ]]; then
        i=$((i + 2))
        out+=' $( '
        scan_normal ')' || return 1
        out+=' ) '
        continue
      fi
      rest="${s:i}"
      if [[ "$rest" =~ ^\$(\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z_][A-Za-z0-9_]*) ]]; then
        out+=" ${BASH_REMATCH[0]} "
        i=$((i + ${#BASH_REMATCH[0]}))
        continue
      fi
    fi
    if [[ "$c" == '`' ]]; then
      i=$((i + 1))
      out+=' ` '
      scan_normal '`' || return 1
      out+=' ` '
      continue
    fi
    i=$((i + 1))
  done
  UNTERM=1
  return 1
}

# term: ')' inside $( ... ), '`' inside backticks, '' at top level.
scan_normal() {
  local term="$1" c depth=0 start content
  while ((i < n)); do
    c="${s:i:1}"
    case "$c" in
      '\')
        out+="${s:i:2}"
        i=$((i + 2))
        ;;
      "'")
        i=$((i + 1))
        start=$i
        while ((i < n)) && [[ "${s:i:1}" != "'" ]]; do i=$((i + 1)); done
        if ((i >= n)); then
          UNTERM=1
          return 1
        fi
        content="${s:start:i-start}"
        i=$((i + 1))
        emit_literal "$content"
        ;;
      '"')
        i=$((i + 1))
        scan_dq || return 1
        emit_literal "$DQRAW"
        ;;
      '`')
        i=$((i + 1))
        if [[ "$term" == '`' ]]; then return 0; fi
        out+=' ` '
        scan_normal '`' || return 1
        out+=' ` '
        ;;
      '$')
        if [[ "${s:i:2}" == '$(' ]]; then
          i=$((i + 2))
          out+=' $( '
          scan_normal ')' || return 1
          out+=' ) '
        elif [[ "${s:i:2}" == "\$'" ]]; then
          i=$((i + 1)) # ANSI-C quoting: drop the $, the quote is handled next round
        else
          out+='$'
          i=$((i + 1))
        fi
        ;;
      '(')
        depth=$((depth + 1))
        out+='('
        i=$((i + 1))
        ;;
      ')')
        if [[ "$term" == ')' && $depth -eq 0 ]]; then
          i=$((i + 1))
          return 0
        fi
        depth=$((depth - 1))
        out+=')'
        i=$((i + 1))
        ;;
      $'\n')
        out+=';'
        i=$((i + 1))
        ;;
      *)
        out+="$c"
        i=$((i + 1))
        ;;
    esac
  done
  [[ -z "$term" ]] && return 0
  UNTERM=1
  return 1
}

tokenize() {
  s="$1"
  n=${#s}
  i=0
  out=""
  UNTERM=0
  scan_normal '' || UNTERM=1
  SK="$out"
}

# ---------- rules ----------

# Command position: start, after ; & | ( ` or --, then optional prefixes (sudo, env, VAR=x) and a path.
SKIP_ENV='((sudo|command|exec|nohup|time|builtin|noglob|env)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
SKIP_NOENV='((sudo|command|exec|nohup|time|builtin|noglob)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
PATHP='([^[:space:];&|()`]*/)?'
CP_HEAD='(^|[;&|(`]|--)[[:space:]]*'
P_CP="${CP_HEAD}${SKIP_ENV}${PATHP}"
P_CP_NOENV="${CP_HEAD}${SKIP_NOENV}${PATHP}"
P_ANY='(^|[^[:alnum:]_.-])'

WORD_END='([^[:alnum:]_.-]|$)'

# Rules that also run over the full text for wrappers (prefix P decides command position or anywhere).
scan_core() {
  local t="$1" p="$2" mode="$3" re
  re="${p}(dset|dpush)${WORD_END}"
  [[ "$t" =~ $re ]] && block "dset and dpush are allowed only as 'dset NAME' or 'dpush NAME PROJECT CONFIG', without flags or chaining."
  re="${p}pbpaste${WORD_END}"
  [[ "$t" =~ $re ]] && block "Direct clipboard access. Copy the secret and run 'dset NAME'."
  re="${p}printenv${WORD_END}"
  [[ "$t" =~ $re ]] && block "printenv prints secret values."
  re="${p}security[[:space:]]+(find-(generic|internet)-password|dump-keychain|export)([[:space:]]|\$)"
  [[ "$t" =~ $re ]] && block "Keychain access."
  if [[ "$mode" == any ]]; then
    [[ "$t" =~ the[[:space:]]+clipboard ]] && block "Clipboard access through a script."
  fi
  scan_doppler "$t" "$p"
}

scan_doppler() {
  local t="$1" p="$2" re
  re="${p}doppler[^;&|]*[[:space:]]secrets([[:space:]]|\$)"
  if [[ "$t" =~ $re ]]; then
    [[ "$t" =~ secrets[[:space:]]+(get|download|substitute) ]] && block "doppler secrets get/download/substitute return values. Use --only-names."
    if [[ "$t" =~ secrets[[:space:]]+(set|delete) ]]; then
      [[ "$t" =~ --silent ]] || block "doppler secrets set/delete only with --silent (otherwise Doppler prints the values)."
    elif [[ ! "$t" =~ --only-names ]]; then
      block "To list secrets use 'doppler secrets --only-names'."
    fi
  fi
  re="${p}doppler[^;&|]*[[:space:]]configure"
  if [[ "$t" =~ $re ]]; then
    [[ "$t" =~ configure[[:space:]]+get[[:space:]]+(project|config)([[:space:]]|\$) ]] || block "doppler configure can print the auth token."
  fi
}

# Rules for command position only (they would give false positives as a plain grep).
scan_cp_only() {
  local t="$1" re
  re="${P_CP_NOENV}env([[:space:]]+(-[^[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*))*[[:space:]]*(\$|[;&|)\`])"
  [[ "$t" =~ $re ]] && block "'env' without a command prints secret values."
  re="${P_CP}(set|export)[[:space:]]*(\$|[;&|)\`])"
  [[ "$t" =~ $re ]] && block "Environment dump (set / export)."
  re="${P_CP}(export|declare|typeset)[[:space:]]+-[[:alnum:]]*[px]([[:space:]]|\$)"
  [[ "$t" =~ $re ]] && block "Environment dump (export -p / declare -x / declare -p)."
  re="${P_CP}(echo|printf)[^;&|]*\\$\\{?[A-Za-z0-9_]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss])"
  [[ "$t" =~ $re ]] && block "echo/printf of a variable that looks like a secret."
}

RE_DUMP='process\.env[[:space:]]*[),]|console\.log\([^)]*process\.env|os\.environ|ENV\.to_h|\$_ENV'
RE_WRAPPER="${P_CP}(bash|sh|zsh|dash|ksh|eval|source|xargs|python[0-9.]*|node|perl|ruby|osascript|timeout)([[:space:]]|\$)"
RE_DOPPLER_CMDSTR="${P_CP}doppler[^;&|]*[[:space:]](--command|-c)([[:space:]=]|\$)"

RE_DSET_OK='^[[:space:]]*dset[[:space:]]+[A-Z][A-Z0-9_]*[[:space:]]*$'
RE_DPUSH_OK='^[[:space:]]*dpush[[:space:]]+[A-Z][A-Z0-9_]*[[:space:]]+[a-z0-9][a-z0-9_-]*[[:space:]]+[a-z0-9][a-z0-9_-]*[[:space:]]*$'

# ---------- main ----------

case "$tool" in
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    [[ -z "$cmd" ]] && exit 0

    # 1) The two allowed forms
    [[ "$cmd" =~ $RE_DSET_OK ]] && exit 0
    [[ "$cmd" =~ $RE_DPUSH_OK ]] && exit 0

    # 2) Preprocess and tokenize
    text="$(preprocess "$cmd")"
    tokenize "$text"

    # 3) Raw text rules
    [[ "$text" =~ $RE_DUMP ]] && block "Printing environment variables from a code snippet."

    # 4) Command-position rules on the skeleton
    scan_core "$SK" "$P_CP" cp
    scan_cp_only "$SK"
    refs_envfile "$SK" && block ".env files are off limits. Secrets live in Doppler. .env.example is allowed."
    refs_credfile "$SK" && block "The Doppler CLI config can hold the auth token."

    # 5) Wrappers and unparseable commands: run the core rules over the full text
    wrapper=0
    ((UNTERM)) && wrapper=1
    [[ "$SK" =~ $RE_WRAPPER ]] && wrapper=1
    [[ "$SK" =~ $RE_DOPPLER_CMDSTR ]] && wrapper=1
    if ((wrapper)); then
      scan_core "$text" "$P_ANY" any
      refs_envfile "$text" && block ".env files are off limits (found inside a script string)."
      refs_credfile "$text" && block "The Doppler CLI config can hold the auth token (found inside a script string)."
    fi
    exit 0
    ;;

  Read | Grep | Glob)
    paths="$(jq -r '[.tool_input.file_path, .tool_input.path, .tool_input.glob] + (if .tool_name == "Glob" then [.tool_input.pattern] else [] end) | map(select(. != null)) | join("\n")' <<<"$input")"
    refs_envfile "$paths" && block ".env files are off limits."
    refs_credfile "$paths" && block "The Doppler CLI config can hold the auth token."
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
