# Hostreamio Development & Synchronization Rules

## 1. Strict Local and GitHub Two-Way Sync
- **Local -> GitHub**: Whenever files are created, modified, or refactored locally, they must be committed and pushed to `origin main`.
- **GitHub -> Local**: When GitHub Actions builds release artifacts (`hostreamio.apk`, `hostreamio.exe`, `hostreamio-windows-x64.zip`), immediately ensure the local repository copies in `D:\hostreamio` are synchronized with the latest artifacts from GitHub Release `v1.0.0`.
- **Post-Update Check**: After every update cycle, ensure:
  1. `git status` is clean (no uncommitted or untracked changes).
  2. Local `hostreamio.exe`, `hostreamio.apk`, and `hostreamio-windows-x64.zip` match the latest build.
  3. GitHub Release `v1.0.0` has all 3 updated assets.

## 2. Release Versioning Policy
- **Fixed Version**: The release version must ALWAYS remain **`v1.0.0`** (`Release v1.0.0`) until the user explicitly requests a version bump.
- Do not create `v1.0.1`, `v2.0.0`, etc.
- Updates must update the assets and tag for `v1.0.0`.

## 3. Responsive UI (Mobile & Android TV)
- Any UI modifications to `android_app/lib/` must support both Mobile (touch/portrait) and Android TV (DPAD remote/landscape).
- Use `Expanded`, `Flexible`, `FittedBox`, or `Wrap` to prevent horizontal text overflows on compact screens.
- Keep all interactive cards and buttons focusable for TV remote navigation via `_TvFocusableButton`.
- Keep the Streaming Theater Catalogue Browser intact and responsive across all categories.
