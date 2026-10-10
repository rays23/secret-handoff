---
description: Show the secret-handoff setup: depot, installed tools and the secret names currently in the depot
allowed-tools: Bash(command -v:*), Bash(doppler secrets --only-names:*), Read
---

Report the state of secret-handoff. You never read or print secret values.

Steps:
1. Read `~/.config/secret-handoff/config` (or `$XDG_CONFIG_HOME/secret-handoff/config`) with the Read tool. It holds `DEPOT_PROJECT` and `DEPOT_CONFIG`.
   If the file is missing, tell the user to run `/secret-handoff:setup` and stop.
2. Run `command -v dset` and `command -v dpush`. Report whether both are on the PATH.
3. Run `doppler secrets --only-names --project <DEPOT_PROJECT> --config <DEPOT_CONFIG>` and list the names.
   Names that start with `DOPPLER_` are built in and can be ignored.
4. Answer in a short table: depot, tools found, secret names waiting in the depot.
   Remind the user that secrets stay in the depot after `dpush` and can be removed with
   `doppler secrets delete NAME --silent -y --project <DEPOT_PROJECT> --config <DEPOT_CONFIG>`.
