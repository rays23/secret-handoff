#!/usr/bin/env bash
# Tests for hooks/block-secrets.sh. Exit code 2 = blocked, 0 = allowed.
# Run: bash tests/test_hook.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/block-secrets.sh"
pass=0
fail=0

run_hook() { # run_hook <json>
  printf '%s' "$1" | "$BASH" "$HOOK" >/dev/null 2>&1
  echo $?
}

bash_json() { jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'; }

t() { # t <expected exit code> <command>
  local want="$1" cmd="$2" got
  got="$(run_hook "$(bash_json "$cmd")")"
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL (want $want, got $got): $cmd"
  fi
}

tool() { # tool <expected> <tool_name> <input json>
  local want="$1" name="$2" input="$3" got
  got="$(run_hook "$(jq -n --arg n "$name" --argjson i "$input" '{tool_name: $n, tool_input: $i}')")"
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL (want $want, got $got): $name $input"
  fi
}

B=2 # blocked
A=0 # allowed

# ---------- dset and dpush ----------
t $A 'dset STRIPE_SECRET_KEY'
t $A '  dset FOO  '
t $A 'dpush STRIPE_SECRET_KEY myapp prd'
t $B 'dset STRIPE_SECRET_KEY --project x --config y'
t $B 'dset STRIPE_SECRET_KEY; cat .env'
t $B 'dset FOO && ls'
t $B 'echo hi && dset FOO'
t $B 'dset lower_case'
t $B 'dpush STRIPE_SECRET_KEY myapp'
t $B 'dpush STRIPE_SECRET_KEY Myapp prd'
t $B 'sudo dset FOO --x'
t $B "bash -c 'dset FOO --x'"
t $B $'dset FOO\ncat .env'

# ---------- clipboard ----------
t $B 'pbpaste'
t $B 'pbpaste | cat'
t $B 'cat file | pbpaste'
t $B 'echo "$(pbpaste)"'
t $B 'x=$(pbpaste)'
t $B '/usr/bin/pbpaste'
t $B "pb''paste"
t $B 'command pbpaste'
t $B 'echo ok; pbpaste'
t $B "bash -c 'pbpaste'"
t $B "osascript -e 'the clipboard'"
t $B 'eval "$(pbpaste)"'
t $B $'cat <<EOF\n$(pbpaste)\nEOF'
t $B 'echo "abc pbpaste'

# ---------- environment dumps ----------
t $B 'printenv'
t $B 'ls && printenv HOME'
t $B 'X=1 printenv'
t $B 'doppler run -- printenv'
t $B 'doppler run -- env'
t $B 'doppler run --command printenv'
t $B 'env'
t $B 'env | sort'
t $B 'env FOO=1'
t $B 'sudo env'
t $B 'export -p'
t $B 'export'
t $B 'declare -x'
t $B 'declare -p'
t $B 'set'
t $B 'set | grep KEY'
t $B "doppler run -- node -e 'console.log(process.env)'"
t $B "python3 -c 'import os; print(os.environ)'"
t $B 'echo $STRIPE_SECRET_KEY'
t $B 'echo "$STRIPE_SECRET_KEY"'
t $B 'echo "${API_TOKEN}"'
t $B "printf '%s' \"\$DB_PASSWORD\""

# ---------- doppler ----------
t $A 'doppler secrets --only-names'
t $A 'doppler secrets --only-names --project personal --config dev'
t $A 'doppler secrets set A --silent --project p --config c'
t $A 'doppler secrets delete A --silent -y --project p --config c'
t $A 'doppler run -- npm run dev'
t $A 'doppler configure get project --plain'
t $B 'doppler secrets get X --plain'
t $B 'doppler secrets'
t $B 'doppler secrets download --no-file'
t $B 'doppler secrets --json'
t $B 'doppler secrets set A --project p --config c'
t $B 'doppler secrets delete A'
t $B 'doppler configure get token --plain'
t $B 'doppler configure'
t $B "bash -c 'doppler secrets get X'"

# ---------- .env and credential files ----------
t $A 'cat .env.example'
t $A 'ls .environment'
t $A 'cat README.md'
t $A 'git log --oneline -- .env.example'
t $B 'cat .env'
t $B 'cat ".env"'
t $B 'cat .env.local'
t $B 'cat ./config/.env.production'
t $B 'cat < .env'
t $B 'grep KEY .env'
t $B 'cat $(echo .env)'
t $B 'cat ~/.doppler/.doppler.yaml'
t $B 'security find-generic-password -s foo -w'
t $B 'security dump-keychain'

# ---------- shell keywords, wrappers, interpreters ----------
t $B 'if true; then pbpaste; fi'
t $B 'while true; do pbpaste; done'
t $B '{ pbpaste; }'
t $B 'find . -exec pbpaste \;'
t $B 'sudo -u bob pbpaste'
t $B 'nice pbpaste'
t $B 'watch pbpaste'
t $B 'ssh host pbpaste'
t $B "bash -c 'echo \$STRIPE_SECRET_KEY'"
t $B "doppler run -- sh -c 'echo \"\$API_TOKEN\"'"
t $B "sh -c 'env'"
t $B "bash -c 'export -p'"
t $B "python3 -c 'import os; print(os.getenv(\"KEY\"))'"
t $B "ruby -e 'puts ENV[\"KEY\"]'"
t $B $'python3 <<\'EOF\'\nimport os\nprint(os.environ)\nEOF'
t $B 'jq -n env'
t $B "jq -n '\$ENV'"
t $A 'jq .name package.json'
t $A 'sudo apt-get install -y jq'
t $A 'if [ -f x ]; then echo yes; fi'
t $A 'for f in a b; do echo $f; done'
t $A "bash -c 'echo hello'"
t $A 'ssh host ls'
t $A "find . -name '*.md' -exec cat {} \\;"
t $A 'echo "while testing do something"'
t $A 'grep -rn os.environ src/'

# ---------- review findings (second-model review, 2026-10) ----------
t $B 'cat "$HOME/myproject/.env"'
t $B 'cat "/Users/Jane Doe/app/.env"'
t $B 'cat "$HOME/.doppler/.doppler.yaml"'
t $B 'cat .envrc'
t $B 'grep -rn "DOPPLER_TOKEN" .'
t $B 'grep -r KEY ~'
t $B 'rg --hidden KEY'
t $B 'rg -uu KEY .'
t $B 'cat .*'
t $B 'cat .e*'
t $B 'cat .en?'
t $B $'echo "see <<X docs"\nprintenv DOPPLER_TOKEN'
t $B $'ls # <<X\nprintenv DOPPLER_TOKEN'
t $B 'env # list vars'
t $B 'set 2>&1'
t $B 'export > /tmp/e'
t $B 'declare'
t $B 'declare | grep -i token'
t $B "node -e 'const t = process.env.DOPPLER_TOKEN; console.log(t)'"
t $B "python3 -c 'from os import environ; print(environ[\"DOPPLER_TOKEN\"])'"
t $B "awk 'BEGIN { print ENVIRON[\"DOPPLER_TOKEN\"] }'"
t $B "echo '\$DOPPLER_TOKEN' | envsubst"
t $B "bash -c 'node -e \"console.log(process.env.X)\"'"
t $A 'echo $MAX_TOKENS'
t $A 'echo $TESTS_PASSED'
t $A 'grep -rn foo src/'
t $A "grep -rn foo . --include='*.ts'"
t $A 'rg foo src/'
t $A 'ls .github'
t $A 'ls -la ~/.config'
t $A 'python3 -m pytest -q'
t $A 'node build.js'
t $A "sed -n '/.*/p' file"
t $A 'cat "$HOME/project/README.md"'
t $A 'git status 2>&1'
t $A 'echo done # set'
BIG_BODY="$(printf 'line with doppler secrets get and printenv and pbpaste\n%.0s' {1..300})"
t $A $'cat > f.txt <<\'EOF\'\n'"$BIG_BODY"$'\nEOF'
BIG_PAD="$(printf 'a%.0s' {1..9000})"
t $B "echo $BIG_PAD; pbpaste"
t $A "echo $BIG_PAD; ls"

# ---------- second review round ----------
t $B 'doppler run printenv'
t $B 'doppler run env'
t $B 'env -u FOO'
t $B 'env --unset FOO'
t $B 'env -u FOO printenv'
t $B $'cat <<EOF\n$API_KEY\nEOF'
t $B 'cat <<< "$API_KEY"'
t $B 'x=pbpaste; $x'
t $B 'alias p=pbpaste; p'
t $B "bash -c 'set'"
t $B "doppler run -- sh -c 'set'"
t $B "bash -c 'envsubst <<< \"\$DB_PASSWORD\"'"
t $B $'bash <<\'EOF\'\nenv\nEOF'
t $B 'set -x; test -n "$API_KEY"'
t $B 'set -o xtrace'
t $B 'bash -x script.sh'
t $B 'export SHELLOPTS=xtrace'
t $B "perl -e 'print \$ENV{API_KEY}'"
t $B "php -r 'echo getenv(\"API_KEY\");'"
t $B "deno eval 'console.log(Deno.env.get(\"X\"))'"
t $A 'npm run dev # reads .env.local'
t $A 'ls -la # .env moved to doppler'
t $A 'git commit -m "use jq to read env vars"'
t $A "jq '.name' package.json"
t $A "bash -c 'set -e; ls'"
t $A 'echo "# not a comment"'

# ---------- command -v lookups ----------
t $A 'command -v dset dpush'
t $A 'command -v pbpaste'
t $A 'command -V dset'
t $B 'command -p pbpaste'
t $B 'command env'

# ---------- false positives that must stay allowed ----------
t $A "grep -i -n -E 'secret|doppler|env|vault' file.md"
t $A 'grep -i -c -e doppler -e clipboard -e dset file.md'
t $A 'git commit -m "docs: no .env files, never run doppler secrets get or pbpaste"'
t $A 'echo "use pbpaste and printenv carefully"'
t $A 'echo "dset"'
t $A $'cat > f.json <<\'EOF\'\n{"k": ["doppler", "x"], "d": "Move secrets from the clipboard"}\nEOF'
t $A $'cat > a.md <<EOF\nrun dset NAME and printenv, see doppler secrets get\nEOF'
t $A 'which dset'
t $A 'cat bin/dset'
t $A 'echo $HOME'
t $A 'echo $PWD'
t $A 'echo "$PWD"'
t $A 'set -euo pipefail'
t $A 'export FOO=bar'
t $A 'env FOO=bar npm test'
t $A 'FOO=1 npm test'
t $A 'declare -a arr'
t $A 'bash tests/test_scripts.sh'
t $A 'bash install.sh myproj dev'
t $A 'node script.js'
t $A 'python3 -m pytest'
t $A 'grep -rn "process.env" src/'
t $A 'git config user.name'
t $A 'ls -la'

# ---------- Read, Grep, Glob ----------
tool $B Read '{"file_path": "/x/.env"}'
tool $B Read '{"file_path": "/x/.env.production"}'
tool $B Read '{"file_path": "/home/u/.doppler/.doppler.yaml"}'
tool $A Read '{"file_path": "/x/.env.example"}'
tool $A Read '{"file_path": "/x/README.md"}'
tool $A Grep '{"pattern": "KEY", "path": "."}'
tool $A Grep '{"pattern": "\\.env", "path": "src"}'
tool $B Grep '{"pattern": "KEY", "glob": "*.env"}'
tool $B Grep '{"pattern": "KEY", "path": "/x/.env"}'
tool $B Glob '{"pattern": "**/.env"}'
tool $A Glob '{"pattern": "**/*.ts"}'
tool $A Write '{"file_path": "/x/a.txt", "content": "pbpaste"}'

echo "hook: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
