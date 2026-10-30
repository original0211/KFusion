# Changelog

## v0.2.38 (2026-10-30)

**Features**

- The dialog layer joins the Hara A surface. The shared dialog components — the common alert, the input dialog and the facade the app calls them through — retire the liquid-glass material and the capsule buttons: panels are now flat fields in the page background colour, closed by a hairline border, and the action row is unfilled text whose hierarchy is carried by type weight alone, the default and destructive actions set a step heavier and the destructive action keeping its system red as a text colour. Titles and body copy take the shared type scale, and input fields take the square corner. Return values, barrier behaviour, validation and focus flow are exactly what they were — only the presentation changed. (8ae4ca0)

**Bug Fixes**

- Switching nodes under sing-box works for names beyond plain ASCII. The clash API client wrote its JSON request bodies as strings, and with no charset on the content type the HTTP stack fell back to Latin-1 — so any node or group name holding a character above U+00FF (Chinese names, flag-emoji names, in practice most real panels) raised an argument error on the device and the switch silently rolled back to the previous selection before a single byte was sent. Request bodies are now encoded as explicit UTF-8 bytes with a declared content length. The read paths never carried this defect, and the mode and connection calls, whose payloads are pure ASCII, send byte-for-byte what they sent before. (d0403e7)
- The Android launcher icon is rebuilt on the standard adaptive structure. The foreground, which reached its bitmap through a bitmap element wrapping a mipmap, now references the full-colour vector glyph directly, and the monochrome layer — which pointed at that same colour bitmap — gains a dedicated monochrome vector of its own, the ring-and-point glyph carried in alpha. On ROM icon pipelines that mishandled the inherited structure the glyph was dropped or tinted into the white ground, and the icon rendered as a blank white disc in the drawer and the system app-info page; the resource change also gives those pipelines a new structure to generate from. The legacy raster icons used by older Android versions are untouched. (0792ff2)
- The point returns to the Android system icons. The quick-settings tile, the foreground-service notification icon and the sing-box status icon drew ring and point inside a single even-odd path, and the fill rule cut away the part of the point that overlaps the ring band — roughly five percent of the point survived, a faint crescent where the mark carries a full dot. The point now stands in a filled path of its own, with every geometric parameter — the ring, the point radius, its seat on the ring midline and the 157-degree bearing — exactly as designed. (91c9500)

## v0.2.37 (2026-10-30)

**Features**

- The dashboard disc completes its unification with the brand mark: the crescent bite that used to be cut out of the ring at 157 degrees is gone, and the ring now carries the mark's single point at the same angle. The point is a state light — it burns vermillion exactly while a core is running (connected, or suspended with the core alive) and the ring stands empty otherwise, the same rule the tray icon follows. The point takes over the status marker's old job, so the status row's separate dot retires and any one screen still shows at most one vermillion mark. The decorative readings of the disc — the brand empty state, the core-switch row glyph and the profile card watermark — render the same ring and never light. (5014645)

**Bug Fixes**

