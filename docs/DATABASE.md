# Database

Supabase Postgres (version 15 or newer). Trello cards 1.4 (data models), 1.6
(join by invite code, server side), 1.8 (restrict data to household members),
and the SQL half of 1.9 (tests).

Accounts are real Supabase Auth email + password users. A user must have a
`profiles` row (a display name) before creating or joining a household.

## Applying the migrations

Files in `supabase/migrations/`, applied in name order:

| File | Contents |
|---|---|
| `20261103000001_core.sql` | tables, constraints, indexes |
| `20261103000002_rls.sql` | grants, row-level security, Realtime publication |
| `20261103000003_functions.sql` | the write functions (RPCs) and the points function |

**Dashboard:** Supabase dashboard, SQL Editor, New query. Paste each file in
order and Run. Each file runs as one transaction: if it errors, nothing from that
file is applied.

**CLI:** `supabase link --project-ref <ref>` then `supabase db push`.

Apply each migration once. They are not written to be re-run.

**Then test:** paste `supabase/tests/rls_test.sql` into the SQL Editor and Run.
It always ends with an error on purpose. The error message is the report
(`RLS TEST REPORT: N passed, M failed`), and the error rolls everything back.
The header of that file has four one-line "mutations" that each make a named
check fail, to show the checks can fail.

## Tables

| Table | Holds |
|---|---|
| `profiles` | `display_name` (1 to 40 chars, no leading or trailing spaces) per user |
| `households` | `name` (1 to 60), `invite_code` (12 chars, unique), `created_by` |
| `household_members` | `household_id`, `user_id`, `role` (`owner` or `member`), `joined_at`. At most one owner per household |
| `chores` | `name`, `effort` (1 to 3), `repeat` (`none`, `daily`, `weekly`, `biweekly`, `monthly`), `due_on`, `assignee`, `fixed`, `created_by`, `archived` |
| `chore_rotation` | `chore_id`, `user_id`, `position`: the members eligible for a rotating chore, in order |
| `chore_completions` | `chore_id`, `completed_by`, `credited_to`, `due_on` (the occurrence completed), `effort`, `completed_at`, `undone_at`, plus `prev_assignee` and `archived_chore` which undo uses |
| `grocery_items` | `name`, `quantity` (text, default `1`), `category` (default `Other`), `claimed_by`, `bought_by`, `bought_at`, `added_by` |
| `join_attempts` | failed join attempts, used to slow down code guessing. Clients can't read it |

Rules the database enforces, not only the app:

- The assignee and every rotation member must belong to that household
  (composite foreign keys onto `household_members`).
- A fixed chore always has an assignee (table check).
- One live completion per chore occurrence: unique on `(chore_id, due_on)` where
  `undone_at is null` (card 2.10).
- `bought_by` and `bought_at` are both set or both null.
- History (`completed_by`, `credited_to`, `bought_by`, ...) points at `profiles`,
  not membership, so a roommate who leaves keeps what they did. A user who
  appears in that history can't be deleted from Auth until those rows are dealt
  with, same as the budget app.

## Who can do what

`anon` (not signed in) gets nothing anywhere. Everything below is a signed-in
user (`authenticated`). "Member" means a member of that row's household.

| Table | Select | Insert | Update | Delete |
|---|---|---|---|---|
| `profiles` | yourself, and people in a household with you | own row | own row | nobody |
| `households` | members | functions only | functions only | functions only |
| `household_members` | members | functions only | functions only | functions only |
| `chores` | members | functions only | functions only | functions only |
| `chore_rotation` | members | functions only | functions only | functions only |
| `chore_completions` | members | functions only | functions only | functions only |
| `grocery_items` | members | members, direct. Only `household_id, name, quantity, category, added_by`; `added_by` must be you; starts unclaimed and unbought | members, direct. Only `name, quantity, category` | members |
| `join_attempts` | nobody | `join_household` only | nobody | `join_household` only |

Outsiders and former members see nothing. Clients have no insert, update or
delete permission on any household, member, chore, rotation or completion table.

### Grocery writes: decision

