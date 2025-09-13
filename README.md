# whisky_discord_perms
Discord → ACE → (optional) Qbox/QBCore job linking.

## What you asked for
- Only departments: `group.lspd`, `group.bcso`, `group.sahp`
- Each maps to in-game job with **rank 0** by default (editable).
- Blank scaffolding for **Discord role IDs** to fill in later.
- You can also whitelabel via extra ACE group names if you prefer.

  
##Looking for help, or custom integrations?  
[![Join Whisky Dev Discord](https://img.shields.io/badge/Discord-Support%20Server-5865F2?logo=discord&logoColor=white)](https://discord.gg/6FQtJdBXMk)


## Install
1) Ensure dependencies and this resource in your `server.cfg`:
   ```cfg
   ensure Badger_Discord_API
   ensure whisky_discord_perms

   # Optional: staff perms for admin commands
   add_ace group.admin command.permrefresh allow
   add_ace group.admin command.permdebug allow
   ```
3) Open `config.lua`, add your Discord **role IDs** under each department.
   - They must be strings, e.g. `"1387419672999362711"`
   - Leave `groups` empty unless you want ACE → dept mapping too.

## Behavior
- On player join: reads Discord roles, optionally grants department ACE, picks the highest-priority department, and (if enabled) sets the job/grade.
- On disconnect: removes any principals granted by this resource.
- Admin:
  - `/permrefresh <id|all>`
  - `/permdebug <id>`

## Notes
- Job linking tries **qbx_core** first, falls back to **qb-core** APIs, and finally emits a generic `QBCore:Server:SetJob` event for forks.
- Toggle with `Config.EnableJobLink` and `Config.OnlySetIfUnemployed`.
- Department priority is set in `Config.DepartmentPriority`.
