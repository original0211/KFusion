# Changelog

## v0.2.16 (2026-10-27)

**Bug Fixes**

- **ui** The configuration list's current profile takes the cabin reading the dashboard set: the card grows the disc watermark at its top end — the same motif, at the same size and faintness, as the dashboard's current-profile card — and the in-use mark moves out of the generic selection badge into a dedicated metadata chip, accent text on the block step, while expiry and the other identity chips stay on their neutral ground. Selection, pressing and the card's data flow are untouched, and the add-profile page rides along unchanged on the shared card language. (84b6244)
- **ui** The universal import page sits its payloads in wells built from the cabin surface steps: the URL field and the pasted-text field recess into inset wells behind the rim border, and the parsed result rises into a block-step well inside the card, so an imported payload reads as set into the page rather than typed over it. The guide head — disc motif and a status-style title — and the single primary confirm button were already the signed-off reading and stay; controllers, parsing and every callback are untouched. (084979f)
- **ui** A geometry correction rides with the import wells: their decoration now draws the project's superellipse border — the rounded-superellipse shape the cards and the Dock already use — instead of a plain circular-arc box, so the wells' corners sit on the one corner geometry the interface allows itself. Radius, rim color, step color and padding are unchanged; only the corner curve moved. (b3e8186)
- **ui** The node exit-IP type probing added with the proxies cabin batch is removed end to end, on the strength of the device verdict: on the profiles it served — OpenVPN home-broadband nodes — the per-node probes timed out in bulk and the rows sat on the probing placeholder with the type never landing. The proxies rows lose the type mark, the probing placeholder and the first-visit note; the page-entry sweep, the delay-test piggyback probes and the per-profile node-to-IP disk map are gone, and the settings switch and the long-press re-probe go with them. The page keeps its cabin form — row-card radius, the selected card's cyan rim and dot, the group metadata chips — and the dashboard's current-exit panel, which predates the module and reads only the connection in use, is not touched. (5dc04e1)
- **core** The sing-box renderer likewise gives back the probe channel it had injected for the removed module: renders no longer add the probe selector over all leaf outbounds, the loopback mixed inbound on port 17909, or the binding rule that rode at the head of the route, so the rendered config is again exactly the pre-probe one, its route rules back to seven — and a guard test now sweeps every rendered tag and the encoded text for any probe remnant. The probe client that switched the injected group is deleted with it. (5dc04e1)
- **core** The sing-box death card no longer loses its own verdict to a race: a crash's exit record is published by the system only after the process has died, and the card used to read it exactly once — too early, it found only the previous attempt's record, failed the attempt association and fell back to the bare generic line, so the signal headline and the attempt line never reached the card. The plugin now waits a bounded grace — thirteen probes over about three seconds — for a record that belongs to this attempt, and only silence still settles for the generic line; a failure card can arrive those three seconds later, carrying strictly more. The same commit stops the service log from printing the crash-report tail header over an empty tail: header and lines now appear only when there is a tail to show. (d1e1d9c)

## v0.2.15 (2026-10-26)

**Bug Fixes**

- **ui** The proxies page now marks every node with the type of the exit IP it really uses: a sweeper resolves each node's exit address — on mihomo through the existing routed probe, on sing-box through a probe channel the renderer injects additively (a dedicated selector over all leaf outbounds, a loopback mixed inbound and one binding rule; strip the three additions and the render is byte-identical to before) — classifies the address through the shared six-source quality lookup, and persists the node-to-IP map per profile for twenty-four hours, invalidated the moment the profile or the running core changes. A row whose type is known carries a small neutral chip — residential, data center or mobile — a group row reads the type of the leaf it actually exits through, and while a type is unknown the row shows nothing at all: a type is never guessed from a node's name. A settings switch turns the whole module off, and a long press on a mark re-probes that one node. (b292ab5)
- **ui** The proxies page takes the cabin reading: node cards settle on the 20-unit row-card radius, the selected card gains the signal-cyan rim overlay and the 7px cyan dot beside its name, and group types move out of plain text into neutral metadata chips, while the exit-IP quality sheet behind a mark stays the existing one. (b292ab5)
- **ui** Two follow-up corrections ride with the batch: the first-visit note about IP types now floats over the proxies list instead of flowing above it, so its asynchronous arrival no longer shifts the list geometry under the reader; and the sweeper no longer unwatches the routed probe when a widget tears down — its entries ride the probe until a core or profile reset — which keeps a teardown from synchronously detaching the probe's transport as its last consumer leaves. (3b82cf0)
- **core** The staged sing-box start ladder now probes two levels below the bare instance: L-1 starts the bare form with the cache file redirected to a fresh probe file (cache-probe-<seq>.db) in the same working directory — the daemon passes a platform log writer unconditionally, so the cache file is opened at every level and only its path can be moved — and L-2 starts a literal near-empty config, a log level and one direct outbound, derived from nothing the renderer or the trimming code produced. Stale probe files are swept before the ladder runs, and the verdicts name the new levels: a death at L-1 clears the cache file's contents (a virgin file crashed on first touch, so suspicion moves to the hosting layer), a death at L-2 after L-1 passed convicts the cache (the torn default cache file is the one material thing the level restores), and a death at L0 after both passed narrows the next round to the bare form's own construction. (c756f83)
- **core** The sing-box death card now leads with the tombstone's own evidence instead of the log tail: the signal line comes first — signal, code and fault address — followed by a plain-language note where the signal carries one (SIGBUS points most often at a damaged memory-mapped file such as the cache file, SIGSEGV at a native invalid memory access, SIGABRT at a deliberate abort such as a Go runtime fatal) and the first backtrace frame, joined to the verdict ahead of the attempt line. The register rows that used to crowd the card stay in the full service log, where trace excerpts are now prefixed line by line and the card's tail filters those lines out. (c756f83)
- **core** A sing-box config check that goes unanswered is no longer reported as an unconvertible profile: the plugin retries a silent check once under a fresh request id — re-sending the intent itself restarts a dead service process, and a late answer to the first attempt can never be taken for the retry's — and only two silences in a row settle the matter, as a new failure that says the service did not respond and that this does not mean the config is invalid. A real validation answer, empty or an error string, is still taken the first time and still names the profile; the Dart-side check budget rises from 35 to 75 seconds to cover both attempts. (c756f83)

