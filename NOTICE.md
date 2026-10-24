# NOTICE — KFusion upstream attribution

KFusion is a derivative work distributed under the GNU General Public License
v3.0 (see `LICENSE`, kept verbatim from upstream). This file records where the
code and designs come from.

## Based on FlClash

- **FlClash** by chen08209 — https://github.com/chen08209/FlClash
  Licensed under GPL-3.0.
  KFusion P0 is a fork of FlClash v0.9.1 (commit 8d4f974), reduced to the
  Android and Windows targets and rebranded. The original copyright and
  license are preserved in `LICENSE` and in the source file headers.
  The upstream repository remains available as the git remote `upstream`.

## Proxy core

- **mihomo / Clash.Meta** — https://github.com/MetaCubeX/mihomo
  (vendored as the `core/Clash.Meta` git submodule, FlClash branch of
  https://github.com/chen08209/Clash.Meta)
  Licensed under GPL-3.0. This is the only core shipped in P0/P1.

## Design input (later phases)

- **Karing** by KaringX — https://github.com/KaringX/karing
  Licensed under GPL-3.0 with an additional term that derivative works may
  not use the Karing name or imply association with it.
  No Karing code is included yet. From P1 on, KFusion will absorb Karing's
  *designs* — all-format subscription compatibility, a single routing
  template applied across subscriptions, beginner mode, and multi-device
  sync. If Karing code is ever reused, it will be under GPL-3.0 and this
  notice will be updated; the KFusion name does not use or imply Karing.

- **sing-box** — https://github.com/SagerNet/sing-box (GPL-3.0)
  Planned as the second core in P2; not included yet.

## KFusion itself

KFusion's own modifications are likewise released under GPL-3.0. There is no
affiliation with, or endorsement by, the FlClash, Karing, mihomo or sing-box
projects.
