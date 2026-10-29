# Digs — FFXI Windower 4 Chocobo Digging Addon

A community-ready copy of the Digs addon with updated FFXI DAT message IDs, Wing Skill tracking, and per-character item history. Based on the original Digs addon by Oyukisan (see the author field in `digs.lua`).

## Install

1. Download this repository ZIP, and extract the **four `.lua` files** into `Windower4/addons/digs/`. The folder name must be `digs`.
2. If upgrading, **back up your existing** `digs.lua`, `messages.lua`, `search_settings.lua`, and any `data/settings.xml` before replacing files.
3. Log in to FFXI, then use the Windower console command `lua l digs` (or `lua r digs` if already loaded).
4. Dig on a chocobo in a supported outdoor zone to begin recording results.

Windower 4 provides the required `config`, `pack`, `packets`, `resources`, `files`, and `bit` modules. The DAT lookup uses the player's own installed FFXI DAT files.

## Commands

Enter addon commands through the Windower chat command prefix (`//`):

- `//digs stats` — accuracy, fatigue estimate, today's item count, greens and Wing Skill
- `//digs items` — today's itemized finds
- `//digs itemslife` — lifetime itemized finds
- `//digs skill` — current Wing Skill and recorded increases
- `//digs skillhistory` — recorded Wing Skill level-ups
- `//digs skill set 5` — manually calibrate Wing Skill without adding a fake level-up
- `//digs rank amateur` — set dig timing rank; see `//digs` for all ranks
- `//digs stats clear` — reset accuracy counters

## Zones and limitations

- The zone allowlist contains **59 configured outdoor zones**. Dungeon areas are intentionally excluded.
- **Zone 44 (Abdhaljs Isle-Purgonorgo)** is included but its message IDs are **pending manual verification**; do not assume digging tracking works there. The other **58 zones** have a complete nine-key message table.
- The addon also scans current FFXI DAT messages when entering a supported zone and caches verified IDs locally. DAT IDs can change after game updates.
- In-game verification has covered successful and failed digs, item counts, saved item history, Wing Skill updates, character-specific history and a zone transition in the tested zones; this is **not** a claim that all zones were individually tested in-game.
- `Fatigue today` is an estimate using the original calculation, **not** a count of failed digs.

## Privacy / clean install

**This release deliberately contains no `settings.xml`, personal item logs, Wing Skill history, character names, or generated `digs_dat_message_ids.lua` cache.** The addon generates local per-character settings as you play. The `.gitignore` excludes the `data/` directory and cache from Git. Never upload your existing `data/settings.xml` to a public repository.

## Credits

Original addon metadata: **Oyukisan**, Digs v1.2.0. This package retains the original author metadata and provides the updated Lua scripts supplied for this release. Check upstream licensing/permission before publishing a modified distribution.
