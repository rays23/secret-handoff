---
description: Move the secret in the clipboard into the depot, optionally push it to projects and wire its name into the app
argument-hint: SECRET_NAME [PROJECT CONFIG ...]
allowed-tools: Bash(dset:*), Bash(dpush:*), Bash(doppler secrets --only-names:*), Bash(doppler run:*), Read, Edit, Grep, Glob
---

The user copied a secret value to the clipboard. Arguments: $ARGUMENTS
The first argument is the secret name. Further arguments are pairs of target project and config.

Rules (not negotiable):
- You never see, read or print the value. You only work with the name.
- No clipboard access, no .env files, no `doppler secrets get` or `download`, no `printenv`.
- Use `dset` and `dpush` only in their exact form without flags: `dset NAME` and `dpush NAME PROJECT CONFIG`.
- If a step would need the value, stop and ask the user.
- If `dset` reports that no depot is configured, tell the user to run `/secret-handoff:setup` and stop.

Steps:
1. Check that the name is UPPER_SNAKE_CASE and fits the naming in the target repo
   (existing names via `doppler secrets --only-names`). If it differs, ask briefly.
2. Run `dset <NAME>`. The target is always the configured depot.
3. For each given pair of project and config, run `dpush <NAME> <PROJECT> <CONFIG>`.
   With no pairs, skip this step and ask at the end where the secret should go.
4. Check with `doppler secrets --only-names --project <PROJECT> --config <CONFIG>` that the name exists in each target.
5. If a target belongs to the current repo, wire the name into the app:
   - Find the central config or env module and reference `process.env.<NAME>` (or the language equivalent), with a fail-fast check at startup that never logs the value.
   - Add the name with an empty value to `.env.example`.
   - Make sure the start scripts run through `doppler run --`.
6. Finish with one line: what was stored, where it was pushed, and which files changed.
