# sing-box binary for the KFusion Windows sidecar

KFusion does not ship a sing-box binary in git. The Windows sidecar
(`lib/core/singbox/singbox_runner.dart`) starts the binary found at, in
order:

1. The path stored in the `singboxBinaryPath` preference, when set.
2. `sing-box.exe` next to the KFusion executable.
3. `singbox/sing-box.exe` inside the application support directory.

## Managed download (default)

When none of the locations above holds a binary, the app downloads one
itself (`lib/core/singbox/singbox_binary.dart`): starting sing-box, or the
download button in Settings → General, fetches the pinned official build —
sing-box 1.14.4, `sing-box-1.14.4-windows-amd64.zip` or
`sing-box-1.14.4-windows-arm64.zip` from the SagerNet/sing-box GitHub
release — into location 3. The zip's SHA-256 must match the digest pinned
in the source (taken from the release's asset digests and re-verified
against downloaded copies) or the download is discarded. Because the
binary lives in the application support directory, app updates, which
replace the install directory, no longer remove it.

The download tries, in order, the Windows system proxy (the WinINET
setting other apps such as Karing set), the app core's own proxy while a
core is running, and a direct connection; a route that fails or stalls is
dropped for the next one, and the Settings section names the route in use
while downloading and the routes tried when one fails. Only the official
release is ever fetched — the pinned SHA-256 above is what makes the
transport safe to vary. The downloaded `sing-box.exe` is unsigned and
landed under AppData, so SmartScreen or Defender may flag its first run —
that check happens on the device, not in CI.

## Placing a binary manually

Manual placement still works and wins over the managed download: any
candidate found above is used as-is. Download a Windows release from the
official sing-box releases page (github.com/SagerNet/sing-box) and pick
the asset matching the machine:
`sing-box-<version>-windows-amd64.zip` for x64, `sing-box-<version>-windows-arm64.zip`
for ARM64. Verify the published checksum for the asset before unzipping, then
place `sing-box.exe` at one of the locations above.

Use a stable release whose `experimental.clash_api` supports the fields
KFusion renders: `external_controller`, `secret`, `default_mode`,
`store_selected` and `cache_file`.

## CI note

The GitHub Actions workflow does not download the binary at build time;
the app itself downloads it at first use instead, so no workflow step is
needed. CI validates the renderer, the runner logic with a fake process
launcher, the mutual-exclusion logic and the managed download against a
fake downloader, but not a real sing-box process.

## Android

Android has no native sing-box runtime in this release. On Android the
sing-box core kind is export-only; the native runtime (libbox) is P3 work.
