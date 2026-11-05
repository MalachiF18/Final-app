-- Grants and row-level security. Trello card 1.8.
--
-- Roles: a signed-in user has the `authenticated` role. `anon` is a client
-- that has not signed in at all; it gets nothing here.
--
-- Supabase's default privileges grant ALL on new public tables and functions
-- to anon and authenticated, so every table starts with "revoke all" and
-- gets back only what it needs.
--
-- Rule of the house: every row belongs to one household and is readable only
-- by its members. Outsiders (including users who left) see nothing.

-- ---------------------------------------------------------------------------
-- Membership helpers.
--
-- SECURITY DEFINER so a policy on household_members can ask "is the caller a
-- member" without re-entering household_members' own policy (infinite
-- recursion). They only answer about the caller, so exposing them as RPCs
-- leaks nothing.
-- ---------------------------------------------------------------------------

create function public.is_household_member(p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.household_members
    where household_id = p_household_id and user_id = auth.uid()
  );
$$;

-- True when the caller and p_user are in at least one household together.
create function public.shares_household_with(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.household_members me
    join public.household_members them on them.household_id = me.household_id
    where me.user_id = auth.uid() and them.user_id = p_user
  );
$$;

revoke all on function public.is_household_member(uuid), public.shares_household_with(uuid)
  from public, anon, authenticated;
-- Policies run with the querying role's privileges, so it needs EXECUTE.
grant execute on function public.is_household_member(uuid), public.shares_household_with(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere. A table with RLS on and no policy is closed.
-- ---------------------------------------------------------------------------

alter table public.profiles           enable row level security;
alter table public.households         enable row level security;
alter table public.household_members  enable row level security;
alter table public.join_attempts      enable row level security;
alter table public.chores             enable row level security;
alter table public.chore_rotation     enable row level security;
alter table public.chore_completions  enable row level security;
alter table public.grocery_items      enable row level security;

revoke all on
  public.profiles, public.households, public.household_members,
  public.join_attempts, public.chores, public.chore_rotation,
  public.chore_completions, public.grocery_items
from public, anon, authenticated;

grant all on
  public.profiles, public.households, public.household_members,
  public.join_attempts, public.chores, public.chore_rotation,
  public.chore_completions, public.grocery_items
to service_role;

-- join_attempts: no grants, no policies. Only join_household() touches it.

-- ---------------------------------------------------------------------------
-- profiles: read your own and those of people you share a household with
-- (display names on member cards); write only your own.
-- ---------------------------------------------------------------------------

grant select, insert, update on public.profiles to authenticated;

create policy "profiles: read self and housemates" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.shares_household_with(id));

create policy "profiles: create own" on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No delete policy: a profile goes away only with its auth user.

-- ---------------------------------------------------------------------------
-- Household, members, chores, rotation, completions: members read; nobody
-- writes directly (no insert/update/delete grant). Writes go through the
-- SECURITY DEFINER functions in 0003.
-- ---------------------------------------------------------------------------

grant select on
  public.households, public.household_members, public.chores,
  public.chore_rotation, public.chore_completions
to authenticated;

create policy "households: members read" on public.households
  for select to authenticated
  using (public.is_household_member(id));

create policy "household_members: members read" on public.household_members
  for select to authenticated
  using (public.is_household_member(household_id));

create policy "chores: members read" on public.chores
  for select to authenticated
  using (public.is_household_member(household_id));

create policy "chore_rotation: members read" on public.chore_rotation
  for select to authenticated
  using (public.is_household_member(household_id));

create policy "chore_completions: members read" on public.chore_completions
  for select to authenticated
  using (public.is_household_member(household_id));

-- ---------------------------------------------------------------------------
-- grocery_items: the simple list is written directly through RLS, but only
-- the harmless columns. DECISION: claim and buy are state changes with rules
-- ("bought_by is you", "only the claimer clears a claim"), and a policy
-- WITH CHECK cannot see the OLD row, so those four columns are NOT granted
-- to clients. They change only through the functions in 0003.
--
--   insert  household_id, name, quantity, category, added_by
--           (policy: caller is a member, added_by is the caller, and the new
--           item starts unclaimed and unbought)
--   update  name, quantity, category (any member)
--   delete  any member
--   claimed_by, bought_by, bought_at: functions only
-- ---------------------------------------------------------------------------

grant select, delete on public.grocery_items to authenticated;
grant insert (household_id, name, quantity, category, added_by)
  on public.grocery_items to authenticated;
grant update (name, quantity, category) on public.grocery_items to authenticated;

create policy "grocery_items: members read" on public.grocery_items
  for select to authenticated
  using (public.is_household_member(household_id));

create policy "grocery_items: members add" on public.grocery_items
  for insert to authenticated
  with check (public.is_household_member(household_id)
              and added_by = (select auth.uid())
              and claimed_by is null
              and bought_by is null
              and bought_at is null);

create policy "grocery_items: members edit" on public.grocery_items
  for update to authenticated
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

create policy "grocery_items: members delete" on public.grocery_items
  for delete to authenticated
  using (public.is_household_member(household_id));

-- ---------------------------------------------------------------------------
-- Realtime.
--
-- Supabase Realtime does not apply RLS to DELETE events: every subscriber to
-- a table receives every delete on it. With RLS on and the default replica
-- identity, a delete payload carries only the primary key.
--
-- So publish only tables whose primary key is a bare random uuid:
--   chores (id), chore_completions (id), grocery_items (id).
-- INSERT/UPDATE events on them are RLS-filtered (members only). A delete
-- leaks one meaningless uuid to other subscribers, nothing else.
--
-- NOT published, on purpose:
--   chore_rotation     PK (chore_id, user_id) would leak user ids on delete
--   household_members  PK (household_id, user_id) would leak who lives where
--   households         carries invite_code
--   profiles, join_attempts
-- create_chore / update_chore / complete_chore / undo_completion always touch
-- the chores row, so a rotation change still produces a chores event; the
-- client refetches on any event.
--
-- If a table is ever added here, check its primary key first: that is
-- exactly what every subscriber will see when one of its rows is deleted.
-- ---------------------------------------------------------------------------

alter publication supabase_realtime
  add table public.chores, public.chore_completions, public.grocery_items;
