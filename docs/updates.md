# Update checks

Android checks its independent manifest at
`https://updates.lifeaxis.fun/lazer/version.json`. Other platforms retain the
GitHub releases flow described below. Neither flow sends account, library,
playback, or other business data. A failed check never interrupts playback or
startup. See [Android cloud releases](releases/android-cloud.md) for signing,
download verification, packaging and full-snapshot deployment requirements, and
[Aliyun OSS hosting](releases/aliyun-oss.md) for the self-hosted download site.

## Where the current version comes from

`lib/diagnostics/build_info.dart` exposes `BuildInfo.version`. Release builds
are stamped by CI with `--dart-define=LAZER_VERSION=<tag>`; local builds fall
back to the version checked into the source. A branch name is not a version, so
it falls back instead of confusing the comparison. `BuildInfo.displayVersion`
adds the `v` the About row shows.

## What counts as newer

Android compares the installed package's **numeric versionCode**, read through
the native bridge, with the manifest code. It does not use SemVer to decide
whether Android can upgrade. Downloads are restricted to versioned HTTPS APKs
under the Lazer directory on the configured update domain. All manifest fields
are validated before showing an update. A missing manifest is a check failure,
not an assertion that the installed app is current.

On other platforms:

`lib/updates/release_version.dart` implements SemVer precedence:

- tags may be written `v2.0.0-beta.2`, `1.5`, or carry a `+build` suffix;
- `2.0.0-beta.2 < 2.0.0-beta.10 < 2.0.0`;
- numeric pre-release identifiers sort below alphanumeric ones.

Drafts and tags that do not parse are ignored. The newest release strictly
greater than the running version wins. A stable build only considers stable
releases; a pre-release build also considers later pre-releases, so beta users
can move from beta 2 to beta 3 while 2.0 users are not pushed onto a beta.

## When it runs

- **Startup.** `AppShell` schedules a check four seconds after the first
  frame when production enables `autoCheckUpdates`. At most one automatic check
  runs per 24 hours (`AppState.updateCheckInterval`); the timestamp of the last
  successful check is persisted.
  A failed startup check retries after five minutes in the same session. The
  shell checks whether the daily interval is due once an hour while open.
  A device clock correction cannot leave a future timestamp blocking checks.
- **Return to foreground.** The shell schedules a check after two seconds,
  respecting the same daily cadence and the five-minute automatic retry window.
- **Settings → About → 检查更新.** A manual check ignores both the daily
  interval and a previous skip.

A check has an 8-second timeout and routes through the same system proxy as the
external charts (`SystemHttpProxy`). Failures are silent on startup and produce
a short snack bar for a manual check.

## Reminding and skipping

On Android, the dialog shows the version, actual byte size and release notes.
**下载更新** downloads into the app's private cache with progress, cancel and
retry. SHA-256 and size are checked before native package/version/signer checks.
Installation rechecks the file and opens Android's system installer; it is never
silent. When needed, the dialog explains the per-app unknown-source permission
and resumes installation after returning from system settings. Refusal leaves
the music player usable. No update notification or storage permission is added.
**稍后** dismisses a nonmandatory update; a mandatory manifest cannot be skipped.
The publisher defaults to nonmandatory releases. Exact current signer sets must
match: key rotation is deliberately not supported by this updater.

The following release-page/skip controls apply to the existing desktop flow:

A found release opens one dialog with the release name, notes, version pair and
the release page URL:

When another dialog covers the app or it is in the background, the found
release is retained and presentation is retried every five seconds without
another network request.

- **前往下载** opens the page in the system browser. Desktop starts
  `rundll32`/`open`/`xdg-open`; Android and iOS answer a small
  `fun.lifeaxis.lazer/updates` channel. No `url_launcher` dependency is needed.
- **稍后** closes the dialog for this session. The next launch may offer the
  same release again after the daily interval.
- **跳过此版本** persists the normalised version in
  `lazer_skipped_update`. Automatic checks ignore exactly that version; a newer
  release still prompts. The About section shows the skipped version with a
  **恢复提醒** action, so a skip is never a dead end.

The jump from a skipped release to a newer one is intentional: skipping beta 2
does not silence the beta 3 announcement.

## Tests

`test/update_checker_test.dart` covers version parsing and ordering, release
selection for stable and pre-release builds, drafts/malformed tags, HTTP
failures, the daily cadence, clock corrections, deferred prompts, automatic
retry, and the skip/manual override. `http.Response`
objects are injected, so the suite never touches the network.

`test/android_updates_test.dart` additionally covers manifest trust boundaries,
numeric code selection, no user-bearing query parameters, download corruption,
native rejection, cancellation, permission refusal/return and dialog content.
Native APK identity validation must also be exercised with the actual formal
signing identity on a working Android device before claiming an end-to-end
production upgrade has been verified.
