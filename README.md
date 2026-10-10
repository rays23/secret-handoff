# secret-handoff

Move a secret from your clipboard into [Doppler](https://www.doppler.com) without Claude Code ever seeing the value.

You copy a key, run one command, and the key lands in a Doppler "depot". From there, `dpush` copies it into the projects that need it. A guard hook blocks the commands that would pull secret values into the conversation.

```text
copy key  →  /secret-handoff:add-secret STRIPE_SECRET_KEY myapp dev  →  done
             │
             ├─ dset   clipboard → depot, verified by hash, clipboard cleared
             └─ dpush  depot → myapp/dev, verified by hash
```

Claude only handles the secret **name**. The value goes through the clipboard and stdin of the Doppler CLI, never through the model's context, the command line, or the output.

## Requirements

- macOS (uses `pbpaste` and `pbcopy`). Linux support with `xclip` or `wl-paste` is welcome as a pull request.
- [Doppler CLI](https://docs.doppler.com/docs/install-cli), logged in with `doppler login`
- `jq`, `shasum`, bash 3.2 or newer (the macOS system bash works)
- Claude Code with plugin support

```bash
brew install dopplerhq/cli/doppler jq
doppler login
```

## Install

```text
/plugin marketplace add rays23/secret-handoff
/plugin install secret-handoff@secret-handoff
/secret-handoff:setup
```

`/secret-handoff:setup` asks which Doppler config is the depot, checks that it is clean, writes `~/.config/secret-handoff/config`, and installs `dset` and `dpush` into `~/.local/bin` so they also work in a normal terminal tab.

### Choosing the depot

The depot is one Doppler config that only holds secrets on their way to other projects.

- Best: a dedicated project with an otherwise empty config, for example project `depot`, config `prd`.
- Also fine: an empty root config such as `stg` in an existing project.
- Avoid branch configs. They inherit every secret of their root config, so `dpush` could copy those too.

## Daily use

| Goal | How |
|---|---|
| Store a secret | Copy the value, then `/secret-handoff:add-secret NAME` in Claude Code, or `dset NAME` in a terminal tab |
| Store and distribute | `/secret-handoff:add-secret NAME myapp dev myapp prd` |
| Distribute later | Ask Claude to push `NAME` to `myapp/prd`. It runs `dpush NAME myapp prd` |
| See the setup | `/secret-handoff:status` |

`dset NAME` prints one line, for example `✓ STRIPE_SECRET_KEY new in depot/prd (verified), clipboard cleared.` The value is never printed.

## The commands

**`dset SECRET_NAME`** reads the clipboard, stores it in the depot through stdin (`doppler secrets set --silent`), reads it back, compares SHA-256 hashes, and clears the clipboard. If the hashes differ, it exits with an error and leaves the clipboard untouched.

**`dpush SECRET_NAME TARGET_PROJECT TARGET_CONFIG`** copies a secret from the depot to a target. It verifies by hash as well. The depot copy stays, so you can push to several targets. Delete it with `doppler secrets delete NAME --silent -y --project <depot> --config <depot-config>` when you are done.

Secret names must be `UPPER_SNAKE_CASE`. Project and config names must be lowercase Doppler slugs.

## What the guard hook blocks

The plugin registers a `PreToolUse` hook for `Bash`, `Read`, `Grep` and `Glob`. It blocks:

- the clipboard: `pbpaste`, AppleScript `the clipboard`
- environment dumps: `printenv`, bare `env`, `set`, `export -p`, `declare -x`, `echo $SOMETHING_KEY`, `process.env` and `os.environ` dumps in code snippets
- `.env` files (`.env.example` is allowed) and the Doppler CLI config `~/.doppler`
- `doppler secrets get`, `download`, `substitute`, listing without `--only-names`, `set` and `delete` without `--silent`, and `doppler configure` (except `get project` and `get config`)
- the macOS keychain: `security find-generic-password`, `dump-keychain`, `export`
- `dset` and `dpush` in any form except `dset NAME` and `dpush NAME PROJECT CONFIG`, so Claude cannot pass flags or chain commands

Quoted text and heredoc bodies are ignored. A `grep 'env|doppler'` or a commit message that mentions `.env` passes. Commands run by interpreters and wrappers (`bash -c`, `eval`, `python`, `node`, `xargs`, and similar) are scanned as plain text instead, because their code is hidden in strings.

Blocked commands return exit code 2 and a reason that Claude reads.

## Limitations

This is a guardrail, not a sandbox. Read this before you rely on it.

- **Heuristic, not a parser.** The hook does not understand all of shell syntax. A determined command can get around it, for example by building a command name from pieces, or by running a script that Claude first wrote to disk. A tested secret guard from another project leaked on 5 of 14 shell commands. Treat the hook as protection against accidents and ordinary prompts, not against an attacker who controls the prompt.
- **False positives.** Mentions of `.env` or `pbpaste` in a script string run by an interpreter are blocked, and so is a URL that ends in `/.env`. Rephrase or run the command yourself with the `!` prefix.
- **Plugins cannot ship permission rules.** The deny rules from `/secret-handoff:setup` are a second layer that you add to your own settings. A plugin also cannot protect its own files from edits.
- **Grep over directories.** Claude Code's Grep tool honors `.gitignore`, so a gitignored `.env` is normally skipped, but a tracked or unignored `.env` can show up in matches.
- **The clipboard is shared.** If something else is in the clipboard when `dset` runs, that gets stored. The output shows the name and target, never the value.
- **Clipboard managers** (Raycast, Paste, Maccy) and Universal Clipboard keep a history. Exclude your password manager there.
- **Session logs.** Values that Claude read before you installed this stay in plain text in `~/.claude/projects/*/*.jsonl`. Search for known key prefixes, rotate what you find, and delete the logs.
- **The depot is a shared waiting room.** Anyone with access to the depot config can read what is in it. Delete secrets from it once pushed.
- **Doppler token.** The hook blocks the common ways to print it, but the token still lives on your machine. Use a service token with minimal scope for CI.

## Uninstall

```text
/plugin uninstall secret-handoff
```

```bash
rm ~/.local/bin/dset ~/.local/bin/dpush ~/.local/bin/handoff-lib.sh
rm -r ~/.config/secret-handoff
```

## Development

```bash
bash tests/test_hook.sh      # guard hook, no network
bash tests/test_scripts.sh   # dset, dpush, install.sh with stubbed doppler and clipboard
shellcheck -S warning -x -s bash bin/* install.sh hooks/block-secrets.sh tests/*.sh tests/stubs/*
```

The tests use stubs for `doppler`, `pbpaste` and `pbcopy`. They never touch a real Doppler account or your clipboard. Both suites run under the macOS system bash 3.2 and bash 5.

## Licence

MIT