Adding, renaming and deleting items is direct through RLS (a simple list).
`claimed_by`, `bought_by` and `bought_at` are **not** granted to clients at all,
because the rules ("`bought_by` is you", "only the claimer clears a claim") depend
on the old row, which an RLS check cannot see. Those columns change only through
`claim_grocery_item`, `unclaim_grocery_item`, `buy_grocery_item` and
`unbuy_grocery_item`, which take no user argument.

## Functions (RPCs)

Call with `supabase.rpc('name', params: {...})` using the parameter names shown.
Each function finds the caller from their sign-in. None takes a caller id, so
nobody can act as somebody else. Errors come back as plain English the app can
show.

### Household

| Function | Returns | Who | Notes |
|---|---|---|---|
| `create_household(p_name text)` | one row: `household_id uuid, invite_code text` | any signed-in user with a profile | caller becomes the owner |
| `join_household(p_code text)` | `uuid` household id, or **`null` if no household has that code** | any signed-in user with a profile | ignores dashes, spaces and case. Already a member returns the id |
| `leave_household(p_household_id uuid)` | nothing | any member | see "Leaving" below |
| `remove_member(p_household_id uuid, p_user_id uuid)` | nothing | owner only | same cleanup as leaving. The owner can't remove themself |
| `regenerate_invite_code(p_household_id uuid)` | new `text` code | owner only | the old code stops working at once |

### Chores

| Function | Returns | Who | Notes |
|---|---|---|---|
| `create_chore(p_household_id uuid, p_name text, p_effort integer, p_repeat text, p_due_on date = today, p_fixed boolean = false, p_assignee uuid = null, p_rotation uuid[] = '{}')` | chore `uuid` | any member | rotating: `p_rotation` (non-empty, in order, all members); the assignee defaults to its first entry. Fixed: `p_assignee` required, `p_rotation` ignored |
| `update_chore(p_chore_id uuid, p_name text, p_effort integer, p_repeat text, p_due_on date, p_fixed boolean, p_assignee uuid = null, p_rotation uuid[] = '{}')` | nothing | any member | **replaces the whole chore**, rotation included. Archived chores can't be edited |
| `archive_chore(p_chore_id uuid)` | nothing | any member | hides the chore, history stays |
| `complete_chore(p_chore_id uuid, p_expected_due_on date = null)` | next assignee `uuid`, or `null` for a one-time chore | any member | see below |
| `undo_completion(p_completion_id uuid)` | nothing | the person who completed it | within 24 hours, and only the chore's latest live completion |

**`complete_chore` rules**

1. Records a completion for the current `due_on`.
2. **Credit goes to the current assignee, not to whoever tapped the button.**
   Anyone in the household may complete a chore (a roommate covering is fine),
   and the points still go to the person it was assigned to. If the chore has
   no assignee, the person who tapped gets them.
   *Team decision for card 3.6: implemented this way; the credit rule lives in
   one place (`credited_to` in `complete_chore`) if the team changes its mind.*
3. `repeat = 'none'`: the chore is archived, returns `null`.
4. Otherwise `due_on` moves forward by the repeat interval: from the **old**
   `due_on` if it was not overdue, from **today** if it was overdue. Intervals:
   daily 1 day, weekly 7, biweekly 14, monthly **30 days** (the mockup's
   rule; not a calendar month).
5. Unless the chore is `fixed`, the assignee becomes the next person in
   `chore_rotation` order after the current one, wrapping around. People who are
   no longer members are skipped (they are removed from rotations when they
   leave). A fixed chore keeps its assignee.

**Pass `p_expected_due_on`** with the `due_on` the user saw. If the chore has
already been completed by someone else a moment ago, the call fails with "This
chore was already completed or rescheduled" instead of completing the *next*
occurrence by accident. Without it, a double tap completes two occurrences.

**`undo_completion`** marks the completion undone (its points disappear),
restores `due_on` to the completed occurrence and the assignee to who it was
before (null if they have left since), and un-archives a one-time chore.

### Groceries

