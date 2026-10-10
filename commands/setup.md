---
description: Choose the depot (Doppler project and config) for secret-handoff and install dset and dpush
argument-hint: [DEPOT_PROJECT DEPOT_CONFIG]
allowed-tools: Bash(command -v:*), Bash(doppler projects:*), Bash(doppler configs:*), Bash(doppler secrets --only-names:*), Read
---

Set up secret-handoff. Arguments: $ARGUMENTS

The depot is one Doppler config that only holds secrets on their way to other projects. `dset` writes to it, `dpush` copies from it.

Rules (not negotiable):
- You never read, print or ask for a secret value. You only work with names.
- You do not edit the user's settings files. You show the snippet from step 5 and let the user decide.

Steps:
1. Check the tools with `command -v doppler`, `command -v jq`, `command -v pbpaste`, `command -v shasum`.
   If one is missing, tell the user how to install it (macOS: `brew install dopplerhq/cli/doppler jq`) and stop.
   If `doppler` is not logged in, tell the user to run `doppler login` themselves and stop.
2. Pick the depot.
   - If $ARGUMENTS has two values, use them as project and config.
   - Otherwise run `doppler projects` and ask the user which project and config to use.
   - Recommend a dedicated config that holds no other secrets. A fresh project with a config named `prd` is ideal.
     A root config such as `stg` of an existing project also works if it is empty. Avoid branch configs: they inherit secrets from their root config.
3. Check the choice with `doppler secrets --only-names --project <P> --config <C>`.
   A clean depot lists only names that start with `DOPPLER_`. If other names appear, warn the user that `dpush` can then copy those secrets too,
   and ask whether to continue or choose another config.
4. Run `bash "${CLAUDE_PLUGIN_ROOT}/install.sh" <P> <C>`. This writes `~/.config/secret-handoff/config` and installs `dset` and `dpush` to `~/.local/bin`
   so they also work in a normal terminal tab. Tell the user to re-run this command after a plugin update.
5. Show the user these deny rules. A plugin cannot ship permission rules, so the user adds them to `permissions.deny` in their own settings:

   ```json
   "Read(**/.env)", "Read(**/.env.*)", "Bash(pbpaste:*)", "Bash(printenv:*)",
   "Bash(doppler secrets get:*)", "Bash(doppler secrets download:*)"
   ```

   Explain that the guard hook already blocks these cases, and the rules are a second layer. Do not write them yourself.
6. Finish with the daily flow: copy a secret, run `/secret-handoff:add-secret NAME`, or type `dset NAME` in another terminal tab.
