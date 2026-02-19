# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- Added authoritative offline Hanzi stroke dataset in `/Users/jyy/Documents/bihua/assets/data/chars_3500.json` (9565 CJK entries, with stroke outlines + median points).
- Added data provenance and license notes in `/Users/jyy/Documents/bihua/assets/data/LICENSE.md`.
- Added web and macOS platform targets for local run/debug (`flutter run -d chrome` / `flutter run -d macos`).

### Changed
- Updated stroke rendering pipeline:
  - Uses real glyph stroke outlines for base rendering.
  - Uses current-stroke highlighting in red during playback.
  - Supports Y-axis flipping for datasets with inverted coordinates.
- Updated playback behavior:
  - Detail page auto-starts playback on open.
  - Playback speed tuned slower (`speed = 0.6`).
  - Playback session isolation per detail page instance to avoid stale state reuse.
- Updated dictionary loading strategy to stop synthetic inflation by default (`minDictionarySize = 0`).
- Updated README to reflect current runtime behavior, data source, and cache-refresh troubleshooting.

### Fixed
- Fixed mismatched Hanzi shape/stroke-order presentation for detail page rendering.
- Fixed initial/detail state inconsistencies that caused incorrect all-black or stale playback states.
- Fixed multiple widget/unit test mismatches after playback and renderer updates.

## [0.1.0] - 2026-02-19

### Added
- Initial Flutter application structure (`home + detail` pages).
- Search by Hanzi (1-20 chars), filter entry points (pinyin/stroke count/radical), and stroke-player controls.
- Unit and widget tests for sanitizer, dictionary behavior, and detail/home interactions.
