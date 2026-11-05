# Screenshot task checklist

Scope: locally saved school demo, confirmed by the project owner. No backend deployment or store publication is represented as complete.

| Screenshot task | Implementation / evidence |
| --- | --- |
| 2.1 Household chore dashboard | Chores screen, due-date ordering, open and overdue totals |
| 2.2 Create, edit, delete | Validated editor; card action menu; deletion confirmation; history retained |
| 2.3 Assign roommates, due dates, repeat schedules | Active assignee, calendar date picker, once/daily/weekly/monthly |
| 2.4 My Responsibilities | Selected-roommate filter and screen title |
| 2.5 Complete chores and save history | Persisted completion snapshots and history screen |
| 2.6 Automatic rotation | Next eligible active roommate after saved completion |
| 2.7 Agreed fixed assignments | Explicit fixed toggle; skips rotation |
| 2.8 Overdue, reassignment, members leaving | Overdue stays visible; edit/reassign; departed members excluded; fixed chores become unassigned |
| 2.9 Upcoming and overdue responsibilities | All / Overdue / Today / Upcoming filters, including personal view |
| 2.10 Rotation, recurrence, duplicate prevention tests | Domain tests include concurrent duplicate requests, stale edits, month boundaries, fixed assignments, departures, and restart persistence |
| Fix README | Setup, honest feature scope, schedule rules, validation, code map, publishing links |
| Accessibility, empty/loading/errors | Semantic tooltips, minimum targets, contrast test, 360px/2× text checks, progress indicators, empty guidance, retry/read errors, save rollback |
| Demo household, presentation, video | Maple House seed; editable deck and silent captioned video in docs/demo; walkthrough in DEMO.md |
| Final review, bug fixes, submission | Source review and automated checks; GitHub commit/PR provides the reviewable submission package. No external course portal or App Store upload is implied. |

## Milestone 3 grocery and fairness checklist

| Task | Implementation / evidence |
| --- | --- |
| 3.1 Shared grocery and household-supply list | Grocery tab shares the household store and includes a starter demo list |
| 3.2 Add, edit, remove, quantities, categories | Validated editor, seven categories, quantity 1–99, action menus, and removal confirmation |
| 3.3 Claim shopping items | Acting roommate can claim/release; another roommate cannot purchase a claimed item |
| 3.4 Purchased status and buyer | Purchase saves item, quantity, category, roommate ID/name, and timestamp snapshots |
| 3.5 Sync list changes | Revisioned persistence, five-second polling, lifecycle-safe store refresh, and manual refresh for instances using the same browser/device store |
| 3.6 Transparent contribution rules | Dashboard states one completed chore or one purchased item equals one point; quantity, cost, and category do not change points |
| 3.7 Calculate recorded contributions | Totals derive only from persisted chore completions and purchase records |
| 3.8 Weekly and monthly dashboard | This week / this month filters with per-roommate chore, purchase, and point totals |
| 3.9 History and undone completions | Unified newest-first history; safe undo restores the chore occurrence or shopping item and removes the contribution |
| 3.10 Sync and fairness tests | Domain tests cover CRUD, claim protection, buyer snapshots, period boundaries, instance refresh, and undo; widget test covers purchase through fairness recalculation |

## Remaining release work

- The confirmed local demo does not include accounts, invitations, Supabase, cross-device synchronization, or conflict merging. Local refresh coordinates app instances only when they use the same browser/device storage.
- iOS runner, physical iPhone testing, signing, release icons/store metadata, and App Review remain future publishing steps.
- Local shared preferences are not a production database or a backup mechanism.
- Store and course submission require their respective destination/account requirements.