## v0.2.14 (2026-10-26)

**Bug Fixes**

- **core** A sing-box process death is now charged to the start attempt that owned it: every attempt carries a sequence number, written with its ledger entry and mirrored where the main process can read it, and an exit record is only quoted when it falls inside the attempt's own five-second association window — a verdict that belongs to this tap reads 'attempt #<n> died: LOW_MEMORY(3) at …', the matching line in the service log gains the same attempt suffix, and an earlier death, an idle-time reclaim or a record that has not landed yet is never presented as this tap's failure again (886ceeb)
- **core** The staged start ladder is now armed for low-memory kills as well as native crashes: an attempt death the system records as LOW_MEMORY inside its window sends the next start down the same trimmed levels, and the verdict names the cause as well as the level — 'staged start: low-memory killed at L<k> (<name>)' — with the full-config level stating plainly that the whole start's peak is in question; deaths that are neither a native crash nor a low-memory kill still leave the ladder unarmed (886ceeb)
- **core** Every real start now leaves a memory snapshot in the service log immediately before it runs — 'start: memory snapshot: pss <x> MB, avail <y> MB, lowMemory=<bool>' — and each staged level's begin line carries that level's own PSS, so the level whose start first inflates memory is visible in the numbers next to the moment it happened, and the system's free-memory and low-memory readings at the time stand as the pressure evidence beside any kill (886ceeb)

## v0.2.13 (2026-10-26)

**Bug Fixes**

- **core** A sing-box working cache left behind by a native crash no longer poisons every later start: before any start that follows a recorded native-crash exit, the cache file in the core's working directory is renamed aside exactly once, keeping one rolled-aside copy, so a cache torn by a process killed mid-write cannot crash the next start the same way; starts after any other kind of exit, and every healthy start, never touch the cache (7f63e2c)
- **core** A native crash during a full sing-box start is now bisected instead of repeated blindly: the crashed attempt is remembered in a ledger written synchronously, so it survives the dying process, and the next start walks trimmed-down configurations built from the same rendered config — bare direct, then outbounds and DNS, then rule sets, then inbounds, then the untouched full config — each level pre-checked before it runs, narrowing the crash to the stage whose component set first brings it back (7f63e2c)
- **core** When a staged level crashes, the tap after it starts nothing: it fails in writing with the crashed level named — 'staged start: crashed at L<k> (<name>)' — in the switch card and the service log, and the attempt after that returns to the normal full start; a level that merely returns an error stays an ordinary failure, never a crash verdict, and a trimmed config that fails its check quietly falls back to the full start (7f63e2c)
- **core** The process-death verdict now carries the tombstone's signal line when the system provides one: the first signal line — signal number and name, code and fault address — is extracted and appended to the exit summary in the service log and the switch card's failure detail, so a crash reports whether it was a bus error at a mapped page, a segmentation fault or an abort; when no trace is available, the summary stands on its own as before (7f63e2c)

## v0.2.12 (2026-10-26)

**Bug Fixes**

- **core** A failed sing-box start now names the recorded cause of the process death instead of only reporting that the process exited: on every service start the newest system process exit record for the sing-box process is read, and its reason — a native crash, low memory, a signal and the rest of the platform set — is written to the service log and folded into the switch card's failure detail, so the next failure reads its exit reason on the card itself (b45c1eb)
- **core** The Go crash report the core's error output is redirected to is now read back instead of sitting unread in the working directory: its last forty lines join the service log once per change alongside the exit record, so a fatal crash inside the core leaves its stack where the failure detail and the next diagnosis can reach it (b45c1eb)
- **core** Errors escaping the sing-box start and profile check paths are no longer silent: both catches are widened from exceptions to all throwables, so an escaping error now fails the attempt in writing — a failed state and a log line — instead of the start thread vanishing without a trace and leaving only a timeout or a dead-process verdict behind, and the service's reload entry gains begin, returned and failed markers with the same treatment (b45c1eb)
- **ui** Both themes gain pinned surface ladders ahead of the cabin restyle: the dark steps settle at the deep values — page #090B0C, card #161818, block #202223 — and the light theme trades its one shared surface role for a warm paper ladder, a paper page under a pure white card with a warm white block inside, so pages, cards and inset blocks separate into three readable levels in both themes (778a6c5)
- **ui** The cabin token layer is declared: card corners settle at 22, row cards at 20 and a new floating tier at 26 covers the dock, dialogs and menus; panel borders read as a rim highlight — white at 7% in dark, ink at 6% in light — and soft panel and dock shadow pairs are fixed for both themes, with common cards taking the rim and the 22 corner now and the shadows following screen by screen (778a6c5)
- **ui** Navigation takes its cabin forms: the floating dock stands 70 high with 26 corners on the chrome step, a rim edge and the dock shadow, its lens tinted in ink instead of the signal colour with a 5 px signal dot marking the selected entry; the edge navigation bar keeps its body on the chrome step with an ink selection reading, and the desktop sidebar selects in ink with its signal marker kept and its inner dividers in the rim tone (778a6c5)
- **ui** The shared type scale is settled: page titles at 27, list titles at 15 medium, subtitles at 12, captions at 11 and card headers at 16 semibold, declared at one point and inherited by every screen instead of each surface keeping its own sizes (778a6c5)

