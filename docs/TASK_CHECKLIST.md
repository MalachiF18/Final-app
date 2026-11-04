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

## Remaining release work

- Grocery sharing is explicitly planned, not implemented in this chore milestone.
- The confirmed local demo does not include accounts, invitations, Supabase, or shared-device concurrency.
- iOS runner, physical iPhone testing, signing, release icons/store metadata, and App Review remain future publishing steps.
- Local shared preferences are not a production database or a backup mechanism.
- Store and course submission require their respective destination/account requirements.
