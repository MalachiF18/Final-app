-- Core schema: tables, constraints, indexes. Trello card 1.4.
--
-- Daily Improvement Household: households of roommates sharing chores and a
-- grocery list. Pattern follows the budget-app database (same team).
--
-- No begin/commit here: `supabase db push` wraps each migration in its own
-- transaction, and the dashboard SQL editor runs a pasted script as one
-- implicit transaction.
--
-- Needs Postgres 15 or newer (Supabase's default): chores.assignee uses
-- ON DELETE SET NULL (column list), added in 15.

-- gen_random_bytes() for invite codes. Supabase installs pgcrypto in the
-- `extensions` schema; this is a no-op when it is already there.
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Users (real email + password accounts in Supabase Auth)
-- ---------------------------------------------------------------------------

-- One row per signed-in user. The app creates it once, when the user picks a
-- display name.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null
    check (char_length(display_name) between 1 and 40
           and display_name = btrim(display_name)),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Households (read-only to clients; every write goes through 0003 functions)
-- ---------------------------------------------------------------------------

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60 and name = btrim(name)),
  -- 12 characters, uppercase, no dashes, no look-alikes (0 O 1 I L).
  -- Generated server-side by public.generate_invite_code().
  invite_code text not null unique check (invite_code ~ '^[A-HJKMNP-Z2-9]{12}$'),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);
-- "Which households am I in" (the PK only serves lookups by household first).
create index household_members_user_id_idx on public.household_members (user_id);
-- At most one owner per household, as a database fact. leave_household()
-- deletes the old owner's row before promoting the successor, so the two
-- never overlap.
create unique index household_members_one_owner_idx
  on public.household_members (household_id) where role = 'owner';

-- Failed join attempts, for brute-force friction in public.join_household().
-- Never readable by clients.
create table public.join_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index join_attempts_user_time_idx on public.join_attempts (user_id, attempted_at);

-- ---------------------------------------------------------------------------
-- Chores
--
-- Composite foreign keys onto household_members make "the assignee and every
-- rotation member belong to this household" a database fact, not only an RPC
-- check. created_by points at profiles only, so a creator can leave the
-- household without blocking on their old chores.
-- ---------------------------------------------------------------------------

create table public.chores (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60 and name = btrim(name)),
  -- Points credited when the chore is completed.
  effort integer not null check (effort between 1 and 3),
  repeat text not null default 'none'
    check (repeat in ('none', 'daily', 'weekly', 'biweekly', 'monthly')),
  -- The occurrence that is currently open. complete_chore() moves it forward.
  due_on date not null default current_date,
  -- Who is up now. Null only when nobody eligible is left (e.g. everybody in
  -- the rotation left); then whoever completes it gets the credit.
  assignee uuid,
  -- true = agreed fixed assignment: complete_chore() never rotates it.
  fixed boolean not null default false,
  created_by uuid not null references public.profiles (id),
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  -- Target of the composite FKs from chore_rotation and chore_completions, so
  -- those rows can never carry a household_id that disagrees with the chore.
  unique (id, household_id),
  -- Column-list SET NULL (Postgres 15+): if the member row ever disappears
  -- without going through household_detach_member(), only assignee is nulled,
  -- not household_id (which is NOT NULL).
  foreign key (household_id, assignee)
    references public.household_members (household_id, user_id)
    on delete set null (assignee),
  -- A fixed chore always has a person. household_detach_member() clears
  -- `fixed` together with the assignee when a fixed assignee leaves.
  check (not fixed or assignee is not null)
);
create index chores_household_idx on public.chores (household_id, archived, due_on);

-- Eligible members for a rotating chore, in rotation order.
create table public.chore_rotation (
  chore_id uuid not null,
  household_id uuid not null,
  user_id uuid not null,
  position integer not null check (position >= 1),
  primary key (chore_id, user_id),
  unique (chore_id, position),
  foreign key (chore_id, household_id)
    references public.chores (id, household_id) on delete cascade,
  -- A member who leaves drops out of every rotation automatically.
  foreign key (household_id, user_id)
    references public.household_members (household_id, user_id) on delete cascade
);
create index chore_rotation_member_idx on public.chore_rotation (household_id, user_id);

-- History of completed occurrences. Points are computed from this table.
-- completed_by and credited_to point at profiles only: history must outlive
-- membership (a roommate who left keeps what they did).
create table public.chore_completions (
  id uuid primary key default gen_random_uuid(),
  chore_id uuid not null,
  household_id uuid not null,
  -- Whoever tapped "done". May be a member covering for the assignee.
  completed_by uuid not null references public.profiles (id),
  -- The assignee at completion time; gets the points. (Falls back to
  -- completed_by when the chore had no assignee.)
  credited_to uuid not null references public.profiles (id),
  -- The occurrence that was completed (the chore's due_on at that moment).
  due_on date not null,
  -- Effort copied at completion time, so later edits do not rewrite history.
  effort integer not null check (effort between 1 and 3),
  completed_at timestamptz not null default now(),
  undone_at timestamptz,
  -- State undo_completion() puts back: the assignee before the completion,
  -- and whether the completion archived the chore (repeat = 'none').
  prev_assignee uuid,
  archived_chore boolean not null default false,
  foreign key (chore_id, household_id)
    references public.chores (id, household_id) on delete cascade
);

-- Card 2.10: one live completion per occurrence. The partial index is the
-- guarantee; complete_chore() also checks first to give a friendly message.
-- Undone completions drop out of the index, so an undone occurrence can be
-- completed again.
create unique index chore_completions_one_per_occurrence
  on public.chore_completions (chore_id, due_on) where undone_at is null;
create index chore_completions_household_time_idx
  on public.chore_completions (household_id, completed_at);
create index chore_completions_credited_idx on public.chore_completions (credited_to);

-- ---------------------------------------------------------------------------
-- Groceries
--
-- claimed_by / bought_by / added_by point at profiles only, so history
-- survives membership changes. Who may change which column is enforced by
-- column grants and policies in 0002 plus the grocery functions in 0003.
-- ---------------------------------------------------------------------------

create table public.grocery_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60 and name = btrim(name)),
  quantity text not null default '1'
    check (char_length(quantity) between 1 and 16 and quantity = btrim(quantity)),
  category text not null default 'Other'
    check (char_length(category) between 1 and 30 and category = btrim(category)),
  -- "I will buy this." Set to the claimer only; cleared by the claimer only.
  claimed_by uuid references public.profiles (id),
  -- Set to the buyer only (the function uses auth.uid()). Earns 1 point.
  bought_by uuid references public.profiles (id),
  bought_at timestamptz,
  added_by uuid not null default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now(),
  check ((bought_by is null) = (bought_at is null))
);
create index grocery_items_household_idx on public.grocery_items (household_id, bought_at);