## v0.2.11 (2026-10-26)

**Bug Fixes**

- **core** A sing-box start whose service process dies mid-start is now called as what it is within one polling cycle instead of pending for the whole 40 seconds: the start gate checks the starting snapshot's process id, and a dead process fails the attempt at once with a detail that says the process exited during start, while an unknown process id still reads as pending (4a73e26)
- **core** When a sing-box start times out, the attempt is now stopped and invalidated instead of being left to finish unwatched: the plugin sends an explicit stop, the service voids the attempt and frees the start gate, and a start that completes late tears itself down without writing a stale running or failed state over the next attempt, so one hung start can no longer poison every retry until the process is killed (4a73e26)
- **core** The sing-box service's own log is now persisted and reaches the failure message: the box log is forwarded and written with stage markers to a rolling 256 KB service log on disk, and a failed start appends its last six lines to the detail under the plain-language sentence, so a start failure finally shows where the core stopped instead of only reporting a timeout (4a73e26)
- **ui** The rest of the profiles line joins the settled card and form standards: an empty profile list shows the brand disc mark, the expiry and group count chips read neutral with red kept only for an expiry that has already passed, and the universal import page gathers its import methods and its name and template fields into section cards under a disc header, with errors in the standard banner and the parse result in a titled section (85bfcf1)
- **ui** The logs page payload now reads in the monospace type scale end to end — message, tag, destination, error, rule, arrow and source — and the routed proxy name drops the signal colour for a neutral emphasis, matching how record rows mark chain names; the requests, connections, DNS and resources screens were audited onto the same record row standards (6ea092f)
- **ui** The theme page's font and text-scale cards take the card corner tier and its sidebar blur row sits in a section card, and the hotkey page reads an unbound row in the variant tone instead of the outline tone, warns on a recording conflict in the warning tone, keeps its intro glyph neutral, and sets key caps in tabular figures (7b2b922)
- **ui** Value-level marks in the rule and filter forms drop the tertiary colour, which sits outside the settled semantic palette: neutral rule outcomes such as PASS, GLOBAL and MATCH, the filter regex caption, the rule preset subtitle and the custom profile status now read in the neutral variant or surface tone, while DIRECT keeps success, the REJECT family keeps warning and an invalid value keeps error (8bf9233)
- **ui** Member type chips in the custom group editor sit on the neutral raised step with variant text, matching the settled tonal chip, instead of the secondary and tertiary container colours; only an exclude member keeps the error container reading (8bf9233)

## v0.2.10 (2026-10-26)

**Bug Fixes**

- **core** Core switching on Android now trusts only the current attempt's native answers: every sing-box start stamps the status snapshot with its own epoch, so a previous failure can no longer answer every later retry within milliseconds and a dead process's leftover RUNNING can no longer pass as success; the service channel waits for each start and stop request's real outcome in the native state machine before it replies; a start counts only once the core's own API probes back; starts are single-flight, the service no longer resurrects its previous configuration after being killed, and the native and Dart start budgets are aligned at 40 and 45 seconds so the native verdict is always the one acted on; and on Windows a switch first reclaims this app's own orphaned sing-box processes and waits for the mixed port to free before the new core spawns (559b58d)
- **core** The sing-box configuration the app renders no longer contains the legacy block outbound that sing-box removed in 1.13 and the bundled 1.14.4 rejects outright: REJECT group members are dropped with a note, a MATCH out to REJECT becomes a trailing reject rule instead, and the rendered configuration is strictly validated with Libbox.checkConfig before any core is stopped, so a profile the bundled sing-box cannot accept is refused up front, in the checker's own words, instead of burning a switch on it (559b58d)
- **ui** The core switch card drops the stock segmented button, which sat inside it like a foreign widget, for two rows in the card's own language — a block-tier fill, the disc motif as the row mark in the signal colour only on the selected core, the core's name and running state, and the shared selection check — and a failed switch now shows the native detail (a libbox rejection, a service failure) in small type under its plain-language sentence instead of discarding it (2cf728f)
- **ui** The add-profile page gathers its five entries — QR code, file, link, custom and universal import — from bare rows on the page fill into one grouped card that shares the dashboard and settings surface step, corner tier and hairlines, with the universal import row taking the page's single accent spot, a sparkle glyph in the primary colour, instead of a second copy of the file glyph (2c4c053)

## v0.2.9 (2026-10-25)

**Features**

- **app** The sing-box card in Settings is now a core switch with a mihomo / sing-box segmented control: one tap stops the running core, starts the target and re-applies the current profile for it, naming each stage as it goes, and the current profile is rendered for the target core up front, so one that cannot be converted is refused before anything stops (7af328f)

