-- Household write API. Trello cards 1.4 / 1.6 (join by code, server side).
--
-- Clients have no insert/update/delete grant on household, member, chore,
-- rotation or completion tables (0002), and only limited column grants on
-- grocery_items. Every other write is one of the SECURITY DEFINER functions
-- below. Each one:
--   * sets search_path = '' and schema-qualifies everything, so a caller
--     cannot redirect a name to an object of their own;
--   * reads the caller only from auth.uid(), never from an argument;
--   * re-checks membership / ownership itself, because SECURITY DEFINER
--     bypasses RLS.
--
-- Errors are raised with plain-English messages the app can show as-is.
-- Errors for "this id is not yours / does not exist" share one message, so
-- outsiders learn nothing about which ids exist.

-- ---------------------------------------------------------------------------
-- Internal helpers (EXECUTE revoked from clients at the bottom)
-- ---------------------------------------------------------------------------

-- 12 characters from a 31-character alphabet with no look-alikes
-- (no 0 O 1 I L): 31^12 is about 7.9e17 codes (~59 bits).
--
-- Uses pgcrypto's gen_random_bytes (a CSPRNG), not random(), which is
-- predictable. Rejection sampling: only bytes below 248 (= 31 * 8) are used,
-- so `byte % 31` hits every character equally often (no modulo bias).
create function public.generate_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text := '';
  v_bytes bytea;
  v_byte integer;
  i integer;
begin
  while char_length(v_code) < 12 loop
    v_bytes := extensions.gen_random_bytes(16);
    for i in 0 .. 15 loop
      v_byte := get_byte(v_bytes, i);
      if v_byte < 248 and char_length(v_code) < 12 then
        v_code := v_code || substr(v_alphabet, (v_byte % 31) + 1, 1);
      end if;
    end loop;
  end loop;
  return v_code;
end;
$$;

-- Validates who a chore is for and returns the resolved assignee.
--   fixed chore:    p_assignee is required and must be a member; the
--                   rotation list is ignored.
--   rotating chore: p_rotation (in order) must be non-empty, free of
--                   duplicates and nulls, every entry a member. p_assignee
--                   defaults to the first entry and must be in the list.
-- Raises on any problem.
create function public.chore_validate_assignment(
  p_household_id uuid,
  p_fixed boolean,
  p_assignee uuid,
  p_rotation uuid[]
)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_rot uuid[] := coalesce(p_rotation, '{}'::uuid[]);
begin
  if p_fixed is null then
    raise exception 'Say whether this chore has a fixed assignee';
  end if;

  if p_fixed then
    if p_assignee is null then
      raise exception 'A fixed chore needs an assignee';
    end if;
    if not exists (select 1 from public.household_members m
                   where m.household_id = p_household_id and m.user_id = p_assignee) then
      raise exception 'The assignee must be a member of the household';
    end if;
    return p_assignee;
  end if;

  if cardinality(v_rot) = 0 then
    raise exception 'Pick at least one roommate to rotate among';
  end if;
  if exists (select 1 from unnest(v_rot) u(x) where u.x is null) then
    raise exception 'Rotation list contains an empty entry';
  end if;
  if (select count(distinct u.x) from unnest(v_rot) u(x)) <> cardinality(v_rot) then
    raise exception 'Each person can appear only once in the rotation';
  end if;
  if exists (
    select 1 from unnest(v_rot) u(x)
    where not exists (select 1 from public.household_members m
                      where m.household_id = p_household_id and m.user_id = u.x)
  ) then
    raise exception 'Everyone in the rotation must be a member of the household';
  end if;

  if p_assignee is null then
    return v_rot[1];
  end if;
  if not (p_assignee = any (v_rot)) then
    raise exception 'The current assignee must be one of the people in the rotation';
  end if;
  return p_assignee;
end;
$$;

