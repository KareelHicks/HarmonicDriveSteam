Bundled yt-dlp binaries
=======================

Place yt-dlp binaries here so exported desktop builds can download user-provided YouTube audio URLs without relying on a system install. The game extracts bundled binaries to `user://external_tools` before executing them, which keeps this working when exports embed the PCK.

Expected paths:

- `tools/yt-dlp/macos/yt-dlp`
- `tools/yt-dlp/windows/yt-dlp.exe`
- `tools/yt-dlp/linux/yt-dlp`

The game also falls back to common system locations and `yt-dlp` on PATH for development builds.

Current bundled binaries:

- macOS universal: `tools/yt-dlp/macos/yt-dlp`, downloaded from the official yt-dlp GitHub release asset for version `2026.06.09`.
- Windows x64: `tools/yt-dlp/windows/yt-dlp.exe`, downloaded from the official yt-dlp GitHub release asset for version `2026.06.09`.
- Linux x64: `tools/yt-dlp/linux/yt-dlp`, downloaded from the official yt-dlp GitHub release asset for version `2026.06.09`.

The yt-dlp project license is included at `tools/yt-dlp/LICENSE`, and its third-party license file is included at `tools/yt-dlp/THIRD_PARTY_LICENSES.txt`.