**Bug Fixes**

- **core** Starting sing-box on Android while mihomo was running no longer hangs and then fails with a raw error claiming mihomo could not stop: the switch stops mihomo through the real run-state chain, the stopped state is written back where the rest of the app reads it, and a stop that does not take effect no longer leaves every other core action reporting the core as not connected (779bf77)
- **app** When a core switch fails part-way through, the core that ran before is restored, and the card explains in one plain sentence which step failed and what to do next, instead of surfacing the raw exception (7af328f)
- **ui** The proxies page joins the settled interface standards: node cards sit on the neutral surface at the card corner step, the signal colour stays only on functional marks such as the current node and the selected group, and delays read as small labels in semantic colours (523424b)

## v0.2.8 (2026-10-25)

**Features**

- **dashboard** Beginner mode is removed: every install now gets the full dashboard, and the import card on the home screen is simply the empty state shown to everyone while no profile exists yet (0f4ce2b)

**Bug Fixes**

- **app** The sing-box section in Settings now keeps everything inside its card — status, the binary location, download progress with the route in use, and any error — instead of spilling rows below it (120bd11)
- **app** Downloading the sing-box binary now tries the Windows system proxy first, then a running core, then a direct connection, with a timeout on each hop and partial downloads cleaned up, instead of going direct and hanging until it times out (120bd11)
- **core** When the core is not connected, profile actions no longer claim it returned an empty profile; they say the core is not connected and ask for it to be started first (d2c473f)
- **ui** The shared interface kit is settled ahead of the screen-by-screen restyle: title weights step down a grade, body text gets a little more line height, large numbers use tabular figures, and cards, blocks and chips follow declared corner steps (8b28a47)
- **ui** Empty states gain a brand variant that carries the disc mark, and dialogs and bottom sheets now rest on one declared base (6df7214)

## v0.2.7 (2026-10-25)

**Features**

- **app** The sing-box core now takes care of itself on Windows: if the binary is missing, Settings offers a one-tap download of the pinned release, verified by checksum, into the app data folder, and starting a sing-box profile fetches it automatically — upgrades no longer lose it (f69e8b0)

**Bug Fixes**

- **config** Profile downloads route through the running sing-box core too, which ends the add-profile timeouts that hit whenever sing-box was in charge and no other core was running (f69e8b0)
- **dashboard** The dashboard editor lists the addable cards at the top instead of below every card already shown, and says so when every card has been added (555907b)
- **desktop** Desktop dashboard cards refill their row when a card is removed, instead of leaving an empty gap behind (5e80e41)
- **app** The YouTube service check probes a lightweight endpoint first and only then judges the region, so a slow premium page no longer shows up as a timeout; a failed check also retries once instead of staying frozen (a76f554)
- **app** When the core is stopped, the status and service cards label their results as direct-route readings instead of presenting them as the selected node's (ca55247)
- **app** The Android notification and quick-settings tile icons now use the KFusion disc rather than the leftover upstream glyph (a7226e1)

## v0.2.6 (2026-10-25)

**Features**

- **app** The phone home has a new hierarchy: the current node, speed and profile cards lead, and the status card carries the logo's disc-and-bite motif (0653e55)
- **dashboard** Beginner mode narrows the home to the core cards, and with no profile yet a universal-import guide card leads the first setup instead of an empty dashboard (0653e55)
- **desktop** The desktop dashboard now shares the phone's saved card list: cards can be removed, added back and reordered on desktop too, instead of a fixed layout (7feac84)

## v0.2.5 (2026-10-25)

**Features**

- **app** New PC icon set in the outlined-disc scheme: the Windows app, installer and shortcut icons drop the white tile for the T disc on transparency with a light outline, and the tray icons are discs too — grey when stopped, black when running, a gold ring while TUN is on and orange in safe mode (c18fdea)

**Bug Fixes**

- **app** The bite cut out of the disc is filled white instead of showing through, so it stays readable on dark wallpapers across the app and tray icons (11a8fc3)

## v0.2.4 (2026-10-25)

**Features**

- **app** A new look that matches the T disc logo: a signal-cyan accent over near-neutral black, white and grey surfaces, with light and dark following the system by default (34b31c0)
- **config** Settings gains a running-core switch for the current profile, so the core a profile runs on can be changed without opening the profile editor (34b31c0)

**Bug Fixes**

- **config** Universal import page spacing: the download, file and parse-text buttons no longer crowd the fields around them, and the profile name field no longer overlaps the parse-text button (2b47d08)
- **app** The About page links point at the right places now: the core link goes to the real upstream, MetaCubeX/Clash.Meta, and the stale credits for the old icon designers are gone (2b47d08)
- **dashboard** The dashboard edit button is shown in beginner mode too, so cards can be added, removed and reordered without turning beginner mode off first (f2a33f3)

## v0.2.3 (2026-10-25)

**Features**

- **app** New app icon: a plain black disc with a crescent bite on white, replacing the inherited FlClash icon on Android (adaptive and legacy icons), Android TV and Windows (5615dc1)

**Bug Fixes**

- **config** Universal import has real action buttons now: download and parse, choose file and parse text sit under their fields instead of hiding in the section header rows, and a disabled confirm button shows where the import will be confirmed before anything is parsed (9f108b0)
- **windows** The Windows install no longer carries FlClash names: the core and helper binaries are KFusionCore.exe and KFusionHelperService.exe, helper service name included (ac61373)
- **desktop** The desktop entry written for protocol registration is named KFusion, the last visible piece of the rename (b1a8a7c)

