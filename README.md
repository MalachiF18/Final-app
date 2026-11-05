# Daily Improvement Household

A Flutter school demo for organizing household chores, sharing a grocery and supply list, and showing transparent contribution totals.

[![CI](https://github.com/MalachiF18/Final-app/actions/workflows/ci.yml/badge.svg)](https://github.com/MalachiF18/Final-app/actions/workflows/ci.yml)

## What works

- Local welcome, profile, and join/create-household onboarding flow.
- Home-first dashboard matching the project wireflow, with feature cards and weekly progress.
- Household chore dashboard with overdue, today, and upcoming filters.
- Create, edit, reassign, and delete chores with due dates.
- One-time, daily, weekly, and monthly schedules.
- My Responsibilities for the selected demo roommate.
- Completion history and per-roommate contribution counts.
- Shared grocery and household-supply list with quantities and categories.
- Add, edit, remove, claim, release, and purchase shopping items.
- Buyer snapshots and purchase history that survive later list edits or removal.
- Weekly and monthly fairness views combining completed chores and purchases.
- Transparent one-action/one-point rules and safe undo with immediate recalculation.
- Household reminders with dates, times, editing, completion, and deletion.
- Settings for members, household name, rotation rules, and in-app reminder status.
- Rotation through eligible active roommates, agreed fixed assignments, and departure handling.
- Local persistence, loading and error states, rollback on save failure, and duplicate-completion protection.
- Same-browser/device app instances poll the shared local store and can be refreshed manually.
- A resettable Maple House demo with three roommates, five chores, and starter shopping items.

**This is a local demo.** Data stays in this browser/device using `shared_preferences`. Roommate selection is a demo control, not authentication. App instances using the same local store poll for newer saved revisions, but there is no Supabase integration, invitation flow, conflict merge, or cross-device synchronization. Clearing browser/app storage removes the data. Preferences are suitable for this demo, not a production database or backup.

## Run

Use Flutter **3.47.2** / Dart **3.13.2**, matching CI.

```sh
flutter pub get
flutter run -d chrome
```

For Android, install the Android SDK/JDK and run `flutter run` with an emulator or device. iOS setup and publishing requirements are in [App Store options](docs/APP_STORE_OPTIONS.md).

## Try the demo

On a fresh install, choose **Create account**, enter a local profile name, then either create a household or join with demo invite code `MAPLE`. Existing households can open **Settings → Members → Load demo household**. This replaces local demo data. Choose the acting roommate in Members, then return Home to open Chores, Groceries, Reminders, or Progress. See [demo walkthrough](docs/DEMO.md), [task checklist](docs/TASK_CHECKLIST.md), and [validation record](docs/VALIDATION.md).

## Schedule rules

Dates are local calendar dates; no time-of-day deadlines. Completion is available on or after the due date, and only for the selected assigned roommate. Overdue chores stay assigned until completed or manually reassigned. Completion saves a snapshot and, for repeating chores, advances to the first future scheduled date. Missed dates do not create fake completions or extra rotations. Weekly schedules preserve the weekday; monthly schedules retain the original day, clamping short months (January 31 → February 28/29 → March 31).

Rotation follows the eligible roommates’ household order. A sole eligible roommate keeps the chore. Fixed assignments skip rotation. When someone leaves, their rotating chores move to the next eligible active roommate; fixed chores become unassigned until explicitly reassigned. With no eligible roommate, a chore is flagged unassigned. History survives departures, edits, and chore deletion. Editing a schedule starts its monthly anchor at the edited due date and invalidates stale completion actions.

## Validate

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
flutter build apk --release
```

Unit tests cover rotation, fixed assignments, overdue recurrence, leap-year month boundaries, departures, restart persistence, save failure rollback, stale edits, duplicate/concurrent completion, grocery CRUD, claims, purchases, reminders, local household setup, refresh between store instances, period totals, and undo recalculation. Widget tests cover onboarding, home navigation, reminder completion, chore creation, the purchase-to-fairness workflow, history, empty/error states, large text, and accessibility guidelines. Android release builds currently use debug signing and are classroom artifacts, not store-ready releases.

## Code

- `lib/data/household_store.dart`: versioned local storage, chores, groceries, purchases, contributions, refresh, and undo transitions.
- `lib/features/onboarding/`: local profile plus join/create-household flow.
- `lib/features/home/`: home dashboard and wireflow-style feature navigation.
- `lib/features/chores/`: dashboard, personal view, editor, and history.
- `lib/features/groceries/`: categorized list, claims, buyer recording, editing, removal, and purchase undo.
- `lib/features/reminders/`: dated household reminders and completion state.
- `lib/features/settings/`: members, household details, rotation guidance, and reminder settings.
- `lib/features/household/`: roommate selection, membership, demo reset.
- `lib/features/fairness/`: transparent weekly/monthly totals and contribution history.
- `lib/core/`: navigation, theme, calendar-date labels.
- `test/`: domain and UI regression tests.
- `docs/`: demonstration, task evidence, and publishing research.

## Submission and publishing

The code and demo materials can be reviewed in GitHub. See [App Store options](docs/APP_STORE_OPTIONS.md) for the school fee-waiver route and free alternatives. An App Store listing requires an eligible publisher, an iOS build, store metadata, and Apple review. A course submission still needs the instructor’s destination and requirements.