-- Replaces a chore's rotation with p_rotation, positions 1..n in array order.
-- A fixed chore passes an empty array and ends up with no rotation rows.
create function public.chore_write_rotation(
  p_chore_id uuid,
  p_household_id uuid,
  p_rotation uuid[]
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  delete from public.chore_rotation where chore_id = p_chore_id;
  insert into public.chore_rotation (chore_id, household_id, user_id, position)
    select p_chore_id, p_household_id, u.x, u.ord::integer
    from unnest(coalesce(p_rotation, '{}'::uuid[])) with ordinality as u(x, ord);
end;
$$;

-- Removes one member's row and everything that would otherwise dangle.
-- Shared by leave_household() and remove_member(). Does NOT handle owner
-- succession; the callers do.
--
-- For every chore the member is assigned to (archived ones too):
--   rotating chore -> the next person in that chore's rotation after them
--                     (wrapping around), or null if nobody else is in it;
--   fixed chore    -> becomes non-fixed with no assignee (the fixed
--                     agreement ended with the person; the owner picks anew).
-- The member drops out of every rotation, loses unbought claims on groceries,
-- and their membership row is deleted. Completions, bought items and other
-- history stay (they point at profiles, not membership).
create function public.household_detach_member(p_household_id uuid, p_user_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  r record;
  v_pos integer;
  v_next uuid;
begin
  for r in
    select c.id, c.fixed from public.chores c
    where c.household_id = p_household_id and c.assignee = p_user_id
  loop
    if r.fixed then
      update public.chores set fixed = false, assignee = null where id = r.id;
    else
      select cr.position into v_pos from public.chore_rotation cr
        where cr.chore_id = r.id and cr.user_id = p_user_id;
      -- Rows after the leaver's position sort first, then wrap to the start.
      select cr.user_id into v_next from public.chore_rotation cr
        where cr.chore_id = r.id and cr.user_id <> p_user_id
        order by (cr.position > coalesce(v_pos, 0)) desc, cr.position
        limit 1;
      update public.chores set assignee = v_next where id = r.id;
    end if;
  end loop;

  delete from public.chore_rotation
    where household_id = p_household_id and user_id = p_user_id;

  update public.grocery_items set claimed_by = null
    where household_id = p_household_id and claimed_by = p_user_id and bought_by is null;

  delete from public.household_members
    where household_id = p_household_id and user_id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_household(name) -> (household_id, invite_code). Caller becomes owner.
-- ---------------------------------------------------------------------------

create function public.create_household(p_name text)
returns table (household_id uuid, invite_code text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_code text;
  v_hh uuid;
  v_try integer;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user) then
    raise exception 'Set your display name first';
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'Household name must be 1 to 60 characters';
  end if;

  -- A collision at ~59 bits is practically impossible, but must never put
  -- two households behind one code; retry with a fresh code.
  for v_try in 1 .. 5 loop
    v_code := public.generate_invite_code();
    begin
      insert into public.households (name, invite_code, created_by)
        values (v_name, v_code, v_user)
        returning id into v_hh;
      insert into public.household_members (household_id, user_id, role)
        values (v_hh, v_user, 'owner');
      household_id := v_hh;
      invite_code := v_code;
      return next;
      return;
    exception when unique_violation then
      null;
    end;
  end loop;
  raise exception 'Could not create the household. Please try again';
end;
$$;

-- ---------------------------------------------------------------------------
-- join_household(code) -> household id, or NULL when no household has that code.
--
-- Input is normalised: dashes and whitespace removed, uppercased, so
-- "abcd-efgh-jkmn" works.
--
-- Brute-force friction: each failed attempt is stored in join_attempts. A
-- caller with 10 failures in the last 15 minutes is refused (exception)
-- before the code is even looked up. Unknown codes RETURN NULL instead of
-- raising, because raising would roll back the attempt row and the counter
-- would never grow. Joining a household you are already in returns its id
-- and does not count as a failure.
-- ---------------------------------------------------------------------------

create function public.join_household(p_code text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g'));
  v_hh uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user) then
    raise exception 'Set your display name first';
  end if;

  -- Keep the table small: this user's attempts older than the window are useless.
  delete from public.join_attempts
    where user_id = v_user and attempted_at < now() - interval '15 minutes';

  if (select count(*) from public.join_attempts where user_id = v_user) >= 10 then
    raise exception 'Too many wrong codes. Wait 15 minutes and try again'
      using errcode = '54000';
  end if;

  select h.id into v_hh from public.households h where h.invite_code = v_code;
  if v_hh is null then
    insert into public.join_attempts (user_id) values (v_user);
    return null;
  end if;

  insert into public.household_members (household_id, user_id)
    values (v_hh, v_user)
    on conflict (household_id, user_id) do nothing;
  return v_hh;
end;
$$;

-- ---------------------------------------------------------------------------
-- leave_household(household_id) -> void
--
-- Any member may leave. If the owner leaves and others remain, ownership
-- passes to the member who joined earliest (ties broken by user id). If the
-- last member leaves, the household and all its data are deleted: nobody
-- could ever open it again. Chores assigned to the leaver are reassigned
-- (see household_detach_member).
-- ---------------------------------------------------------------------------

create function public.leave_household(p_household_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_successor uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  -- Serialise concurrent leaves/removals in one household, so two owners
  -- (or two last members) cannot both conclude someone else remains.
  perform 1 from public.households h where h.id = p_household_id for update;

  select m.role into v_role from public.household_members m
    where m.household_id = p_household_id and m.user_id = v_user;
  if not found then
    raise exception 'You are not a member of this household' using errcode = '42501';
  end if;

  if v_role = 'owner' then
    select m.user_id into v_successor from public.household_members m
      where m.household_id = p_household_id and m.user_id <> v_user
      order by m.joined_at, m.user_id
      limit 1;
    if v_successor is null then
      -- Delete the chores first (rotation and completions cascade from them).
      -- Otherwise the cascade from the member rows could try to null a fixed
      -- chore's assignee, which its table check forbids.
      delete from public.chores where household_id = p_household_id;
      delete from public.households where id = p_household_id;
      return;
    end if;
  end if;

  perform public.household_detach_member(p_household_id, v_user);
  -- The old owner's row is gone, so the one-owner index allows this.
  if v_successor is not null then
    update public.household_members set role = 'owner'
      where household_id = p_household_id and user_id = v_successor;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- remove_member(household_id, user_id) -> void. Owner only; same cleanup as
-- leaving. The owner cannot remove themself (use leave_household, which
-- handles succession).
-- ---------------------------------------------------------------------------

create function public.remove_member(p_household_id uuid, p_user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  perform 1 from public.households h where h.id = p_household_id for update;

  if not exists (select 1 from public.household_members m
                 where m.household_id = p_household_id
                   and m.user_id = v_user and m.role = 'owner') then
    raise exception 'Only the household owner can remove members' using errcode = '42501';
  end if;
  if p_user_id is null or p_user_id = v_user then
    raise exception 'Use leave household to remove yourself';
  end if;
  if not exists (select 1 from public.household_members m
                 where m.household_id = p_household_id and m.user_id = p_user_id) then
    raise exception 'That person is not a member of this household';
  end if;

  perform public.household_detach_member(p_household_id, p_user_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- regenerate_invite_code(household_id) -> the new code. Owner only.
-- The old code stops working immediately.
-- ---------------------------------------------------------------------------

create function public.regenerate_invite_code(p_household_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_code text;
  v_try integer;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not exists (select 1 from public.household_members m
                 where m.household_id = p_household_id
                   and m.user_id = v_user and m.role = 'owner') then
    raise exception 'Only the household owner can change the invite code'
      using errcode = '42501';
  end if;

  for v_try in 1 .. 5 loop
    v_code := public.generate_invite_code();
    begin
      update public.households set invite_code = v_code where id = p_household_id;
      return v_code;
    exception when unique_violation then
      null;
    end;
  end loop;
  raise exception 'Could not create a new code. Please try again';
end;
$$;

-- ---------------------------------------------------------------------------
-- create_chore(...) -> chore id. Any member.
--
-- p_effort 1..3 (points). p_repeat none|daily|weekly|biweekly|monthly.
-- p_due_on defaults to today.
-- Rotating chore (p_fixed false): p_rotation is the eligible members in
--   order; p_assignee defaults to the first of them.
-- Fixed chore (p_fixed true): p_assignee required; p_rotation ignored.
-- ---------------------------------------------------------------------------

create function public.create_chore(
  p_household_id uuid,
  p_name text,
  p_effort integer,
  p_repeat text,
  p_due_on date default null,
  p_fixed boolean default false,
  p_assignee uuid default null,
  p_rotation uuid[] default '{}'
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_assignee uuid;
  v_chore uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not public.is_household_member(p_household_id) then
    raise exception 'You are not a member of this household' using errcode = '42501';
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'Chore name must be 1 to 60 characters';
  end if;
  if p_effort is null or p_effort not between 1 and 3 then
    raise exception 'Effort must be 1, 2 or 3';
  end if;
  if p_repeat is null or p_repeat not in ('none', 'daily', 'weekly', 'biweekly', 'monthly') then
    raise exception 'Repeat must be none, daily, weekly, biweekly or monthly';
  end if;
  v_assignee := public.chore_validate_assignment(p_household_id, p_fixed, p_assignee, p_rotation);

  insert into public.chores
    (household_id, name, effort, repeat, due_on, assignee, fixed, created_by)
  values
    (p_household_id, v_name, p_effort, p_repeat, coalesce(p_due_on, current_date),
     v_assignee, p_fixed, v_user)
  returning id into v_chore;

  perform public.chore_write_rotation(v_chore, p_household_id,
    case when p_fixed then '{}'::uuid[] else p_rotation end);
  return v_chore;
end;
$$;

-- ---------------------------------------------------------------------------
-- update_chore(...) -> void. Any member. Full replacement: the app sends the
-- whole edited chore. Editing does not touch past completions (they keep the
-- effort they were completed with). Archived chores cannot be edited.
-- ---------------------------------------------------------------------------

create function public.update_chore(
  p_chore_id uuid,
  p_name text,
  p_effort integer,
  p_repeat text,
  p_due_on date,
  p_fixed boolean,
  p_assignee uuid default null,
  p_rotation uuid[] default '{}'
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_chore public.chores%rowtype;
  v_assignee uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  select * into v_chore from public.chores c where c.id = p_chore_id for update;
  if not found or not public.is_household_member(v_chore.household_id) then
    raise exception 'Chore not found' using errcode = '42501';
  end if;
  if v_chore.archived then
    raise exception 'This chore is archived';
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'Chore name must be 1 to 60 characters';
  end if;
  if p_effort is null or p_effort not between 1 and 3 then
    raise exception 'Effort must be 1, 2 or 3';
  end if;
  if p_repeat is null or p_repeat not in ('none', 'daily', 'weekly', 'biweekly', 'monthly') then
    raise exception 'Repeat must be none, daily, weekly, biweekly or monthly';
  end if;
  if p_due_on is null then
    raise exception 'Due date is required';
  end if;
  v_assignee := public.chore_validate_assignment(v_chore.household_id, p_fixed, p_assignee, p_rotation);

  update public.chores
     set name = v_name, effort = p_effort, repeat = p_repeat, due_on = p_due_on,
         assignee = v_assignee, fixed = p_fixed
   where id = p_chore_id;

  perform public.chore_write_rotation(p_chore_id, v_chore.household_id,
    case when p_fixed then '{}'::uuid[] else p_rotation end);
end;
$$;

-- archive_chore(id) -> void. Any member. Hides the chore; history stays.
create function public.archive_chore(p_chore_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_household uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  select c.household_id into v_household from public.chores c
    where c.id = p_chore_id for update;
  if not found or not public.is_household_member(v_household) then
    raise exception 'Chore not found' using errcode = '42501';
  end if;
  update public.chores set archived = true where id = p_chore_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- complete_chore(chore_id, expected_due_on) -> the next assignee (null when
-- the chore was one-time and is now archived).
--
-- TEAM DECISION for card 3.6 (credit rules), made here so the rest can build
-- on it: ANY member may mark a chore done (a roommate covering is fine), but
-- the points go to the chore's CURRENT ASSIGNEE, not to the person who tapped
-- the button. If the chore has no assignee, the person who tapped gets them.
-- Change this one place (credited_to below) if the team decides otherwise.
--
-- What it does, in one transaction with the chore row locked:
--   1. records a completion for the current due_on, credited to the assignee;
--   2. one-time chore (repeat none): archives it, returns null;
--   3. otherwise advances due_on by the repeat interval, counted from the
--      OLD due_on when not overdue, from TODAY when overdue (so a late chore
--      does not stay overdue forever). Intervals: daily 1, weekly 7,
--      biweekly 14, monthly 30 days (matches the mockup);
--   4. unless the chore is fixed, hands it to the next member in rotation
--      order after the current assignee, wrapping around, skipping anyone no
--      longer in the household.
--
-- p_expected_due_on (card 2.10, double taps): pass the due_on the user saw.
-- If the chore has already moved on (someone else completed it a moment
-- ago), this raises instead of silently completing the NEXT occurrence. The
-- unique index on (chore_id, due_on) is the backstop for any other writer.
-- ---------------------------------------------------------------------------

create function public.complete_chore(p_chore_id uuid, p_expected_due_on date default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_chore public.chores%rowtype;
  v_days integer;
  v_pos integer;
  v_next uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  select * into v_chore from public.chores c where c.id = p_chore_id for update;
  if not found or not public.is_household_member(v_chore.household_id) then
    raise exception 'Chore not found' using errcode = '42501';
  end if;
  if v_chore.archived then
    raise exception 'This chore is archived';
  end if;
  if p_expected_due_on is not null and p_expected_due_on <> v_chore.due_on then
    raise exception 'This chore was already completed or rescheduled. Refresh and try again';
  end if;

  begin
    insert into public.chore_completions
      (chore_id, household_id, completed_by, credited_to, due_on, effort,
       prev_assignee, archived_chore)
    values
      (v_chore.id, v_chore.household_id, v_user, coalesce(v_chore.assignee, v_user),
       v_chore.due_on, v_chore.effort, v_chore.assignee, v_chore.repeat = 'none');
  exception when unique_violation then
    raise exception 'This occurrence was already completed';
  end;

  if v_chore.repeat = 'none' then
    update public.chores set archived = true where id = v_chore.id;
    return null;
  end if;

  v_days := case v_chore.repeat
              when 'daily' then 1 when 'weekly' then 7 when 'biweekly' then 14 else 30 end;

  if v_chore.fixed then
    v_next := v_chore.assignee;
  else
    select cr.position into v_pos from public.chore_rotation cr
      where cr.chore_id = v_chore.id and cr.user_id = v_chore.assignee;
    -- Entries after the current position sort first, then wrap to the start.
    -- The join drops anyone who is no longer a member (defensive: rotation
    -- rows are deleted when a member leaves).
    select cr.user_id into v_next
      from public.chore_rotation cr
      join public.household_members m
        on m.household_id = cr.household_id and m.user_id = cr.user_id
      where cr.chore_id = v_chore.id
      order by (cr.position > coalesce(v_pos, 0)) desc, cr.position
      limit 1;
  end if;

  update public.chores
     set due_on = greatest(v_chore.due_on, current_date) + v_days,
         assignee = v_next
   where id = v_chore.id;
  return v_next;
end;
$$;

-- ---------------------------------------------------------------------------
-- undo_completion(completion_id) -> void
--
-- Only the person who completed it, within 24 hours, and only while it is the
-- chore's latest live completion. Marks it undone (points disappear) and puts
-- the chore back: due_on is the completed occurrence again, the assignee is
-- who it was before (null if they have left since), and a one-time chore is
-- un-archived.
-- ---------------------------------------------------------------------------

create function public.undo_completion(p_completion_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_chore_id uuid;
  v_comp public.chore_completions%rowtype;
  v_assignee uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  -- Lock the chore first (same order as complete_chore), then the completion.
  select c.chore_id into v_chore_id from public.chore_completions c where c.id = p_completion_id;
  if found then
    perform 1 from public.chores ch where ch.id = v_chore_id for update;
  end if;
  select * into v_comp from public.chore_completions c where c.id = p_completion_id for update;

  if not found or v_comp.completed_by <> v_user
     or not public.is_household_member(v_comp.household_id) then
    raise exception 'Only the person who completed this chore can undo it'
      using errcode = '42501';
  end if;
  if v_comp.undone_at is not null then
    raise exception 'This completion was already undone';
  end if;
  if v_comp.completed_at < now() - interval '24 hours' then
    raise exception 'Completions can only be undone within 24 hours';
  end if;
  if exists (select 1 from public.chore_completions x
             where x.chore_id = v_comp.chore_id and x.undone_at is null
               and x.id <> v_comp.id
               and (x.completed_at > v_comp.completed_at or x.due_on > v_comp.due_on)) then
    raise exception 'A newer completion exists for this chore. Undo that one first';
  end if;

  update public.chore_completions set undone_at = now() where id = v_comp.id;

  -- Previous assignee, unless they have left the household since.
  select m.user_id into v_assignee from public.household_members m
    where m.household_id = v_comp.household_id and m.user_id = v_comp.prev_assignee;

  update public.chores
     set due_on = v_comp.due_on,
         assignee = v_assignee,
         -- A fixed chore with nobody to hold it stops being fixed (table check).
         fixed = fixed and v_assignee is not null,
         archived = case when v_comp.archived_chore then false else archived end
   where id = v_comp.chore_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Groceries. Adding, renaming and deleting items is direct (RLS, 0002).
-- Claiming and buying go through these four, so the rules cannot be bent:
--   claimed_by is only ever set to the caller, and only the claimer clears it;
--   bought_by is always the caller. There is no argument to name someone else.
-- ---------------------------------------------------------------------------

-- claim_grocery_item(id): "I will buy this". Fails if someone else claimed it.
create function public.claim_grocery_item(p_item_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_item public.grocery_items%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  select * into v_item from public.grocery_items g where g.id = p_item_id for update;
  if not found or not public.is_household_member(v_item.household_id) then
    raise exception 'Item not found' using errcode = '42501';
  end if;
  if v_item.bought_by is not null then
    raise exception 'This item was already bought';
  end if;
  if v_item.claimed_by is not null and v_item.claimed_by <> v_user then
    raise exception 'Someone else already claimed this item';
  end if;
  update public.grocery_items set claimed_by = v_user where id = p_item_id;
end;
$$;

-- unclaim_grocery_item(id): only the claimer can clear a claim.
create function public.unclaim_grocery_item(p_item_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_item public.grocery_items%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  select * into v_item from public.grocery_items g where g.id = p_item_id for update;
  if not found or not public.is_household_member(v_item.household_id) then
    raise exception 'Item not found' using errcode = '42501';
  end if;
  if v_item.claimed_by is distinct from v_user then
    raise exception 'Only the person who claimed this item can clear the claim'
      using errcode = '42501';
  end if;
  if v_item.bought_by is not null then
    raise exception 'This item was already bought';
  end if;
  update public.grocery_items set claimed_by = null where id = p_item_id;
end;
$$;

-- buy_grocery_item(id): marks it bought BY THE CALLER (1 point). Any member
-- may buy an item someone else claimed; the buyer gets the point. An
-- unclaimed item becomes claimed by the buyer.
create function public.buy_grocery_item(p_item_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_item public.grocery_items%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  select * into v_item from public.grocery_items g where g.id = p_item_id for update;
  if not found or not public.is_household_member(v_item.household_id) then
    raise exception 'Item not found' using errcode = '42501';
  end if;
  if v_item.bought_by is not null then
    raise exception 'This item was already bought';
  end if;
  update public.grocery_items
     set bought_by = v_user, bought_at = now(), claimed_by = coalesce(claimed_by, v_user)
   where id = p_item_id;
end;
$$;

-- unbuy_grocery_item(id): only the buyer can take it back (the point goes
-- with it). The claim stays.
create function public.unbuy_grocery_item(p_item_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_item public.grocery_items%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  select * into v_item from public.grocery_items g where g.id = p_item_id for update;
  if not found or not public.is_household_member(v_item.household_id) then
    raise exception 'Item not found' using errcode = '42501';
  end if;
  if v_item.bought_by is distinct from v_user then
    raise exception 'Only the person who bought this item can undo it'
      using errcode = '42501';
  end if;
  update public.grocery_items set bought_by = null, bought_at = null where id = p_item_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- household_contributions(household_id, since) -> (user_id, points)
--
-- One row per CURRENT member (zero points included, so the Fairness screen
-- can draw every bar). Points since p_since (null = all time):
--   chores:    effort of every non-undone completion credited to the member;
--   groceries: 1 per item the member bought (bought_by, bought_at >= since).
-- Deleting a bought item deletes its point; unbuying removes it too.
--
-- SECURITY INVOKER on purpose: it runs as the caller, so RLS does the
-- member-only check. A non-member sees no household_members rows and gets an
-- empty result. Former members are not listed.
-- The app passes now() - interval '7 days' for "this week", 30 days for
-- "this month" (the mockup's periods).
-- ---------------------------------------------------------------------------

create function public.household_contributions(p_household_id uuid, p_since timestamptz default null)
returns table (user_id uuid, points bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select m.user_id,
         (coalesce(c.pts, 0) + coalesce(g.pts, 0))::bigint as points
  from public.household_members m
  left join (
    select cc.credited_to as uid, sum(cc.effort) as pts
    from public.chore_completions cc
    where cc.household_id = p_household_id
      and cc.undone_at is null
      and cc.completed_at >= coalesce(p_since, '-infinity'::timestamptz)
    group by cc.credited_to
  ) c on c.uid = m.user_id
  left join (
    select gi.bought_by as uid, count(*) as pts
    from public.grocery_items gi
    where gi.household_id = p_household_id
      and gi.bought_by is not null
      and gi.bought_at >= coalesce(p_since, '-infinity'::timestamptz)
    group by gi.bought_by
  ) g on g.uid = m.user_id
  where m.household_id = p_household_id
  order by points desc, m.user_id;
$$;

-- ---------------------------------------------------------------------------
-- Privileges. Postgres grants EXECUTE to PUBLIC by default and Supabase's
-- default privileges add anon and authenticated, so revoke all three and
-- grant back only the API.
-- ---------------------------------------------------------------------------

revoke all on function
  public.generate_invite_code(),
  public.chore_validate_assignment(uuid, boolean, uuid, uuid[]),
  public.chore_write_rotation(uuid, uuid, uuid[]),
  public.household_detach_member(uuid, uuid),
  public.create_household(text),
  public.join_household(text),
  public.leave_household(uuid),
  public.remove_member(uuid, uuid),
  public.regenerate_invite_code(uuid),
  public.create_chore(uuid, text, integer, text, date, boolean, uuid, uuid[]),
  public.update_chore(uuid, text, integer, text, date, boolean, uuid, uuid[]),
  public.archive_chore(uuid),
  public.complete_chore(uuid, date),
  public.undo_completion(uuid),
  public.claim_grocery_item(uuid),
  public.unclaim_grocery_item(uuid),
  public.buy_grocery_item(uuid),
  public.unbuy_grocery_item(uuid),
  public.household_contributions(uuid, timestamptz)
from public, anon, authenticated;

grant execute on function
  public.create_household(text),
  public.join_household(text),
  public.leave_household(uuid),
  public.remove_member(uuid, uuid),
  public.regenerate_invite_code(uuid),
  public.create_chore(uuid, text, integer, text, date, boolean, uuid, uuid[]),
  public.update_chore(uuid, text, integer, text, date, boolean, uuid, uuid[]),
  public.archive_chore(uuid),
  public.complete_chore(uuid, date),
  public.undo_completion(uuid),
  public.claim_grocery_item(uuid),
  public.unclaim_grocery_item(uuid),
  public.buy_grocery_item(uuid),
  public.unbuy_grocery_item(uuid),
  public.household_contributions(uuid, timestamptz)
to authenticated;