## v0.2.2 (2026-10-24)

**Bug Fixes**

- **core** Fix sing-box profile activation failing against the bundled sing-box 1.14 runtime: the renderer now emits the 1.14 configuration format (typed DNS servers with a fakeip server and a DNS hijack rule action, rule-set based GEOIP and GEOSITE rules, the TUN address list, WireGuard endpoints and the experimental cache file) instead of the removed pre-1.12 formats (283e857)
- **config** Map the Clash built-in policies when rendering sing-box groups and rules: DIRECT and REJECT group members resolve to the direct and block outbounds, and REJECT rule targets become reject rule actions (283e857)

## v0.2.1 (2026-10-24)

**Bug Fixes**

- **android** Fix the crash on launch: the app manifest now names the application and component classes the app actually ships, instead of classes resolved from the renamed application id namespace, which did not exist (825dcae)
- **android** Fix the platform channel prefix mismatch left over from the rename, so the Dart side reaches the app, battery, service and tile channels the native side registers (825dcae)

## v0.2.0 (2026-10-24)

**Features**

- **android** Android sing-box runtime: libbox built from the pinned sing-box source in Gradle and hosted by SingBoxVpnService, with two-way exclusion against the mihomo core (bbd1c41)
- **android** The Android sing-box service runs on the libbox command server, the entry point of sing-box 1.14 (4e437f2)
- **android** The libbox and mihomo gomobile runtimes coexist in one package: a single shared Seq copy at runtime, with the libbox bindings compiled against a compile-only Seq jar (238acce)

## v0.1.0 (2026-10-24)

**Features**

- **app** KFusion baseline on the FlClash base: Android and Windows only, rebranded as an independent app (2c9ee29)
- **config** Config hub: universal import for Clash, sing-box, share-link and subscription formats, routing templates and beginner mode (e506259)
- **core** Second core: sing-box rendering and a Windows sidecar runtime, mutually exclusive with the mihomo core (682de79)

**Bug Fixes**

- **tool** Changelog tooling derives releases built on the frozen boundary commit, so tagged releases verify (347d38f)

## v0.9.1 (2026-10-17)

**Breaking Changes**

- **network** Desktop TUN keys follow the profile unless picked; changed values carry over (cb08088)

**Features**

- **l10n** French, Spanish and Korean translations (f43755c)
- **android** No more Firebase analytics or crash reporting (bc72bba)
- **network** Per-key desktop TUN settings; system proxy and tray fixes (cb08088)
- **theme** Redesigned theme colors and color styles (5eafd7a)
- **dashboard** A redesigned dashboard around the current exit (9bd258f)
- **profiles** Profile-detail resources and include-all in custom groups (0bac500)
- **proxies** Proxy groups as cards, group tabs as chips (2ea52fd)
- **views** Sortable tables for connections, requests and DNS (da6fb0a)
- **ui** Optional two-tier Liquid Glass and slide-to-pick menus (7c9627f)
- **ui** iOS-style surfaces, alerts and sheets; clearer TV focus (9bd2286)

**Bug Fixes**

- **ui** Fix pasting and Chinese input in text fields (5607f70)
- **core** Large profiles no longer crash; downloads trust core CAs (5984c16)

**Performance**

- **android** Smoother Android UI while the proxy is busy (2201c19)

## v0.9.0 (2026-10-14)

**Breaking Changes**

- **views** DNS and NTP override toggles are removed; picked keys apply to every profile (491fae1)
- **database** Custom overwrites are removed; rebuild them as custom profiles (1677024)

**Features**

- **views** Per-key DNS, NTP, sniffer and TUN settings (491fae1)
- **profiles** Custom profiles (3abda78)
- **ui** Stacked sheets, context menus and a sort mode (8c43053)
- **providers** DNS, Hosts and ports apply without a restart (532ebf0)
- **android** Launcher shortcuts and one-step on-demand access (d3fa225)
- **core** Share link import and mrs rule sets (2fa2f7f)

**Bug Fixes**

- **database** Unreadable settings no longer block startup or restores (1677024)
- **desktop** Windows and Linux desktop fixes (94a25f4)
- **core,helper** The elevated Core only answers its owner (d780cb8)

## v0.8.99 (2026-10-03)

**Features**

- **editor** Editor word wrap and snippets (e131675)
- **dashboard** More dashboard cards (e62afb7)
- **views** Hide timed-out nodes and search every list (8378c70)
- **ui** Sidebar, floating dock and drag to go back (841d603)
- **ui** New app glyphs, empty states and theme page (ee6a497)
- **overwrite** Invalid override warnings and rule presets (46fb7fe)
- **config** DNS query log and per-key DNS/NTP overrides (a390a42)
- **core** Proxied service checks and outbound IP risk (8068e68)
- **platform** Tray hotkeys, node delays and a delay test (1e97716)

**Bug Fixes**

- **core** A changed resource link is now used by the next sync and by auto update (ff23f30)
- **core** DNS lookups no longer fail on networks that report no DNS servers (e55f6d1)
- **proxies** Smaller icons in icon-only group headers (786a6ab)
- **core,android** Push notifications reconnect in Doze (1e9955d)
- **backup,database** Restores never apply halfway (bee8f24)

