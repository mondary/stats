# Extensions (Fork Customizations)

This folder contains fork-specific additions that are not part of upstream `exelban/stats` core modules.

## Current extension
- `LLM/` : LLM usage module (Codex, Claude, Gemini, GLM)

## Notes
- The Xcode project references this extension directly from `extensions/LLM`.
- Goal: keep custom code isolated to simplify upstream sync and potential PR extraction.
