# Classroom demonstration

## Materials

- [Editable presentation](demo/Household-demo.pptx)
- [Silent walkthrough video](demo/Household-demo.webm)
- [Publishing options](APP_STORE_OPTIONS.md)

The video uses captioned slides and real Flutter UI captures from the automated walkthrough. It is not a live device screen recording. It has no audio; the presentation speaker notes provide a narration script. Captures use November 4, 2026 for repeatability. The running app generates demo dates relative to the current date.

## Live walkthrough (about 3 minutes)

1. Launch the app. Open **Household → Load demo household → Confirm**. This intentionally replaces locally saved data.
2. Open Chores. Show five chores, the overdue kitchen task, and filters for overdue, today, and upcoming.
3. Select **My Responsibilities** as Alex. Only Alex’s chores appear. Complete **Take out the trash**.
4. Select **Household chores → Upcoming**. The next trash occurrence belongs to Jordan and is due one week later.
5. Open **Completion history**. Show Alex’s saved completion with its original due date.
6. Open **Fairness**. Alex now has one recorded completion. Explain that counts do not represent equal effort.
7. Open **Household**, select Sam, then complete **Water the plants** from Chores → Today. Its weekly repeat stays with Sam because the assignment is fixed.
8. Add a chore with a title, due date, assignee, repeat schedule, and eligible roommates. Use the card menu to edit/reassign or delete it.
9. Remove Sam in Household. The fixed plant chore becomes unassigned and asks for reassignment. History remains intact. Editing it lets the household choose a new owner.
10. Restart the app/browser page to show that data persists locally. Explain that a different device has separate data, and secure shared households are future work.

## Questions to be ready for

- **What if someone taps complete twice?** Busy-write guarding and an occurrence token reject duplicate or stale actions. History is saved together with the next occurrence in the local snapshot.
- **What if a weekly chore is weeks overdue?** Save one actual completion, advance to the first future scheduled date, and rotate once. Do not invent work for missed weeks.
- **What if a month has fewer days?** Clamp to the last date, then restore the monthly anchor in the next month that supports it.
- **Can we share across phones?** Not in this local demo. A production backend needs authentication, household permissions, transaction-safe occurrence completion, and synchronized state.
- **Can it go on the App Store for free?** The accredited school may qualify for a membership fee waiver or publish under its existing team. See the sourced publishing guide.

## Reproduce the captures

Use a writable output directory and Flutter’s bundled Roboto font path:

```sh
DEMO_CAPTURE_DIR=/absolute/output/directory \
DEMO_FONT_PATH=/absolute/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf \
flutter test test/demo/capture_demo_test.dart
```

This optional test is skipped by regular CI. It loads the real fonts, drives the app, checks the rotation, and captures the UI. Standard tests do not need those environment variables.