## v0.8.98 (2026-09-14)

**Bug Fixes**

- **resources** Refresh the geo file size and time after an update finishes (c5bf5bd)
- **core** Keep the core running while Windows sleeps with the app suspended (60f371a)

## v0.8.97 (2026-09-10)

**Features**

- **ui** Rework the app UI and refresh the localization (26cfbaf)
- **app** Rework the app layer and window handling, and add proxy authentication (aaf934c)
- **desktop** Rework the desktop runners, packaging, and native build (c0fcbc0)
- **android** Rework the Android VPN service and lifecycle handling (ae29f38)
- **plugins** Rework the desktop plugins and add the Helper service and Rust bridge (adf715f)
- **core** Rework the core IPC and process lifecycle (c6eaa0a)

<!-- changelog:frozen -->
<!-- Entries below predate the structured pipeline. Their wording is kept as written; only the heading and list style were normalized. -->

## v0.8.96 (2026-08-17)

- Optimize commented policy
- Fix whole group delay test failing on Windows
- Optimize package icon loading and connections polling

## v0.8.95 (2026-08-14)

- Optimize core service
- Optimize Android TV launcher icon
- Optimize back navigation
- Optimize more details
- Fix some issues
- Optimize app layout
- Optimize focus control
- Adjust android process

## v0.8.94 (2026-07-11)

- Fix macos performance issue
- Support custom global-ua
- Update core
- Optimize some details
- Fix linux silent launching not working

## v0.8.93 (2026-05-29)

- Support custom overwrite
- Support run on demand
- Optimize windows ipc
- Optimize windows arm64
- Optimize build
- Optimize some details
- Update core

## v0.8.92 (2026-02-02)

- Add sqlite store
- Optimize android quick action
- Optimize backup and restore
- Optimize more details

## v0.8.91 (2025-12-12)

- Fix windows some issues
- Optimize overwrite handle
- Optimize access control page
- Optimize some details

## v0.8.90 (2025-10-08)

- Fix android tile service
- Support append system DNS
- Fix some issues
- Update changelog

## v0.8.89 (2025-09-27)

- Fix some issues
- Optimize Windows service mode
- Update core
- Update changelog

## v0.8.88 (2025-09-23)

- Add android separates the core process
- Support core status check and force restart
- Optimize proxies page and access page
- Update flutter and pub dependencies
- Update go version
- Optimize more details
- Update changelog

## v0.8.87 (2025-07-29)

- Optimize desktop view
- Optimize logs, requests, connection pages
- Optimize windows tray auto hide
- Optimize some details
- Update core
- Update changelog

## v0.8.86 (2025-06-15)

- Fix windows tun issues
- Optimize android get system dns
- Optimize more details
- Update changelog

## v0.8.85 (2025-06-07)

- Support override script
- Support proxies search
- Support svg display
- Optimize config persistence
- Add some scenes auto close connections
- Update core
- Optimize more details

## v0.8.84 (2025-05-01)

- Fix windows service verify issues
- Update changelog

## v0.8.83 (2025-05-01)

- Add windows server mode start process verify
- Add linux deb dependencies
- Add backup recovery strategy select
- Support custom text scaling
- Optimize the display of different text scale
- Optimize windows setup experience
- Optimize startTun performance
- Optimize android tv experience
- Optimize default option
- Optimize computed text size
- Optimize hyperOS freeform window
- Add developer mode
- Update core
- Optimize more details
- Add issues template
- Update changelog

## v0.8.82 (2025-04-18)

- Optimize android vpn performance
- Add custom primary color and color scheme
- Add linux nad windows arm release
- Optimize requests and logs page
- Fix map input page delete issues
- Update changelog

## v0.8.81 (2025-04-08)

- Add rule override
- Update core
- Optimize more details
- Update changelog

## v0.8.80 (2025-03-10)

- Optimize dashboard performance
- Fix some issues
- Fix unselected proxy group delay issues
- Fix asn url issues
- Update changelog

## v0.8.79 (2025-03-07)

- Fix tab delay view issues
- Fix tray action issues
- Fix get profile redirect client ua issues
- Fix proxy card delay view issues
- Add Russian, Japanese adaptation
- Fix some issues
- Update changelog

## v0.8.78 (2025-03-05)

- Fix list form input view issues
- Fix traffic view issues
- Update changelog

## v0.8.77 (2025-03-05)

- Optimize performance
- Update core
- Optimize core stability
- Fix linux tun authority check error
- Fix some issues
- Fix scroll physics error
- Update changelog

## v0.8.75 (2025-02-09)

- Add windows storage corruption detection
- Fix core crash caused by windows resource manager restart
- Optimize logs, requests, access to pages
- Fix macos bypass domain issues
- Update changelog

## v0.8.74 (2025-02-03)

- Fix some issues
- Update changelog

## v0.8.73 (2025-02-02)

- Update popup menu
- Add file editor
- Fix android service issues
- Optimize desktop background performance
- Optimize android main process performance
- Optimize delay test
- Optimize vpn protect
- Update changelog

## v0.8.72 (2025-01-10)

- Update core
- Fix some issues
- Update changelog

## v0.8.71 (2025-01-09)

- Remake dashboard
- Optimize theme
- Optimize more details
- Update flutter version
- Update changelog

## v0.8.70 (2024-12-09)

