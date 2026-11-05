# Validation record

Milestone 3 checked November 5, 2026 using Flutter 3.47.7 / Dart 3.13.5. Earlier artifact checks were performed November 4, 2026 using Flutter 3.47.2 / Dart 3.13.2.

## Passed locally

- `dart format --output=none --set-exit-if-changed .`: 18 Dart files, no changes.
- `flutter analyze`: no issues.
- `flutter test`: 40 passed. One optional capture test is skipped unless its output/font environment variables are provided.
- Optional capture test with real fonts: passed, produced seven screenshots of the running widget tree and verified the demonstrated rotation.
- `flutter build web --release`: succeeded.
- `flutter build apk --release`: succeeded for the earlier chore milestone, approximately 52.5 MB. The Android build was not rerun for milestone 3 because this machine currently has no Android SDK. It uses the repository’s existing debug signing configuration and is not a Play Store signing setup.
- Presentation: nine slides; package structure, layout geometry, declared Arial fonts, and re-import passed. All slide previews inspected.
- Video: 1280 × 720, 24 fps, 72 seconds, silent WebM; encoded successfully and a decoded frame was visually checked. This is a captioned slideshow walkthrough using real app captures, not a live device recording.
- `git diff --check`: no whitespace errors.

## Coverage

Domain checks cover weekly and daily recurrence, monthly leap-year clamping and restoration, fixed assignment, rotation order, member departures, no remaining eligible members, stale edits, future-date completion rejection, assignment validation, single-occurrence completion, concurrent duplicate requests, restart persistence, rollback after a storage failure, grocery CRUD, claim protection, buyer snapshots, reminders, local household setup, weekly/monthly contribution windows, local store refresh, and undo recalculation.

Widget checks cover local onboarding, home-first feature navigation, dashboard and personal filtering, completion/history, chore creation, reminder creation/completion, the full add-item → purchase → fairness → undo flow, read failure/retry, navigation at 360px width and 2× text size, labeled controls, Android tap targets, and text contrast. Existing calendar-date tests also pass. The running Chrome home dashboard was visually inspected after hot restart.

## Limits of this validation

No physical Android/iPhone device test or iOS archive was performed. The web release compiled and the debug app launched in Chrome; automated UI checks came from Flutter’s widget-test renderer. No claim of full screen-reader certification, production database durability, cross-device synchronization, authentication, or conflict merging is made. Store polling and manual refresh cover app instances using the same browser/device storage only.

The SDK and build caches were staged in the temporary workspace. The local SDK architecture detection needed an environment workaround; application source and CI use the standard pinned Flutter release. GitHub CI independently runs formatting, analysis, tests, web build, and Android build on Linux. Check the PR’s current Actions status for the remote result.

## Artifact hashes (SHA-256)

| Artifact | SHA-256 |
| --- | --- |
| Android APK | `fc1efab65062f1a05d81e9ee434eb09576434f54f6955b97691635c1a618f527` |
| Presentation | `14c47d5aba23c4b456e5cfc1c65ff77517965dfd1f54f29a7628fdfd1711a22b` |
| Walkthrough video | `65a22ddf5e2b3f49167fcc1423c0b7e750db7c284890b6ad2e5d4a7ca9f450f8` |

The APK is provided as a local deliverable and through CI artifacts rather than being stored as a large Git blob. Presentation and video are checked into `docs/demo/`.