- The brand mark now survives dark surfaces. The About page hero, which pointed at the monochrome asset, returns to the full-colour mark and picks a field by theme: ink ring with the vermillion point on light, a pale ring (#EDEDEA) with the dark-field point (#B03A30) on dark, where the ink version used to vanish — and took the point's colour with it even in light mode. The Windows tray gains dark-field variants of all four states, chosen from the taskbar's own light/dark setting and refreshed the moment the system theme changes. The launcher icon is regenerated at the design's small-size floor — a heavier ring and a full-size point — after the master's hairline weight shrank below visibility at drawer sizes and the icon rendered as a blank white disc. The Android quick-settings tile, foreground-service notification and sing-box status icons, which still carried the retired T-disc silhouette, now carry the current mark, and the last two hard-coded KFUSION brand strings read through the appName constant like everything else. (e152147)
- Two leftovers from the rebrand and one silent failure. The tray's taskbar-theme probe read the registry with a malformed key path (doubled separators in a raw string), so the open always failed and the failure was swallowed — the SystemUsesLightTheme reading shipped in the dark-field work never actually took effect on a real machine and the icon always fell back to the platform brightness; the key now uses single separators like every other registry read in the tree. The Android notification channel name and the sing-box VPN notification title, which still said KFusion, now say Vessel Service and Vessel · sing-box (display strings only; the channel id is untouched, so existing notification settings carry over). (6d18e22)
- Sing-box becomes a full second core instead of a display-only one, and its process lifecycle is hardened. While sing-box bears the traffic, node selection, mode switching and delay tests now go to its panel API (new changeProxy, patchMode and closeConnections on the clash API client, with the panel's own error messages surfaced); the renderer emits the clash_mode rules that give the panel a real mode list (rule, Global, Direct) and the app mode is synced to the core at start. The dashboard ring, whose tap was hard-wired to nothing under sing-box, now stops sing-box exactly as it stops mihomo. On lifecycle: exiting the app stops sing-box as well as mihomo, so no orphaned sing-box.exe is left holding port 7890; a startup self-check reclaims any orphan that does survive, with process enumeration that reports its failures instead of silently returning an empty list (PowerShell CIM, with a corroborated tasklist fallback whose unverified entries are reclaimed only when they provably hold the port and match the app's own binary). A stop only counts when the run state and the port are actually released, and when port 7890 is occupied the failure message names the owner — a leftover sing-box from the previous run, this app's mihomo core process, another named program, or an explicitly unidentified one. Delay testing gains a visible testing state in the section head, and when a test-all run finishes the list re-sorts itself by delay (measured first, timeouts at the bottom) in presentation only — the stored configuration order and the current-exit marker are untouched. (25f01bd)

## v0.2.36 (2026-10-30)

**Features**

- The app is now Vessel: the display name, the repository and every user-facing brand string change from KFusion to Vessel, and the icon becomes the approved one-point mark — a fine ring carrying a single vermillion dot at 157 degrees — regenerated for the launcher in its adaptive and legacy sets, for the Windows icon and for the tray, with a monochrome variant for the About page hero and for the 16-pixel icon entry, where the dot's hue cannot survive. Nothing that identifies the app to the system moves: the Android applicationId, the package names, the signing certificate, the executable names and the Windows installer AppId are all unchanged, so an existing install upgrades in place and keeps its data. This release also completes the behaviour subtraction programme: the standard override and the global added-rules editor, WebDAV sync and the custom profile editor and custom resources are gone (stored data stays in place, inert), while custom profiles keep rendering read-only. (60806b9)

**Bug Fixes**

- The views smoke test no longer imports the action library that the custom profile editor's removal left unused in it; the stray import tripped the analyzer's fatal-warnings gate in CI. Test-only change — no application code is affected. (c4eeacb)

## v0.2.35 (2026-10-29)

**Features**

- **ui** The delay test-all entry moves from the subscriptions header to the main screen: it now stands at the head of the node list, where the delays it refreshes are the ones being read, and the subscriptions header keeps only its update and sort actions. The test itself is unchanged — it still runs every group of the current profile through the same action, with the same testing state and the same write-back into the node rows; only the entry point moved. (397566a)

**Bug Fixes**

- **ui** The main screen's pinned compact bar no longer slides under the system status bar once the node list is scrolled: its content now honours the top safe-area inset, as the hero header already did, so the disc, the status dot and the current exit name stay fully visible below the status bar. The bar's background still spans the full width behind the status bar, and its appearance threshold, collapse geometry and scroll behaviour are unchanged. (3c98ac2)

## v0.2.34 (2026-10-29)

**Features**

- **ui** The settings drill-down pages — theme, backup and restore, hotkeys, access control, about and the disclaimer — are read in the white Hara A language, completing the settings surface: the grouped cards, rims and rounded panels give way to hairline-separated rows on the plain white field, switches read as the ink-dot toggle mark, and selection checks and swatch rings render in palette ink instead of the seed primary. Every page keeps its composition, wiring and behaviour; only the surfaces moved. (3266d1d)

## v0.2.33 (2026-10-29)

**Features**

- **views** The settings half-page is read in the white Hara A language: its seeded Material switches give way to an ink-dot reading — a filled dot with the state word in ink when a setting is on, an empty slot with a dim word when it is off — its entry rows drop their icons and rounded chrome for hairline-separated text rows, and the page sits on the plain white container, in the same language as the main screen and the subscriptions screen. The composition is unchanged — core switch card, startup and takeover rows, everyday entries, the Advanced gate, and disclaimer and about at the foot — and the pages inside the gate keep their existing face. (3080008)
- **dashboard** The main screen exit row gains the exit's country. The exit probe already returns a country code alongside the address; a local table covering 52 countries in all seven app languages turns the code into a name, with no extra network lookup. The country lands together with the address, ahead of the connection type. (5677e60)
- **dashboard** The main screen exit row then stops printing the address itself and reads country and type only — for example 日本 · 住宅. The address stays in use internally, feeding the type lookup, and remains visible on the quality details page; when the IP is hidden, the row still shows ***** instead. (b50561e)
- **views** The core switch card is read in the Hara A language too: the rounded, shadowed panel is gone, and the card's content — title, status and the two core rows with their disc marks — now sits directly on the page field, separated by hairlines and hit-tested through square areas. Wiring, states and behaviour are unchanged; only the surface moved. (874607b)
- **ui** The selection check beside the running core on the switch card now renders in palette ink instead of the shared mark's seed primary, completing the card's Hara reading. The shared SelectionCheck only gains an optional color; every other surface keeps the scheme primary. (5eb133d)

## v0.2.32 (2026-10-29)

**Features**

- **views** The dashboard and the proxies readings merge into one main screen: the contour ring, the status row, four figures (delay, exit, core and session traffic) and the mode row now sit above the grouped node list on a single scroll surface, and the status compacts into a pinned bar as the list scrolls. Navigation settles at three entries: main screen, subscriptions and settings. The running core is carried by the ring and the status row while the idle core is only named at the end of the brand row; while connected, the current exit row is marked with a text label instead of the vermilion dot, which stays unique to the connection status. (6ab08fb)
- **profiles** The profiles screen becomes the subscriptions screen: it takes the settled title and gains a test-all-delays entry in its header, running the existing per-page delay test over every group. (bded3d7)
- **dashboard** The main screen exit row appends the exit IP's type (residential, data center, mobile or business) as soon as the quality lookup knows it. Until then, and whenever the lookup fails, the row shows the address alone. (c1b5a7d)
- **views** Settings settle into a half-page: the core switch card on top, the startup and takeover rows below it, the everyday entries (language, theme, backup, hotkeys and access control) as single rows, and the disclaimer and about at the foot. Everything else moves behind one Advanced gate (the advanced settings subtree, custom resources, proxy settings, resources, logs, fonts and the developer page) and keeps its existing face inside the gate; a custom profile's editors are reached as "advanced edit" from its row menu. (a61dee9)

## v0.2.31 (2026-10-29)

**Features**

- **singbox** A native sing-box JSON profile is now fed to the sing-box kernel exactly as imported instead of being converted through the clash render. The universal import recognises the format, checks its structure and stores the bytes untouched; switching to such a profile hands the stored text to the kernel as-is, with its ports, TUN inbound and readiness following the config itself, which must declare its own experimental.clash_api endpoint for the app's panel and probes. Mihomo refuses a native profile in plain words at preflight instead of failing obscurely, and the degradation ledger treats a native profile as not applicable instead of reporting an empty list. (5932a9c)

## v0.2.30 (2026-10-29)

**Features**

- **singbox** The degradations a sing-box render records for a profile are now presented in the app instead of living only in a file next to the rendered config. Each profile keeps its own ledger — a sidecar written when the profile is saved, refreshed or switched to — and the profiles screen shows the count on the profile's row and opens a page that names every item, grouped by kind with a localized reason for each. A universal import ends with a one-time summary when the imported profile carries degradations. The page and the core-switch card read the same render ledger, so their counts always agree. (9e5a2a2)

**Bug Fixes**

- **singbox** The background scan that refreshes a profile's degradation ledger after an import could finish after the profiles provider had already been disposed or rebuilt, and its trailing refresh hint then threw instead of landing quietly. The hint now goes through the same mounted check the providers already use after an async gap: the ledger file is written before the hint either way, watchers in a dead container need no hint, and a later container reads the file fresh. (c30cbb4)
- **common** Removed a cache-directory warm-up in the app path helper that nothing ever read. The side future it fired had no error handler, so when the first path lookup happened before the platform binding was ready — as a plain test isolate does — the error escaped as an unhandled async failure and was blamed on whichever test happened to be running. No behaviour changes; the injection point the test helpers use stays. (74f2de8)

## v0.2.29 (2026-10-28)

**Features**

- **core** A Clash profile rendered for sing-box now follows a defined contract instead of a best-effort full translation. Only the mainstream node protocols convert — shadowsocks, vmess, vless, trojan, hysteria2, tuic, wireguard, socks5 and http — and groups keep only the selector and url-test shapes whose members are all nodes. The subscription's own routing is no longer translated rule by rule: a built-in template sends private addresses and the CN rule sets direct and everything else through the main group. Anything the contract does not carry — an off-contract protocol such as openvpn, a nested group, the source rules — is no longer dropped silently or left pointing at a name that was never emitted: each drop is recorded by name in one structured degradation ledger, also written next to the rendered config, ready to be presented in the app. (76f8ba6)

## v0.2.28 (2026-10-28)

**Bug Fixes**

- **core** A sing-box start no longer dies on a group member the renderer could not emit. Members were copied from the Clash config verbatim, so a node with no sing-box form — the openvpn home broadband nodes — or a dropped group left a name pointing at nothing: a reference the format check never resolves and the outbound manager rejects only at start, as a dependency not found. Members are now pruned to the outbounds actually emitted, every drop noted; a group left empty drops in cascade, rules and match targets that resolve to nothing are dropped or fall back, and a dialer-proxy maps to detour only when its target survives. A final self-check over every cross reference refuses to ship a config with any name left unresolvable. (d381d29)
- **config** Domain-addressed nodes no longer time out on profiles that bring no DNS of their own. The universal import keeps only proxies, groups and rules, so such a profile runs on the baseline DNS — which named domain-form DoH endpoints and no proxy-server nameserver, leaving a proxy server's own name to be resolved by first bootstrapping the nameserver's host through the default nameserver. The baseline now carries a dedicated proxy-server nameserver, and both nameserver lists use the IP-literal DoH endpoints a working subscription uses, so server names resolve directly; a guard keeps every baseline endpoint an IP literal. A subscription that brings its own DNS section is untouched, byte for byte. (3d5d666)

## v0.2.27 (2026-10-28)

**Features**

- **ui** The token layer takes the batch two additions: text styles for the action and payload readings and the spacing constants the new surfaces are measured in, so the proxies and profiles pages are built from named, settled values instead of figures repeated surface by surface. (9b3553c)
- **proxies** The proxies page takes the White reading: groups stand as section titles over hairlines, every node a single line, the selected row's name in full weight, a group row naming the leaf its chain actually exits through, and latency in the payload reading with the dashboard's empty mark where nothing has been measured. Testing every latency, the settings sheet and search are text actions in the title row. The picker keeps the old face until its own batch. (1acd92a)
- **profiles** The profiles page takes the White reading: the current profile's row carries the vermilion dot and the word for in use, over two meta lines — the kind, with a custom profile's group count, then traffic used of total, expiry and the last update in compact relative form, a small ring standing in while an update runs. Updating all and sorting are text actions. The add section stands three rows — from a link, from a file, and more, which still reaches the code scan, the custom form and the universal import — one row more than the concept drew, so nothing the old page reached is lost. (44f30d0)
- **profiles** The universal import is restyled to the same reading: a text title where the disc guide head stood, section titles over hairlines, the payload well framed by a hairline on four sides and set in monospace, the primary action as ink text over an ink underline, and errors in red text alone. Presentation only — every state, parsing, download, confirm and export step reads as it did. (b1b80d0)
- **profiles** The core kind selector in the profile editor takes the reading: text rows in place of the raised face, disc and check, the selected kind in ink with an ink underline beneath it, the rest dim. The choice itself is untouched — the same tap writes the same kind — and the switch card with its whole switch chain keeps its own surface, by the staggering rule between the two lines of work. (64d43d8)

**Bug Fixes**

- **ui** One vermilion dot per screen, and hairlines that span. The batch two screenshots caught the first dot rule — the exit leaf, selected in its own group — printing two dots when another group selected the same leaf; the dot is now read by walking the selection chain from the global group, and lands only on the chain's last leaf, so the settled count holds by construction. And on the new surfaces a hairline under a start- or centre-aligned column collapsed to no width at all; the columns stretch now, as the dashboard already read them, and the lines run their full measure. (7cbe06c)
- **profiles** The profiles header stays inside narrow widths. At a rail-width content column the title row overflowed — the text actions held their natural width and only the title gave. Title and action group each take their share now and scale down within it, the same rule the proxies page already kept; CI caught the overflow, and the fix is pinned where it was found. (e562e77)
- **core** A sing-box start no longer dies fetching a rule-set that does not exist. The renderer pointed the LAN address set at a remote file the upstream project never published — its rule-set branch carries country codes only — and the fetch answered 404 at rule-set initialisation, in the open now that a healthy start can no longer be failed on suspicion. LAN renders as the native private-address rule instead, the equivalent of the source format's GEOIP,LAN, with no start-time download at all; a mixed row keeps its remote rule for the country codes beside it, and a guard test pins the rendered remote set to exactly the two files measured live, so a future drift prints red. (e59ed59)
- **core** A sing-box start waits for the network it is about to dial through. The interface monitor's deliveries were posted to a handler lane while the start ran on to the rule-set fetch, whose first dial could read an enumeration still empty and fail with no available network interface — on device, eleven milliseconds ahead of the update that named the Wi-Fi. The monitor's start hook now waits, bounded at five seconds on the start thread, for the first delivery that has actually handed a named interface to the core; release and timeout each leave a line in the service log, and a timeout proceeds ungated, so a truly offline start still fails with its real error. Nothing retries the whole start, and the ninety-second budget is untouched. (3a9f1c0)
- **profiles** The profiles add rows' arrow takes its settled size. Independent sign-off found it set in the row's own reading where the spec settles arrows one step smaller; a token now carries that value — the typography guard admits sizes from the token layer alone — and the arrow takes it, the row's words unchanged. (7812f3d)
- **dashboard** The same correction on the dashboard's import row, found while the profiles one was being fixed: its trailing arrow rode the row's reading too, and now takes the arrow token. One line; the label is unchanged. (94535bc)

## v0.2.26 (2026-10-28)

**Bug Fixes**

- **core** A healthy sing-box start can no longer be pronounced dead for being invisible. The start gate judged the service by whether its /proc entry was visible from the app process, and a sibling process's entry is not reliably visible on Android — so a service that had written its own STARTING snapshot moments earlier, its pid fresh in it, could be failed as 'exited during start' while its router was still loading rule-sets, as the previous release's own verdict-inputs line caught in the act, twice in one start. The gate now returns only suspicion for an unseeable pid, and the poll must confirm the death in the platform's exit history — the same record window the death letter reads — before a start may be failed; unconfirmed, a RUNNING report is taken at the service's word and a STARTING one simply keeps waiting. The budgets, the polling beat and the record window are untouched: what changed is the standard of evidence, from one channel's guess to the platform's own record. (c5964f1)
- **core** Whether sing-box is running is answered from evidence now, not from visibility. The check shared the start gate's blind spot — a RUNNING report whose pid the app process could not see read as not running however alive the service was, so the interface restored itself around a phantom and more than one switch decision reasoned from the same false negative. A RUNNING report now stands unless the exit history overturns it: a death record for that process later than the report itself; anything older belongs to an earlier incarnation, and where the platform cannot answer, the report is taken at its word. Stopping a service likewise waits for the stop to be real now, instead of reporting success on the first blind look. (2d94976)
- **core** A slow sing-box start is given the time its slowest phase measurably takes. Fetching rule-sets alone has been seen alive past forty-nine seconds, beyond the old forty-second poll budget — which, once a start may no longer be failed on suspicion, would have torn a healthy start down for slowness alone. The poll budget is ninety seconds now, held in the gate where the contract tests pin it, and the Dart side's sing-box timeout follows at ninety-five, keeping its five-second margin over the service's own verdict; mihomo's budgets are untouched, and a death confirmed in the exit history still lands as fast as it ever did — only an unproven start is waited on longer. (0ac2402)

## v0.2.25 (2026-10-28)

**Features**

- **theme** The first layer of the Kenya Hara 'White' redesign: a fixed token layer — a six-value palette in light and dark, a settled type scale, hairline rules, and a standing ban on rounded corners, shadows and gradients on migrated surfaces — and the outline disc, the product mark redrawn as a fine ring whose centre stays empty. Guard tests pin the constitution, the disc's settled bite geometry among it, so the batches that follow build on values that cannot drift in silence. (e962fec)
- **ui** Navigation takes one text form on phone and desktop alike. The floating dock and the sidebar retire; a text bar and a text rail carry the section names as words instead, the current one marked — a name needs no icon to be found. Their elastic press survives the retirement, kept in its own file for the surfaces that still use it. (74915bb)
- **dashboard** The dashboard is rebuilt to the redesign's fixed composition: the outline disc as the connection state's whole portrait across all four states — unconnected, connecting, connected, failed — with the status line taking over the compact role when the page scrolls, standing in for the cabin core's compact bar. The card-customisable layout steps aside on this first surface; its data is kept, unpresented. (d3ae061)
- **ui** Three settled values restored where independent review found them drifted: the phone navigation bar's height, which had subtracted its top padding twice and come up short of the settled whole; the dashboard status line's spacing after its vermilion dot, returned to the settled figure; and the disc's bite geometry — direction, distance and radius — now asserted value by value in the guard tests, where before only its single declaration was watched. (d78ad37)

**Bug Fixes**

- **core** A death letter can no longer be lost to a closed ledger. The harvest used to look only at attempts still marked open, so an attempt settled by its own verdict — the ordinary way a failed start ends — became permanently invisible to it, and two releases in a row reached the failure card letterless even though the previous death had been recorded. The harvest now settles the most recent attempt whether its ledger stands open or closed, telling a service's own incarnation and an owner's own settlement apart by token — and an upgrade heals ledgers that older versions left closed, on its first start. (ce1cd7f)
- **core** An untouched crash report is no longer called unreadable. The native setup creates a fresh, empty report file at every start, and only a genuine crash ever writes into it — an empty file is a setup artifact, not a trace that failed to read. The crash-reason line now names that state 'report empty', and keeps 'unreadable' for a file that carries writing yet yields no readable line, so the two can no longer be mistaken for each other on the card. (7f6fa45)
- **core** A sing-box death verdict now leaves its inputs in the service log. When the failure card is composed, the snapshot that triggered the verdict — its state, its process id, its timestamp — is appended as one line beside the attempt's own sequence and start, so the next contested verdict can be settled from the record itself instead of being reconstructed from arithmetic on the card's log tail. Nothing about the verdict changes; only its evidence is kept. (51677e6)

## v0.2.24 (2026-10-27)

**Bug Fixes**

- **core** The death-letter harvest now asks the system for its exit records with a concrete cap, and survives a record whose trace will not open. The harvest used to request the unbounded form of the list — the one form that had never produced a visible result on the device in question, while the capped form beside it worked every round — so a death could go unlettered for reasons indistinguishable from the platform having nothing to say. The request now carries an explicit cap, a platform that answers nothing leaves a line in the service log saying the exit history was unavailable, and reading a record's trace is guarded, so one unreadable record can no longer take the whole harvest down with it. (2a3ff6e)
- **core** A death letter can no longer be lost to the numbering of the staged start. The ladder used to stamp each of its levels with a fresh sequence number, so a start that climbed several levels pushed the previous attempt's number far outside the window the failure card accepts, and the letter written for it was discarded in silence — three deaths in a row arrived letterless for exactly this reason. A whole start now takes a single sequence number, its levels refresh only their own label under it, and the start path itself settles the previous attempt before anything overwrites the ledger, giving the harvest a second chance at the one moment it cannot miss. (ebb8061)
- **core** The crash-reason line is now judged against the attempt it describes, on both paths that compose it. Freshness used to be measured from each reader's own clock: an early reader found the report inside its window and called it unreadable, a later one found the same untouched file outside its window and called it stale, and one death carried two verdicts. The plugin and the service now anchor the window to the attempt's own start, so one death, one file, one answer. (11dfd8f)

## v0.2.23 (2026-10-27)

**Bug Fixes**

- **core** A startup death now leaves a letter the next service start cannot miss. The card composed in the seconds after a death kept losing its race with the system, which publishes a process exit record asynchronously: three attempts in a row read not published yet, and the death stayed nameless. Every service start now harvests the full exit-record list — no process filter, no count cap — matches the attempt the ledger still holds open against it, earliest matching core record first and skipping records an earlier letter already consumed, and persists the outcome as a death letter, whether the harvest found the death or not. The card quotes the letter for its own attempt or the one before it, so a death that settles late still arrives with its reason, status and time — and a harvest that found nothing says how much it scanned and what the newest record in the list was. (131e4be)
- **core** Stage marks are now attributed to the attempt that left them. The marker file is one append-only stream shared by every core incarnation, and its offsets tick from each incarnation's own birth, so the card's global last line could quote a previous attempt — one card carried a +20.8s monitor mark that belonged to the attempt before it. The first mark of every incarnation now delimits its attempt: the card and the service log take only the window after the last delimiter, gated by the file's age against the attempt start, and an empty window reads stage mark: no marks this attempt instead of borrowing an older attempt's line. (9e2cb4e)
- **core** The crash-reason line now names three states with one vocabulary on both paths that produce it. The same death read report unreadable on the service path and no fresh report on the plugin path, because one helper folded a missing report into unreadable and the other folded it into not-fresh. A single helper now serves both: no report when no report file exists, no fresh report when the file predates the attempt window, and report unreadable only when a report inside the window cannot yield a line. (73813d3)
- **core** The daemon error line is now matched by its level field, not by substring. The line used to be the last log line containing ERROR or FATAL anywhere, so a DEBUG DNS answer spelling NOERROR posed as the daemon's error on the failure cards. Selection now strips the line's ANSI codes and parses the level that follows the sing-box prefix; only ERROR and FATAL levels qualify, whatever the message text says. (2fff69a)
- **core** The death-letter harvest never letters an attempt this process is still starting. A check or stop intent can surface while a start is in flight in the same process; writing that live attempt an unmatched letter would spend its one letter, and its real death later would be skipped as already harvested. The harvest now bows out while the start gate is held, leaving the live attempt's letter to the first surface after its outcome is known. (3e9f800)

## v0.2.22 (2026-10-27)

**Bug Fixes**

- **core** A startup death's card now always names the death's category and stage coordinate. The bare "exited during startup" line was all a non-crash death ever showed: the system publishes the process exit record asynchronously, and it routinely missed the few seconds the card waited for it, so the record was filtered away as stale and nothing was appended at all. The card now always closes with diagnostic lines gated to this attempt: the newest exit record's category line — its reason, status or signal, time and description — or an explicit line saying the record is not published yet; the last stage mark the core left behind, whatever the death turns out to be; the first line of a crash report fresh enough to belong to this attempt, or a note that there is none; and the daemon log's last error line, when it has one. The wait for the record is widened to about five seconds, still far inside the start budget. (ad99657)
- **core** The service log's death block now quotes the stage-marker trail for any surfaced exit record, not only Go crashes. The marks are how a death gets its stage coordinate — the last phase the core reached before it died — but they were appended inside the crash-gated part of the block, so a death by signal or by the low-memory killer left the service log as bare as the card. Any new exit record being surfaced now carries the marks with it, written once even when a crash block follows. (5a96621)

## v0.2.21 (2026-10-27)

**Bug Fixes**

- **core** The sing-box core no longer panics on a cellular interface's link-local IPv6 address. Interface prefixes handed to the core were built straight from the platform's address string, and a link-local address carries its zone along — fe80::…%rmnet_data1/64 — which the core's prefix parser rejects outright: IPv6 zones cannot be present in a prefix, raised as a panic inside the interface refresh that every monitor update runs, so the first update whose enumeration included the cellular interface killed the start. Interface prefixes are now rebuilt from the address's raw bytes before they are handed over, which strips the zone while keeping the address and its prefix length intact — the shape the reference client has always used. IPv4 prefixes are unchanged. (ca501eb)

## v0.2.20 (2026-10-27)

**Bug Fixes**

- **core** The sing-box interface monitor now warms up before a start and cannot lose a delivery in silence. Registration used to sit inside the start path, a breath ahead of the start itself, and the core could come up before any platform update had ever reached it — its interface list stayed empty and every dial in the rule-set downloads that follow a start reported no available network interface. The monitor registers when the service is created now, so the system's updates collect in the serialized lane ahead of any start; attaching a listener primes it from the network the system reports at that moment, seeded and replayed in one lane step, never from a snapshot taken at registration time. And a delivery whose link properties are not readable yet is no longer dropped: the cleared reading is delivered instead, which still has the core refresh its interface list, and the reading that lands later corrects the default. (c0e72c5)
- **core** The crash report's first line now closes the death block in the service log. A native death already surfaced the report's head, its tail and the stage-marker trail, but the line that names the failure sits at the top of that block — above the window a failure card shows. The last line of the block is now a crash reason line carrying the report's first non-empty line verbatim, so the reason reads off the card directly; a report that is missing or unreadable leaves a one-line note saying so. (b4816b5)

## v0.2.19 (2026-10-27)

**Bug Fixes**

- **core** The sing-box default-interface monitor now delivers the way the reference client delivers. Interface callbacks used to report from whichever system thread delivered them, straight into the core, while a start was still setting up; updates now pass through one serialized lane owned by the service — the system callbacks only post, link properties are read on the lane, and the core hears about the tracked network in arrival order, replayed to a listener that attaches late. Registration itself sits at the service layer, happens once per service lifetime ahead of the start, and is tiered by platform level the way the reference client tiers it; a report always carries the unmetered, unconstrained reading. (6a08d3e)
- **core** The interface monitor seeds before it registers. The monitor's initial state used to be queued after the system callback was registered, so the system's first update could land ahead of the seed and then be overwritten by the older snapshot; the seed is queued first now, and the first system update always lands on top of it. (62ef097)
- **core** A native death's crash report now shows its head as well as its tail. The service log carried only the report's last lines — the end of a goroutine stack — while the line that names the failure sits at the top of the file; when a death leaves a report tail, the head's first forty lines now land in the log ahead of it under a crash head prefix, and a report that cannot be read leaves a one-line note saying so instead of silence. (b90f118)
- **core** The stage-marker trail joins the crash report in the service log. The instrumented core writes a line at each start stage it reaches; when a native death leaves a crash tail, the last thirty marker lines now land in the log behind it under a stage mark prefix, so the stage the start had reached when it died reads off the log directly. A death that left no markers leaves no marker lines. (3015fbb)
- **core** The sing-box core is bound with the stage-marker patches applied. The bind that builds the core library from its pinned source now applies four small patches after the source sync — a marker writer, marks at the daemon's and the box's start boundaries and across the interface monitor's update path, and the marker file's path set during setup — and asserts every landing spot before the build proceeds, so an upstream change that moves a context line fails the build loudly instead of shipping an uninstrumented core. The patches live in the repository; the core source and the built library never do. (95e9d7e)

## v0.2.18 (2026-10-27)

**Bug Fixes**

- **ui** The core switch card takes the cabin panel shadow. The general settings page's core switch card already sat on the cabin card corner with the rim, but it lay flat where its dashboard sibling is lifted by the panel shadow; it takes the same shadow now, from the same surface definition, so the two presentations of the one switch read as one card. Nothing inside the card moved — title, status sentence, failure detail, the binary area, the two core rows and every callback are byte-identical. (c2e4147)
- **ui** The profile editor's core selector reads like the switch card. The editor used to pick a profile's core kind from a bare dropdown while the general page presents the same choice as two rows on the switch card; the editor now presents the two cores as card rows in that language — the core disc mark, the shared display name (sing-box keeps its hyphen), the running state and the selection check on the chosen row, which is inert, while the other row makes the same one call the dropdown made. The two platform captions keep their wording and their conditions and move inside the card. (e875d97)
- **ui** The disclaimer body takes a cabin panel. The disclaimer text used to read flat on the page; it now sits in a raised cabin panel — card corner, rim and panel shadow — with its wording unchanged. The consent bar below it is untouched. (d8a7047)
- **ui** The about page's marks settle into the cabin language. The logo well gains the cabin rim, and the version pill — a solid primary fill — now reads as a marker chip: a raised surface carrying primary text, the way markers read everywhere else in the cabin, instead of a lone filled badge. (1a96aed)
- **ui** Dialog and menu shapes take the cabin rim at the theme base. Dialogs, popup menus and menus already shared the floating corner; their theme shapes now carry the cabin rim side as well, defined in the one place all three shapes live, so every overlay the bases present is rimmed and there is no second definition anywhere to drift from it. (a84c2c0)
- **ui** The popup card takes the floating corner and a rim on its plain fill. The morphing popup card sat on a corner one step under the floating tier the other overlays settled on; it takes the floating corner now, its rows concentric inside it, and its plain fill — the non-glass reading — gains the cabin rim. The glass path is unchanged. (f996856)
- **ui** Sheet top corners settle on the floating corner. A sheet's crown sat one tier rounder than the dialogs and menus it appears beside; the snap sheet, the paged sheet and the theme's bottom-sheet shape now all take the floating corner, so every floating surface in the app crowns at the same radius. (dd79fcf)
- **ui** The segmented control's chosen face takes the ink variant. The selected segment used to fill with the accent; it now fills with ink and its label takes the page step — the quieter reading the cabin reserves for a mode choice — at the two places the control serves: the theme page's mode strip and the palette's core segments. No other surface takes the variant. (7a14c26)
- **ui** Error faces settle to plan B: red stays on the glyph and the words. The error banner's container was the error fill; it now sits on a neutral raised surface with the cabin rim, its icon and text carrying the error color. The error illustration's body returns to the neutral surface steps, red surviving only in the central glyph. The fatal start-up error screen keeps its full red face by design — plan B grades the everyday error faces, not the fatal one. (095e7cc)
- **core** A concurrent delete that reaches the same end state is no longer an error. Deleting a file checked that it existed and then deleted it, so two callers clearing the same cache file at once raced: the loser was handed a file-not-found exception for an absence that was exactly what it had asked for, and the spurious failure once reddened a release build's test run after the test itself had already completed. Deletion now treats 'already gone' as the contract fulfilled; every other failure still propagates. (8269cfa)

## v0.2.17 (2026-10-27)

**Bug Fixes**

- **ui** The record rows take the cabin row-card corner. The shared record row card — the one row the requests, connections, DNS queries and log screens are all built from — sat on the section-card corner and carried no rim, while every other cabin plate pairs its corner tier with the cabin rim. It drops to the row-card corner and gains the rim side, so the record lines read as cabin row cards like the rest of the interface; the wide-screen record tables already sat on the card step and keep it, and status chips, rates and every row action are untouched. (c888cbd)
- **ui** Log payloads sit in an inset well. A log entry's payload no longer reads flat on its row card: it recesses into a rimmed inset well — the same well form the profile payload took in the configuration line — with the entry's header staying on the card outside it. The level mark stays a small chip at the head of the row, its color the only color the row carries, and the payload text keeps its monospace step. (14b6243)
- **ui** The theme preview shows both cabins at once. The live preview no longer renders a single mini screen in the app's current brightness: the light scheme on the paper phone and the dark scheme on the dark phone stand side by side, sharing the one selection and animation state, so a scheme can be judged in both cabins before it is picked. The preview plate itself takes the cabin rim. (3eb8397)
- **ui** The theme page's plates take the rim, and the swatch marker stops changing color. The color swatch selection ring used to take each swatch's own fill, so the selected marker changed color with the swatch it sat on; it now stays on the scheme primary for every swatch, the way a marker should — the one accent the page allows itself. The page's bespoke plates — the swatch box, the font card, the text-scale plate and the custom-color preview — gain the cabin rim, their ink and layouts unchanged. (536b66d)
- **ui** The hotkey page's intro plate takes the cabin rim — the one bespoke plate on that page still missing it, now in line with the rest. The keycaps stay on the block step in monospace, and the conflict reading keeps the form the settings screens settled on. (90588e4)
- **ui** The DNS queries empty state takes the brand variant. Where the empty DNS list used to show the functional illustration, it now shows the gray disc mark the cabin language reserves for brand positions — the same motif the dashboard's core carries — with its label unchanged. (c22fd70)
- **core** Signaled sing-box deaths now arm the staged ladder and the cache isolation. Three full starts in a row died about a tenth of a second after the start call — two of them classified by the system as signaled deaths rather than native crashes — and the ladder never ran for the signaled pair, because the arming set and the cache-isolation gate both recognized only native crashes and low-memory kills. A signaled death at the same code point, with the same memory snapshot, is the same start failure under the system's other label — the crash pipeline simply filed no tombstone for it — so signaled deaths arm both gates now, and the isolation predicate lives in one place the two gates share; the isolation log line names its cause and stays byte-identical for native crashes. (3990a2a)
- **core** Signaled deaths are named by their signal, and the death card waits out the tombstone on one clock. The exit record has carried the killing signal's number all along; the card now reads it and names it, so a signaled death reads SIGNALED with its SIGSEGV, SIGKILL, SIGBUS, SIGABRT or SIGILL beside it — and whether a signaled death and a native crash at the same point are one death wearing two labels can finally be judged from the card. The crash headline's hunt no longer swallows its misses, either: when a native crash's trace cannot be read, the service log says which of the three ways it missed — the trace stream was unavailable, the trace was unreadable, or it held no signal line — on both channels that report a death. And the card's assembly now waits on a single shared budget for the attempt's record and, behind a native crash, for the headline, instead of the two racing separately; a settled record whose death is not a native crash stops waiting at once. (d3aadd2)
- **core** A render-side preflight rejection now says why. When a profile cannot be converted for sing-box because nothing in it is usable, the switch used to cancel with the bare 'cannot be converted' line and the reason nowhere on the card. The rejection now carries the renderer's own count: how many nodes speak protocols sing-box does not support — named by their own protocol strings — how many are wireguard nodes it cannot use, how many groups have no usable member, and how many unsupported group types, skipped REJECT members and untranslated rules account for the rest. A profile with nothing convertible at all gets its own plain sentence, and content that is not a recognizable Clash configuration at all gets another. The verdict itself has not moved — the same profiles are refused — but the refusal explains itself. (70ffbb1)

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