- Support better window position memory
- Add windows arm64 and linux arm64 build script
- Optimize some details

## v0.8.69 (2024-12-06)

- Remake desktop
- Optimize change proxy
- Optimize network check
- Fix fallback issues
- Optimize lots of details
- Update change.yaml
- Fix android tile issues
- Fix windows tray issues
- Support setting bypassDomain
- Update flutter version
- Fix android service issues
- Fix macos dock exit button issues
- Add route address setting
- Optimize provider view
- Update changelog
- Update CHANGELOG.md

## v0.8.67 (2024-11-09)

- Add android shortcuts
- Fix init params issues
- Fix dynamic color issues
- Optimize navigator animate
- Optimize window init
- Optimize fab
- Optimize save

## v0.8.66 (2024-10-26)

- Fix the collapse issues
- Add fontFamily options

## v0.8.65 (2024-10-26)

- Update core version
- Update flutter version
- Optimize ip check
- Optimize url-test

## v0.8.64 (2024-10-12)

- Update release message
- Init auto gen changelog
- Fix windows tray issues
- Fix urltest issues
- Add auto changelog
- Fix windows admin auto launch issues
- Add android vpn options
- Support proxies icon configuration
- Optimize android immersion display
- Fix some issues
- Optimize ip detection
- Support android vpn ipv6 inbound switch
- Support log export
- Optimize more details
- Fix android system dns issues
- Optimize dns default option
- Fix some issues
- Update readme

## v0.8.60 (2024-09-17)

- Fix build error2
- Fix build error
- Support desktop hotkey
- Support android ipv6 inbound
- Support android system dns
- fix some bugs

## v0.8.59 (2024-09-09)

- Fix delete profile error

## v0.8.58 (2024-09-08)

- Fix submit error 2
- Fix submit error
- Optimize DNS strategy
- Fix the problem that the tray is not displayed in some cases
- Optimize tray
- Update core
- Fix some error

## v0.8.57 (2024-09-02)

- Fix tun update issues
- Add DNS override
- Fixed some bugs
- Optimize more detail
- Add Hosts override

## v0.8.56 (2024-08-26)

- fix android tip error
- fix windows auto launch error

## v0.8.55 (2024-08-25)

- Fix windows tray issues
- Optimize windows logic
- Optimize app logic
- Support windows administrator auto launch
- Support android close vpn

## v0.8.53 (2024-08-15)

- Change flutter version
- Support profiles sort
- Support windows country flags display
- Optimize proxies page and profiles page columns

## v0.8.52 (2024-08-11)

- Update flutter version
- Update version
- Update timeout time
- Update access control page
- Fix bug

## v0.8.51 (2024-08-05)

- Optimize provider page
- Optimize delay test
- Support local backup and recovery
- Fix android tile service issues

## v0.8.49 (2024-07-31)

- Fix linux core build error
- Add proxy-only traffic statistics
- Update core
- Optimize more details
- Merge pull request #140 from txyyh/main
- 添加自建 F-Droid 仓库相关 workflow
- Rename readme fingerprint
- Rename workflow deploy repo name
- Add download guide to README
- Add push release files to fdroid-repo

## v0.8.48 (2024-07-25)

- Optimize proxies page
- Fix ua issues
- Optimize more details

## v0.8.47 (2024-07-22)

- Fix windows build error

## v0.8.46 (2024-07-22)

- Update app icon
- Fix desktop backup error
- Optimize request ua
- Change android icon
- Optimize dashboard

## v0.8.44 (2024-07-18)

- Remove request validate certificate
- Sync core

## v0.8.43 (2024-07-18)

- Fix windows error

## v0.8.42 (2024-07-18)

- Fix setup.dart error
- Fix android system proxy not effective
- Add macos arm64

## v0.8.41 (2024-07-17)

- Optimize proxies page
- Support mouse drag scroll
- Adjust desktop ui
- Revert "Fix android vpn issues"
- This reverts commit 891977408e6938e2acd74e9b9adb959c48c79988.

## v0.8.40 (2024-07-15)

- Fix android vpn issues
- Fix android vpn issues
- Rollback partial modification

## v0.8.39 (2024-07-15)

- Fix the problem that ui can't be synchronized when android vpn is occupied by an external
- Override default socksPort,port

## v0.8.38 (2024-07-14)

- Fix fab issues

## v0.8.37 (2024-07-14)

- Update version
- Fix the problem that vpn cannot be started in some cases
- Fix the problem that geodata url does not take effect

## v0.8.36 (2024-07-13)

- Update ua
- Fix change outbound mode without check ip issues
- Separate android ui and vpn
- Fix url validate issues 2
- Add android hidden from the recent task
- Add geoip file
- Support modify geoData URL

## v0.8.35 (2024-07-07)

- Fix url validate issues
- Fix check ip performance problem
- Optimize resources page

## v0.8.34 (2024-07-04)

- Add ua selector
- Support modify test url
- Optimize android proxy
- Fix the error that async proxy provider could not selected the proxy

## v0.8.33 (2024-07-01)

- Fix android proxy error
- Fix submit error
- Add windows tun
- Optimize android proxy
- Optimize change profile
- Update application ua
- Optimize delay test

## v0.8.32 (2024-06-28)

- Fix android repeated request notification issues

## v0.8.31 (2024-06-28)

- Fix memory overflow issues

## v0.8.30 (2024-06-27)

- Optimize proxies expansion panel 2
- Fix android scan qrcode error