| Function | Returns | Who | Notes |
|---|---|---|---|
| `claim_grocery_item(p_item_id uuid)` | nothing | any member | claim for yourself. Fails if someone else claimed it or it is bought |
| `unclaim_grocery_item(p_item_id uuid)` | nothing | the claimer | |
| `buy_grocery_item(p_item_id uuid)` | nothing | any member | `bought_by` = the caller. An unclaimed item becomes claimed by the buyer |
| `unbuy_grocery_item(p_item_id uuid)` | nothing | the buyer | the point goes with it |

Add, rename and delete items with plain table writes:
`from('grocery_items').insert({household_id, name, quantity, category})`
(`added_by` defaults to you).

### Points

`household_contributions(p_household_id uuid, p_since timestamptz = null)`
returns `(user_id uuid, points bigint)`, one row per **current** member, zeros
included.

- Chores: the `effort` of each non-undone completion **credited to** the member.
- Groceries: 1 point per item the member bought (`bought_at >= p_since`).
- `p_since = null` is all time. The app passes `now() - interval '7 days'` for
  "this week" and 30 days for "this month".
- Runs as the caller, so row-level security makes it member-only: a non-member
  gets zero rows. Former members are not listed. Deleting a bought item
  deletes its point.

### Leaving and removal

`leave_household` and `remove_member` share one cleanup:

- Chores assigned to that person move on: a rotating chore goes to the next
  person in *its* rotation after them (wrapping), or to nobody if they were the
  only one. A **fixed** chore loses its fixed agreement: it becomes a normal
  chore with no assignee, and the owner picks someone.
- They drop out of every rotation and lose unbought grocery claims.
- Completions and bought items stay (history, points already earned).
- If the **owner** leaves and others remain, ownership passes to whoever
  joined earliest. If the **last** member leaves, the household and all its
  data are deleted.
- A new member is **not** added to existing rotations automatically; use
  `update_chore` to add them.

Readable helpers: `is_household_member(uuid)` and `shares_household_with(uuid)`
return a boolean, and each answers only about the caller.

## Invite codes and guessing

- 12 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, with no `0 O 1 I L`.
  That's 31^12, about 8 x 10^17 codes. Generated on the server with
  `gen_random_bytes`, with no modulo bias. Stored uppercase without dashes. The
  app can show it as `ABCD-EFGH-JKMN`.
- Every member can read the code (to share it). Only the owner can replace it.
- **Guessing friction:** every unknown code is logged in `join_attempts`. After
  **10 wrong codes in 15 minutes**, `join_household` refuses that user, even for
  a correct code, until the window passes (error `Too many wrong codes...`).
  Unknown codes return `null` instead of raising an error. An error would roll
  back the logged attempt, and the counter would never grow.
- Limit: a guesser can make new accounts to reset the counter. Supabase limits
  sign-ups per IP, and with 8 x 10^17 codes guessing isn't practical either way.

## Realtime

Supabase Realtime **doesn't apply RLS to DELETE events.** Every subscriber to a
table gets every delete on it, with the row's primary key.

So only **`chores`**, **`chore_completions`** and **`grocery_items`** are
published. Their primary key is a random uuid, so a delete reveals a meaningless
id and nothing else. INSERT and UPDATE events are filtered by RLS, so members
only see their own households.

Not published, on purpose:

- `chore_rotation`: its key `(chore_id, user_id)` would reveal user ids on delete
- `household_members`: its key `(household_id, user_id)` would reveal who lives where
- `households`, because it holds the invite code
- `profiles` and `join_attempts`

**App pattern:** subscribe to those three tables filtered by
`household_id=eq.<id>`. On any event, refetch the screen's data. Delete events
can't be filtered by `household_id`, so for a DELETE, check whether the id is
one you're showing. `create_chore`, `update_chore`, `complete_chore` and
`undo_completion` always touch the `chores` row, so a rotation change also sends
an event. Members joining or leaving don't send a live event: refetch members
when the household screen opens.

## Things the team may want to change

- Credit rule (card 3.6): points go to the assignee, not the person who tapped.
- Monthly repeat is 30 days, matching the mockup, not a calendar month.
- New members are not auto-added to rotations.
- Undo window is 24 hours (a constant in `undo_completion`).
