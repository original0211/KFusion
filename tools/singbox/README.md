# sing-box binary for the KFusion Windows sidecar

KFusion does not ship a sing-box binary in git. The Windows sidecar
(`lib/core/singbox/singbox_runner.dart`) starts the binary found at, in
order:

1. The path stored in the `singboxBinaryPath` preference, when set.
2. `sing-box.exe` next to the KFusion executable.
3. `singbox/sing-box.exe` inside the application support directory.

## Obtaining a binary

Download a Windows release from the official sing-box releases page
(github.com/SagerNet/sing-box) and pick the asset matching the machine:
`sing-box-<version>-windows-amd64.zip` for x64, `sing-box-<version>-windows-arm64.zip`
for ARM64. Verify the published checksum for the asset before unzipping, then
place `sing-box.exe` at one of the locations above.

Use a stable release whose `experimental.clash_api` supports the fields
KFusion renders: `external_controller`, `secret`, `default_mode`,
`store_selected` and `cache_file`.

## CI note

The GitHub Actions workflow does not download the binary yet. Adding a
download step touches `.github/workflows/build.yaml`, which the API token
cannot write (it lacks the `workflow` scope); that step is a separate
browser task. Until it lands, CI validates the renderer, the runner logic
with a fake process launcher, and the mutual-exclusion logic, but not a
real sing-box process.

## Android

Android has no native sing-box runtime in this release. On Android the
sing-box core kind is export-only; the native runtime (libbox) is P3 work.