## v0.8.29 (2024-06-27)

- Optimize proxies expansion panel
- Fix text error

## v0.8.28 (2024-06-26)

- Optimize proxy
- Optimize delayed sorting performance
- Add expansion panel proxies page
- Support to adjust the proxy card size
- Support to adjust proxies columns number
- Fix autoRun show issues
- Fix Android 10 issues
- Optimize ip show

## v0.8.26 (2024-06-22)

- Add intranet IP display
- Add connections page
- Add search in connections, requests
- Add keyword search in connections, requests, logs
- Add basic viewing editing capabilities
- Optimize update profile

## v0.8.25 (2024-06-19)

- Update version
- Fix the problem of excessive memory usage in traffic usage.
- Add lightBlue theme color
- Fix start unable to update profile issues
- Fix flashback caused by process

## v0.8.23 (2024-06-16)

- Add build version
- Optimize quick start
- Update system default option

## v0.8.22 (2024-06-16)

- Update build.yml
- Fix android vpn close issues
- Add requests page
- Fix checkUpdate dark mode style error
- Fix quickStart error open app
- Add memory proxies tab index
- Support hidden group
- Optimize logs
- Fix externalController hot load error

## v0.8.21 (2024-06-13)

- Add tcp concurrent switch
- Add system proxy switch
- Add geodata loader switch
- Add external controller switch
- Add auto gc on trim memory
- Fix android notification error

## v0.8.20 (2024-06-12)

- Fix ipv6 error
- Fix android udp direct error
- Add ipv6 switch
- Add access all selected button
- Remove android low version splash

## v0.8.19 (2024-06-10)

- Update version
- Add allowBypass
- Fix Android only pick .text file issues

## v0.8.18 (2024-06-09)

- Fix search issues

## v0.8.17 (2024-06-09)

- Fix LoadBalance, Relay load error
- Fix build.yml4
- Fix build.yml3
- Fix build.yml2
- Fix build.yml
- Add search function at access control
- Fix the issues with the profile add button to cover the edit button
- Adapt LoadBalance and Relay
- Add arm
- Fix android notification icon error

## v0.8.16 (2024-06-08)

- Add one-click update all profiles
- Add expire show

## v0.8.15 (2024-06-06)

- Temp remove tun mode
- Remove macos in workflow
- Change go version

## v0.8.14 (2024-06-06)

- Update Version
- Fix tun unable to open

## v0.8.13 (2024-06-06)

- Optimize delay test2
- Optimize delay test
- Add check ip
- add check ip request

## v0.8.12 (2024-06-06)

- Fix the problem that the download of remote resources failed after GeodataMode was turned on, which caused the
  application to flash back.
- Fix edit profile error
- Fix quickStart change proxy error
- Fix core version

## v0.8.10 (2024-06-05)

- Fix core version

## v0.8.9 (2024-06-05)

- Update file_picker
- Add resources page
- Optimize more detail
- Add access selected sorted
- Fix notification duplicate creation issue
- Fix AccessControl click issue

## v0.8.7 (2024-05-31)

- Fix Workflow
- Fix Linux unable to open
- Update README.md 3
- Create LICENSE
- Update README.md 2
- Update README.md
- Optimize workFlow

## v0.8.6 (2024-05-31)

- optimize checkUpdate

## v0.8.5 (2024-05-30)

- Fix submit error

## v0.8.4 (2024-05-30)

- add WebDAV
- add Auto check updates
- Optimize more details
- optimize delayTest

## v0.8.2 (2024-05-15)

- upgrade flutter version

## v0.8.1 (2024-05-15)

- Update kernel
- Add import profile via QR code image

## v0.8.0 (2024-05-11)

- Add compatibility mode and adapt clash scheme.

## v0.7.14 (2024-05-07)

- update Version
- Reconstruction application proxy logic

## v0.7.13 (2024-05-06)

- Fix Tab destroy error

## v0.7.12 (2024-05-06)

- Optimize repeat healthcheck

## v0.7.11 (2024-05-06)

- Optimize Direct mode ui

## v0.7.10 (2024-05-06)

- Optimize Healthcheck
- Remove proxies position animation, improve performance
- Add Telegram Link
- Update healthcheck policy
- New Check URLTest
- Fix the problem of invalid auto-selection

## v0.7.8 (2024-05-05)

- New Async UpdateConfig
- add changeProfileDebounce
- Update Workflow
- Fix ChangeProfile block
- Fix Release Message Error

## v0.7.7 (2024-05-04)

- Update Selector 2

## v0.7.6 (2024-05-04)

- Update Version
- Fix Proxies Select Error

## v0.7.5 (2024-05-03)

- Fix the problem that the proxy group is empty in global mode.
- Fix the problem that the proxy group is empty in global mode.

## v0.7.4 (2024-05-03)

- Add ProxyProvider2

## v0.7.3 (2024-05-03)

- Add ProxyProvider
- Update Version
- Update ProxyGroup Sort
- Fix Android quickStart VpnService some problems

## v0.7.1 (2024-05-01)

- Update version
- Set Android notification low importance
- Fix the issue that VpnService can't be closed correctly in special cases
- Fix the problem that TileService is not destroyed correctly in some cases
- Adjust tab animation defaults
- Add Telegram in README_zh_CN.md
- Add Telegram

## v0.7.0 (2024-04-30)

- update mobile_scanner
- Initial commit
