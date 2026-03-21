# Archived: Full ROM Shortcut Maker Specs

This directory contains the original specifications for a full-featured ROM Shortcut Maker that would independently scan ROMs, detect emulators, fetch metadata, and generate app bundles.

## Why Archived

After analysis, we determined this approach was overkill since Steam ROM Manager already handles all the complex logic (ROM scanning, emulator matching, metadata fetching, artwork). 

The simpler approach: parse Steam's shortcuts.vdf file (which SRM populates) and generate .app bundles from that data.

## Original Specs

- `requirements.md` - 13 detailed requirements with 29 acceptance criteria
- `design.md` - Full architecture with 29 correctness properties
- `tasks.md` - 80+ implementation tasks

## If You Need This

These specs remain valid if you ever want to build a standalone tool that doesn't depend on Steam ROM Manager.
