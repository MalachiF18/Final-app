-- RLS and RPC checks for the Daily Improvement Household database.
-- Trello card 1.9 (SQL half). Same harness as the budget-app database.
--
-- HOW TO RUN: apply the three migrations first, then paste this whole file
-- into the Supabase dashboard SQL editor and press Run (or `psql -f`).
--
-- WHAT YOU WILL SEE: the script ALWAYS ends with an ERROR on purpose. The
-- error message is the report, e.g.
--   RLS TEST REPORT: N passed, 0 failed (everything rolled back)
--   PASS 01 ...
-- Ending in an error is what guarantees nothing is saved: the test users,
-- households, chores and groceries all disappear with the rollback. If the
-- message is anything other than "RLS TEST REPORT", setup itself broke;
-- read that error.
--
-- HOW IT SIMULATES USERS: exactly what PostgREST does for an app request:
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"<user id>","role":"authenticated"}';
-- then calls the same public.* functions / selects the same tables the app
-- will. `reset role` goes back to the editor's own (postgres) role.
--
-- Every "cannot" check also has a control showing the SAME query does work
-- for someone allowed, so a zero-row result cannot pass vacuously, and
-- expected errors are matched on their message or SQLSTATE, so an unrelated
-- error (typo, missing function) is a FAIL, not a PASS.
--
-- PROVING THE CHECKS CAN FAIL: a check nobody has seen fail is not known to
-- work. Add ONE of these lines right after `begin;` below, run, confirm the
-- named check turns FAIL, then remove it (it is rolled back either way):
--
--   1. create policy "mutant" on public.grocery_items for select to authenticated using (true);
--        -> checks 26 and 31 must FAIL (an outsider / a former member can read the list).
--   2. drop index public.chore_completions_one_per_occurrence;
--        -> check 39 must FAIL (database no longer rejects a duplicate completion).
--      Check 13 still passes: it exercises the p_expected_due_on guard in the
--      function, a different layer. Only check 39 reaches the index.
--   3. grant update (bought_by) on public.grocery_items to authenticated;
--        -> check 22 must FAIL (a member can write bought_by directly).
--   4. alter publication supabase_realtime add table public.chore_rotation;
--        -> check 41 must FAIL (a table whose delete payload leaks user ids is published).
--
-- Test users (fixed ids, rolled back at the end):
--   A aaaaaaaa-...  creates the household (owner), Alice
--   B bbbbbbbb-...  member, Bob
--   C cccccccc-...  member, Carol
--   D dddddddd-...  outsider, Dave; never joins the first household
--
-- Check index
--   01-07  create / join / outsiders         08-10  chores: create, validate, no direct writes
--   11-13  rotation, fixed, duplicate        14-19  undo
--   20-22  groceries                         23-24  contributions
--   25-27  member vs outsider reads, throttle
--   28-31  roles, leaving, skip leaver       32-36  owner transfer, regenerate, remove, last member
--   37-38  anon and internal functions       39-41  database-level backstops

begin;

-- Report accumulator. A custom setting rather than a table, so every role
-- can append to it and it needs no grants.
select set_config('t.report', '', true);

-- ---------------------------------------------------------------- fixtures
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'authenticated', 'authenticated', 'dih-test-a@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'authenticated', 'authenticated', 'dih-test-b@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
   'authenticated', 'authenticated', 'dih-test-c@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
   'authenticated', 'authenticated', 'dih-test-d@example.test', '{}', '{}', now(), now());

-- ============================================================ as A
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 01: a user creates their own profile through RLS, then a household; the
--     invite code is 12 chars from the no-look-alike alphabet; A is the owner.
do $$
declare r record; v_role text;
begin
  insert into public.profiles (id, display_name)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Alice');
  select * into r from public.create_household('Test house');
  perform set_config('t.hh', r.household_id::text, true);
  perform set_config('t.code', r.invite_code, true);
  select m.role into v_role from public.household_members m
    where m.household_id = r.household_id and m.user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  perform set_config('t.report', current_setting('t.report') ||
    case when r.invite_code ~ '^[A-HJKMNP-Z2-9]{12}$' and v_role = 'owner'
         then E'\nPASS 01 create_household: 12-char code ' || r.invite_code || ', creator is owner'
         else E'\nFAIL 01 code=' || coalesce(r.invite_code, 'NULL') || ' role=' || coalesce(v_role, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 01 setup error: ' || sqlerrm, true);
end $$;

-- 02: a user cannot create a profile for somebody else.
do $$
declare v text;
begin
  begin
    insert into public.profiles (id, display_name)
      values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Impostor');
    v := 'ACCEPTED';
  exception when others then v := sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v like '42501%' then E'\nPASS 02 cannot create another user''s profile'
         else E'\nFAIL 02 got: ' || v end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 02 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 03: join normalises input: lowercase with a dash and a space still works,
--     and the joiner is a plain member.
do $$
declare v_code text := current_setting('t.code'); v_got uuid; v_role text;
begin
  insert into public.profiles (id, display_name)
    values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Bob');
  v_got := public.join_household(lower(substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4) || ' ' || substr(v_code, 9, 4)));
  select m.role into v_role from public.household_members m
    where m.household_id = v_got and m.user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  perform set_config('t.report', current_setting('t.report') ||
    case when v_got = current_setting('t.hh')::uuid and v_role = 'member'
         then E'\nPASS 03 join_household accepts lowercase/dashed/spaced code, joiner is a member'
         else E'\nFAIL 03 join returned ' || coalesce(v_got::text, 'NULL') || ' role=' || coalesce(v_role, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 03 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as C
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';

do $$
begin
  insert into public.profiles (id, display_name)
    values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Carol');
  perform set_config('t.report', current_setting('t.report') ||
    case when public.join_household(current_setting('t.code')) = current_setting('t.hh')::uuid
         then E'\nPASS 04 third member joins with the plain code'
         else E'\nFAIL 04 C could not join' end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 04 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as D (outsider)
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}';

-- 05: a well-formed but wrong code returns NULL, and so does a missing code;
--     neither makes D a member. (Two failed attempts are now on D's counter.)
do $$
declare
  v_wrong text := case when current_setting('t.code') = 'ZZZZZZZZZZZZ'
                       then 'YYYYYYYYYYYY' else 'ZZZZZZZZZZZZ' end;
  v_a uuid; v_b uuid;
begin
  insert into public.profiles (id, display_name)
    values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Dave');
  v_a := public.join_household(v_wrong);
  v_b := public.join_household(null);
  perform set_config('t.report', current_setting('t.report') ||
    case when v_a is null and v_b is null
              and not public.is_household_member(current_setting('t.hh')::uuid)
         then E'\nPASS 05 wrong code and missing code return NULL, no membership'
         else E'\nFAIL 05 wrong=' || coalesce(v_a::text, 'NULL') || ' missing=' || coalesce(v_b::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 05 error: ' || sqlerrm, true);
end $$;

-- 06: an outsider cannot add themself by writing household_members directly.
do $$
declare v text;
begin
  begin
    insert into public.household_members (household_id, user_id, role)
      values (current_setting('t.hh')::uuid, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'owner');
    v := 'ACCEPTED';
  exception when others then v := sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v like '42501%' then E'\nPASS 06 direct household_members insert: permission denied'
         else E'\nFAIL 06 got: ' || v end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 06 error: ' || sqlerrm, true);
end $$;

-- 07: an outsider cannot create a chore in someone else's household via the RPC.
do $$
declare v text;
begin
  begin
    perform public.create_chore(
      p_household_id := current_setting('t.hh')::uuid, p_name := 'Sneaky', p_effort := 1,
      p_repeat := 'weekly', p_rotation := array['dddddddd-dddd-4ddd-8ddd-dddddddddddd']::uuid[]);
    v := 'ACCEPTED';
  exception when others then v := sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v like '42501 You are not a member of this household%' then E'\nPASS 07 outsider cannot create a chore'
         else E'\nFAIL 07 got: ' || v end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 07 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 08: a member creates a rotating chore (A, B, C in order) and a fixed one
--     (for C). Rotation rows keep their order; a fixed chore has none.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  v_trash uuid; v_vac uuid;
  v_t public.chores%rowtype; v_v public.chores%rowtype;
  v_order text; v_vrot int;
begin
  v_trash := public.create_chore(
    p_household_id := hh, p_name := 'Take out trash', p_effort := 2, p_repeat := 'weekly',
    p_rotation := array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc']::uuid[]);
  v_vac := public.create_chore(
    p_household_id := hh, p_name := 'Vacuum', p_effort := 3, p_repeat := 'weekly',
    p_fixed := true, p_assignee := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
  perform set_config('t.trash', v_trash::text, true);
  perform set_config('t.vac', v_vac::text, true);
  select * into v_t from public.chores where id = v_trash;
  select * into v_v from public.chores where id = v_vac;
  select string_agg(left(cr.user_id::text, 1), '' order by cr.position) into v_order
    from public.chore_rotation cr where cr.chore_id = v_trash;
  select count(*) into v_vrot from public.chore_rotation where chore_id = v_vac;
  perform set_config('t.report', current_setting('t.report') ||
    case when v_t.assignee = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and not v_t.fixed
              and v_t.due_on = current_date and v_order = 'abc'
              and v_v.fixed and v_v.assignee = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' and v_vrot = 0
         then E'\nPASS 08 member creates chores: rotation order a,b,c starts with A; fixed chore has C and no rotation'
         else E'\nFAIL 08 trash assignee=' || coalesce(v_t.assignee::text, 'NULL') || ' order=' || coalesce(v_order, 'NULL')
              || ' vac fixed=' || v_v.fixed || ' vac rotation rows=' || v_vrot end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 08 error: ' || sqlerrm, true);
end $$;

-- 09: chore validation. Each bad input is refused with its own message.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  v1 text; v2 text; v3 text; v4 text;
begin
  begin  -- rotation with an outsider
    perform public.create_chore(p_household_id := hh, p_name := 'x', p_effort := 1, p_repeat := 'daily',
      p_rotation := array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','dddddddd-dddd-4ddd-8ddd-dddddddddddd']::uuid[]);
    v1 := 'ACCEPTED';
  exception when others then v1 := sqlerrm; end;
  begin  -- fixed chore with no assignee
    perform public.create_chore(p_household_id := hh, p_name := 'x', p_effort := 1, p_repeat := 'daily', p_fixed := true);
    v2 := 'ACCEPTED';
  exception when others then v2 := sqlerrm; end;
  begin  -- effort out of range
    perform public.create_chore(p_household_id := hh, p_name := 'x', p_effort := 4, p_repeat := 'daily',
      p_rotation := array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']::uuid[]);
    v3 := 'ACCEPTED';
  exception when others then v3 := sqlerrm; end;
  begin  -- fixed chore for an outsider
    perform public.create_chore(p_household_id := hh, p_name := 'x', p_effort := 1, p_repeat := 'daily',
      p_fixed := true, p_assignee := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
    v4 := 'ACCEPTED';
  exception when others then v4 := sqlerrm; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v1 like 'Everyone in the rotation must be a member%'
              and v2 like 'A fixed chore needs an assignee%'
              and v3 like 'Effort must be 1, 2 or 3%'
              and v4 like 'The assignee must be a member%'
         then E'\nPASS 09 outsider in rotation, fixed without assignee, effort 4, outsider assignee all rejected'
         else E'\nFAIL 09 got: [' || v1 || '] [' || v2 || '] [' || v3 || '] [' || v4 || ']' end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 09 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 10: a member cannot write chore tables directly: no insert, update or delete
--     on chores, no insert on rotation or completions. Control: B can read the chore.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  v_trash uuid := current_setting('t.trash')::uuid;
  v1 text; v2 text; v3 text; v4 text; v5 text; v_seen int;
begin
  select count(*) into v_seen from public.chores where id = v_trash;
  begin
    insert into public.chores (household_id, name, effort, created_by)
      values (hh, 'Direct', 1, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    v1 := 'ACCEPTED';
  exception when others then v1 := sqlstate; end;
  begin
    update public.chores set effort = 1 where id = v_trash;
    v2 := 'ACCEPTED';
  exception when others then v2 := sqlstate; end;
  begin
    delete from public.chores where id = v_trash;
    v3 := 'ACCEPTED';
  exception when others then v3 := sqlstate; end;
  begin
    insert into public.chore_completions (chore_id, household_id, completed_by, credited_to, due_on, effort)
      values (v_trash, hh, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', date '2099-01-01', 3);
    v4 := 'ACCEPTED';
  exception when others then v4 := sqlstate; end;
  begin
    insert into public.chore_rotation (chore_id, household_id, user_id, position)
      values (v_trash, hh, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 9);
    v5 := 'ACCEPTED';
  exception when others then v5 := sqlstate; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v_seen = 1 and v1 = '42501' and v2 = '42501' and v3 = '42501' and v4 = '42501' and v5 = '42501'
         then E'\nPASS 10 member cannot insert/update/delete chores or insert completions/rotation directly (control: can read)'
         else E'\nFAIL 10 seen=' || v_seen || ' ins=' || v1 || ' upd=' || v2 || ' del=' || v3 || ' comp=' || v4 || ' rot=' || v5 end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 10 error: ' || sqlerrm, true);
end $$;

-- ============================================================ 11: rotation A -> B -> C -> A
-- Each member completes the chore while it is theirs, passing the due date
-- they saw. Weekly, never overdue, so due_on moves +7 each time.
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
do $$
begin
  perform set_config('t.n1', public.complete_chore(current_setting('t.trash')::uuid, current_date)::text, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 11 step 1 error: ' || sqlerrm, true);
end $$;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';
do $$
begin
  perform set_config('t.n2', public.complete_chore(current_setting('t.trash')::uuid, current_date + 7)::text, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 11 step 2 error: ' || sqlerrm, true);
end $$;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';
do $$
declare
  v_trash uuid := current_setting('t.trash')::uuid;
  n3 uuid; v_t public.chores%rowtype; v_credit text;
begin
  n3 := public.complete_chore(v_trash, current_date + 14);
  select * into v_t from public.chores where id = v_trash;
  select string_agg(left(c.credited_to::text, 1), '' order by c.due_on) into v_credit
    from public.chore_completions c where c.chore_id = v_trash and c.undone_at is null;
  perform set_config('t.report', current_setting('t.report') ||
    case when current_setting('t.n1')::uuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
              and current_setting('t.n2')::uuid = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
              and n3 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
              and v_t.assignee = n3 and v_t.due_on = current_date + 21 and v_credit = 'abc'
         then E'\nPASS 11 rotation A->B->C->A, due_on +7 each time (now +21), credit a,b,c'
         else E'\nFAIL 11 returned ' || coalesce(current_setting('t.n1'), '?') || ',' || coalesce(current_setting('t.n2'), '?') || ',' || coalesce(n3::text, 'NULL')
              || ' due=' || v_t.due_on || ' credit=' || coalesce(v_credit, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 11 step 3 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 12: a fixed chore does not rotate. A covers for C: the completion is
--     recorded by A but credited to C, and the chore stays with C.
do $$
declare
  v_vac uuid := current_setting('t.vac')::uuid;
  v_next uuid; v_v public.chores%rowtype; v_c public.chore_completions%rowtype;
begin
  v_next := public.complete_chore(v_vac, current_date);
  select * into v_v from public.chores where id = v_vac;
  select * into v_c from public.chore_completions where chore_id = v_vac and undone_at is null;
  perform set_config('t.report', current_setting('t.report') ||
    case when v_next = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' and v_v.assignee = v_next and v_v.due_on = current_date + 7
              and v_c.completed_by = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
              and v_c.credited_to = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' and v_c.effort = 3
         then E'\nPASS 12 fixed chore stays with C; A covered, credit goes to C (3 points)'
         else E'\nFAIL 12 next=' || coalesce(v_next::text, 'NULL') || ' by=' || v_c.completed_by || ' credited=' || v_c.credited_to end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 12 error: ' || sqlerrm, true);
end $$;

-- 13: completing the same occurrence twice is rejected (card 2.10): a second
--     tap that still carries the old due date finds the chore has moved on.
--     (Control: the first completion in 12 succeeded.) Exactly one live
--     completion exists afterwards.
do $$
declare v text; n int;
begin
  begin
    perform public.complete_chore(current_setting('t.vac')::uuid, current_date);
    v := 'ACCEPTED';
  exception when others then v := sqlerrm; end;
  select count(*) into n from public.chore_completions
    where chore_id = current_setting('t.vac')::uuid and undone_at is null;
  perform set_config('t.report', current_setting('t.report') ||
    case when v like 'This chore was already completed%' and n = 1
         then E'\nPASS 13 second completion of the same occurrence rejected; one live completion'
         else E'\nFAIL 13 got: ' || v || ' live completions=' || n end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 13 error: ' || sqlerrm, true);
end $$;

-- 14: an OVERDUE chore advances from today, not from its old due date.
--     "Undo me" is weekly, rotates A,B, due 3 days ago. Completing it gives
--     due today + 7 (not today + 4) and hands it to B.
do $$
declare
  v_chore uuid; v_next uuid; v_ch public.chores%rowtype; v_comp uuid;
begin
  v_chore := public.create_chore(
    p_household_id := current_setting('t.hh')::uuid, p_name := 'Undo me', p_effort := 1,
    p_repeat := 'weekly', p_due_on := current_date - 3,
    p_rotation := array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb']::uuid[]);
  perform set_config('t.undome', v_chore::text, true);
  v_next := public.complete_chore(v_chore);
  select * into v_ch from public.chores where id = v_chore;
  select id into v_comp from public.chore_completions where chore_id = v_chore and undone_at is null;
  perform set_config('t.uc1', v_comp::text, true);
  perform set_config('t.report', current_setting('t.report') ||
    case when v_next = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and v_ch.due_on = current_date + 7
         then E'\nPASS 14 overdue chore restarts from today (due today+7) and passes to B'
         else E'\nFAIL 14 next=' || coalesce(v_next::text, 'NULL') || ' due=' || v_ch.due_on end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 14 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 15: someone other than the completer cannot undo; nothing changes.
do $$
declare v text; v_undone timestamptz;
begin
  begin
    perform public.undo_completion(current_setting('t.uc1')::uuid);
    v := 'ACCEPTED';
  exception when others then v := sqlstate || ' ' || sqlerrm; end;
  select undone_at into v_undone from public.chore_completions where id = current_setting('t.uc1')::uuid;
  perform set_config('t.report', current_setting('t.report') ||
    case when v like '42501 Only the person who completed this chore can undo it%' and v_undone is null
         then E'\nPASS 15 undo by someone else rejected, completion still live'
         else E'\nFAIL 15 got: ' || v || ' undone_at=' || coalesce(v_undone::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 15 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 16: the completer undoes it: due_on is the old occurrence again, the
--     assignee is back to A, and the completion is marked undone.
do $$
declare v_ch public.chores%rowtype; v_undone timestamptz;
begin
  perform public.undo_completion(current_setting('t.uc1')::uuid);
  select * into v_ch from public.chores where id = current_setting('t.undome')::uuid;
  select undone_at into v_undone from public.chore_completions where id = current_setting('t.uc1')::uuid;
  perform set_config('t.report', current_setting('t.report') ||
    case when v_ch.due_on = current_date - 3 and v_ch.assignee = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and v_undone is not null
         then E'\nPASS 16 undo by the completer restores due_on and assignee'
         else E'\nFAIL 16 due=' || v_ch.due_on || ' assignee=' || coalesce(v_ch.assignee::text, 'NULL') || ' undone_at=' || coalesce(v_undone::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 16 error: ' || sqlerrm, true);
end $$;

-- 17: a one-time chore is archived when completed (returns NULL) and
--     un-archived by undo.
do $$
declare
  v_once uuid; v_next uuid; v_arch1 boolean; v_arch2 boolean; v_comp uuid;
begin
  v_once := public.create_chore(
    p_household_id := current_setting('t.hh')::uuid, p_name := 'Once', p_effort := 1, p_repeat := 'none',
    p_rotation := array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']::uuid[]);
  v_next := public.complete_chore(v_once);
  select archived into v_arch1 from public.chores where id = v_once;
  select id into v_comp from public.chore_completions where chore_id = v_once and undone_at is null;
  perform public.undo_completion(v_comp);
  select archived into v_arch2 from public.chores where id = v_once;
  perform set_config('t.report', current_setting('t.report') ||
    case when v_next is null and v_arch1 and not v_arch2
         then E'\nPASS 17 one-time chore archived on completion, un-archived by undo'
         else E'\nFAIL 17 next=' || coalesce(v_next::text, 'NULL') || ' archived after=' || v_arch1 || ' after undo=' || v_arch2 end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 17 error: ' || sqlerrm, true);
end $$;

-- 18: an occurrence whose completion was undone can be completed again (the
--     unique index only covers live completions). This completion stays and
--     is worth 1 point to A.
do $$
declare v_next uuid; v_comp uuid;
begin
  v_next := public.complete_chore(current_setting('t.undome')::uuid, current_date - 3);
  select id into v_comp from public.chore_completions
    where chore_id = current_setting('t.undome')::uuid and undone_at is null;
  perform set_config('t.uc2', v_comp::text, true);
  perform set_config('t.report', current_setting('t.report') ||
    case when v_next = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and v_comp is not null
         then E'\nPASS 18 an undone occurrence can be completed again'
         else E'\nFAIL 18 next=' || coalesce(v_next::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 18 error: ' || sqlerrm, true);
end $$;

-- Age that completion past the 24-hour undo window (as the editor's role).
reset role;
update public.chore_completions set completed_at = now() - interval '25 hours'
  where id = current_setting('t.uc2')::uuid;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 19: the completer cannot undo after 24 hours. (Control: 16 shows the same
--     call works inside the window.)
do $$
declare v text; v_undone timestamptz;
begin
  begin
    perform public.undo_completion(current_setting('t.uc2')::uuid);
    v := 'ACCEPTED';
  exception when others then v := sqlstate || ' ' || sqlerrm; end;
  select undone_at into v_undone from public.chore_completions where id = current_setting('t.uc2')::uuid;
  perform set_config('t.report', current_setting('t.report') ||
    case when v like '%within 24 hours%' and v_undone is null
         then E'\nPASS 19 undo after 24 hours rejected'
         else E'\nFAIL 19 got: ' || v end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 19 error: ' || sqlerrm, true);
end $$;

-- 20: groceries. A member adds an item directly through RLS (defaults fill in
--     quantity and category). Forged inserts are refused: added_by someone
--     else, a pre-set claim, a pre-set buyer.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  v_id uuid; v_qty text; v_by uuid;
  v1 text; v2 text; v3 text;
begin
  insert into public.grocery_items (household_id, name) values (hh, 'Milk') returning id, quantity, added_by into v_id, v_qty, v_by;
  perform set_config('t.milk', v_id::text, true);
  begin
    insert into public.grocery_items (household_id, name, added_by)
      values (hh, 'Forged author', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    v1 := 'ACCEPTED';
  exception when others then v1 := sqlstate; end;
  begin
    insert into public.grocery_items (household_id, name, claimed_by)
      values (hh, 'Pre-claimed', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    v2 := 'ACCEPTED';
  exception when others then v2 := sqlstate; end;
  begin
    insert into public.grocery_items (household_id, name, bought_by, bought_at)
      values (hh, 'Pre-bought', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now());
    v3 := 'ACCEPTED';
  exception when others then v3 := sqlstate; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v_qty = '1' and v_by = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
              and v1 = '42501' and v2 = '42501' and v3 = '42501'
         then E'\nPASS 20 member adds an item directly; forged added_by / claim / buyer on insert refused'
         else E'\nFAIL 20 qty=' || coalesce(v_qty, 'NULL') || ' by=' || coalesce(v_by::text, 'NULL') || ' forged=' || v1 || ',' || v2 || ',' || v3 end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 20 error: ' || sqlerrm, true);
end $$;

-- A claims the milk (through the function).
do $$
begin
  perform public.claim_grocery_item(current_setting('t.milk')::uuid);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 21 setup (A claims milk) error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 21: claim rules. B adds eggs. B cannot take A's claim, cannot clear it, and
--     cannot write claimed_by directly (not even on an unclaimed item). The
--     control is a direct rename of the eggs, which IS allowed.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  v_eggs uuid; v1 text; v2 text; v3 text; v_renamed text; v_claim uuid;
begin
  insert into public.grocery_items (household_id, name, quantity, category)
    values (hh, 'Eggs', '12', 'Kitchen') returning id into v_eggs;
  perform set_config('t.eggs', v_eggs::text, true);
  begin
    perform public.claim_grocery_item(current_setting('t.milk')::uuid);
    v1 := 'ACCEPTED';
  exception when others then v1 := sqlerrm; end;
  begin
    perform public.unclaim_grocery_item(current_setting('t.milk')::uuid);
    v2 := 'ACCEPTED';
  exception when others then v2 := sqlerrm; end;
  begin
    update public.grocery_items set claimed_by = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where id = v_eggs;
    v3 := 'ACCEPTED';
  exception when others then v3 := sqlstate; end;
  update public.grocery_items set name = 'Eggs (dozen)' where id = v_eggs returning name into v_renamed;
  select claimed_by into v_claim from public.grocery_items where id = current_setting('t.milk')::uuid;
  perform set_config('t.report', current_setting('t.report') ||
    case when v1 like 'Someone else already claimed%' and v2 like 'Only the person who claimed%'
              and v3 = '42501' and v_renamed = 'Eggs (dozen)'
              and v_claim = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
         then E'\nPASS 21 B cannot steal, clear or directly write a claim; A''s claim intact; direct rename allowed'
         else E'\nFAIL 21 steal=' || v1 || ' clear=' || v2 || ' direct=' || v3 || ' renamed=' || coalesce(v_renamed, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 21 error: ' || sqlerrm, true);
end $$;

-- 22: bought_by is always the caller. B cannot write bought_by directly, for
--     A or for self. Through the function it is B (the function has no
--     argument to name anybody else), and A cannot undo B's purchase.
do $$
declare
  v_eggs uuid := current_setting('t.eggs')::uuid;
  v1 text; v2 text; v_by uuid;
begin
  begin
    update public.grocery_items set bought_by = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', bought_at = now() where id = v_eggs;
    v1 := 'ACCEPTED';
  exception when others then v1 := sqlstate; end;
  begin
    update public.grocery_items set bought_by = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', bought_at = now() where id = v_eggs;
    v2 := 'ACCEPTED';
  exception when others then v2 := sqlstate; end;
  perform public.buy_grocery_item(v_eggs);
  select bought_by into v_by from public.grocery_items where id = v_eggs;
  perform set_config('t.report', current_setting('t.report') ||
    case when v1 = '42501' and v2 = '42501' and v_by = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
         then E'\nPASS 22 bought_by cannot be written directly; the function sets it to the caller'
         else E'\nFAIL 22 direct for A=' || v1 || ' direct for self=' || v2 || ' via function=' || coalesce(v_by::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 22 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 22b: A cannot undo B's purchase, then buys the milk A claimed (bought_by A).
do $$
declare v text; v_by uuid;
begin
  begin
    perform public.unbuy_grocery_item(current_setting('t.eggs')::uuid);
    v := 'ACCEPTED';
  exception when others then v := sqlstate || ' ' || sqlerrm; end;
  perform public.buy_grocery_item(current_setting('t.milk')::uuid);
  select bought_by into v_by from public.grocery_items where id = current_setting('t.milk')::uuid;
  perform set_config('t.report', current_setting('t.report') ||
    case when v like '42501 Only the person who bought this item%' and v_by = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
         then E'\nPASS 22b non-buyer cannot undo a purchase; A buys the milk A claimed'
         else E'\nFAIL 22b got: ' || v || ' milk bought_by=' || coalesce(v_by::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 22b error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 23: contributions. Chores credit the assignee at completion, groceries the
--     buyer; the undone completions (14/16, 17) and nobody-else count for
--     nothing. Expected over the last 7 days:
--       A = trash 2 + "Undo me" (second completion) 1 + milk 1 = 4
--       B = trash 2 + eggs 1 = 3
--       C = trash 2 + vacuum 3 (credited to C, completed by A) = 5
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  pa bigint; pb bigint; pc bigint; n int;
begin
  select count(*) into n from public.household_contributions(hh, now() - interval '7 days');
  select points into pa from public.household_contributions(hh, now() - interval '7 days') where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  select points into pb from public.household_contributions(hh, now() - interval '7 days') where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  select points into pc from public.household_contributions(hh, now() - interval '7 days') where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  perform set_config('t.report', current_setting('t.report') ||
    case when n = 3 and pa = 4 and pb = 3 and pc = 5
         then E'\nPASS 23 contributions: A=4 B=3 C=5, three rows, undone completions excluded'
         else E'\nFAIL 23 rows=' || n || ' A=' || coalesce(pa::text, 'NULL') || ' B=' || coalesce(pb::text, 'NULL') || ' C=' || coalesce(pc::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 23 error: ' || sqlerrm, true);
end $$;

-- 24: the since filter works. A future date: everyone has 0 (and is still
--     listed). The last 24 hours exclude A's backdated 25-hour-old
--     completion (A = 3). NULL means all time (A = 4 again).
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  n_future int; sum_future bigint; a_day bigint; b_day bigint; c_day bigint; a_all bigint;
begin
  select count(*), coalesce(sum(points), 0) into n_future, sum_future
    from public.household_contributions(hh, now() + interval '1 day');
  select points into a_day from public.household_contributions(hh, now() - interval '24 hours') where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  select points into b_day from public.household_contributions(hh, now() - interval '24 hours') where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  select points into c_day from public.household_contributions(hh, now() - interval '24 hours') where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  select points into a_all from public.household_contributions(hh, null) where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  perform set_config('t.report', current_setting('t.report') ||
    case when n_future = 3 and sum_future = 0 and a_day = 3 and b_day = 3 and c_day = 5 and a_all = 4
         then E'\nPASS 24 since filter: future = all zeros, last 24h drops the old completion (A=3), null = all time'
         else E'\nFAIL 24 future rows=' || n_future || ' sum=' || sum_future || ' 24h A=' || coalesce(a_day::text, 'NULL') || ' B=' || coalesce(b_day::text, 'NULL') || ' C=' || coalesce(c_day::text, 'NULL') || ' all A=' || coalesce(a_all::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 24 error: ' || sqlerrm, true);
end $$;

-- 25: members CAN read the household's data. This is also the control arm
--     for the outsider check (26): same queries, must be non-zero here.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  n_h int; n_m int; n_c int; n_r int; n_k int; n_g int; n_p int;
begin
  select count(*) into n_h from public.households where id = hh;
  select count(*) into n_m from public.household_members where household_id = hh;
  select count(*) into n_c from public.chores where household_id = hh;
  select count(*) into n_r from public.chore_rotation where household_id = hh;
  select count(*) into n_k from public.chore_completions where household_id = hh;
  select count(*) into n_g from public.grocery_items where household_id = hh;
  select count(*) into n_p from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  perform set_config('t.report', current_setting('t.report') ||
    case when n_h = 1 and n_m = 3 and n_c >= 4 and n_r >= 6 and n_k >= 7 and n_g = 2 and n_p = 1
         then E'\nPASS 25 member reads household, members, chores, rotation, completions, groceries, housemate profile'
         else E'\nFAIL 25 member counts h=' || n_h || ' m=' || n_m || ' c=' || n_c || ' r=' || n_r || ' k=' || n_k || ' g=' || n_g || ' p=' || n_p end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 25 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as D (outsider)
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}';

-- 26: an outsider sees nothing of the household (same queries as 25), cannot
--     add to its grocery list, cannot complete its chores, and the
--     contributions function returns no rows.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  n_h int; n_m int; n_c int; n_r int; n_k int; n_g int; n_p int; n_contrib int;
  v_ins text; v_done text;
begin
  select count(*) into n_h from public.households where id = hh;
  select count(*) into n_m from public.household_members where household_id = hh;
  select count(*) into n_c from public.chores where household_id = hh;
  select count(*) into n_r from public.chore_rotation where household_id = hh;
  select count(*) into n_k from public.chore_completions where household_id = hh;
  select count(*) into n_g from public.grocery_items where household_id = hh;
  select count(*) into n_p from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  select count(*) into n_contrib from public.household_contributions(hh, null);
  begin
    insert into public.grocery_items (household_id, name) values (hh, 'Outsider item');
    v_ins := 'ACCEPTED';
  exception when others then v_ins := sqlstate; end;
  begin
    perform public.complete_chore(current_setting('t.trash')::uuid);
    v_done := 'ACCEPTED';
  exception when others then v_done := sqlstate || ' ' || sqlerrm; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when n_h + n_m + n_c + n_r + n_k + n_g + n_p + n_contrib = 0
              and v_ins = '42501' and v_done like '42501 Chore not found%'
         then E'\nPASS 26 outsider reads 0 rows of every household table and contributions; cannot add groceries or complete chores'
         else E'\nFAIL 26 outsider counts h=' || n_h || ' m=' || n_m || ' c=' || n_c || ' r=' || n_r || ' k=' || n_k || ' g=' || n_g || ' p=' || n_p || ' contrib=' || n_contrib || ' insert=' || v_ins || ' complete=' || v_done end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 26 error: ' || sqlerrm, true);
end $$;

-- 27: brute-force friction. D already has 2 failed attempts (05). Eight more
--     wrong codes return NULL; the next call is refused, and stays refused
--     even with the CORRECT code (the throttle runs before the lookup).
do $$
declare
  v_wrong text := case when current_setting('t.code') = 'ZZZZZZZZZZZZ'
                       then 'YYYYYYYYYYYY' else 'ZZZZZZZZZZZZ' end;
  i int;
  v_refused_at int;
begin
  for i in 3 .. 15 loop
    begin
      perform public.join_household(v_wrong);
    exception when others then
      if sqlerrm like 'Too many wrong codes%' then v_refused_at := i; exit; end if;
      raise;
    end;
  end loop;
  begin
    perform public.join_household(current_setting('t.code'));
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 27 throttled user still joined with the right code', true);
  exception when others then
    if v_refused_at = 11 and sqlerrm like 'Too many wrong codes%' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 27 11th attempt refused after 10 wrong codes, even with the right code', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 27 refused_at=' || coalesce(v_refused_at::text, 'never') || ' last error: ' || sqlerrm, true);
    end if;
  end;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 27 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 28: a plain member cannot regenerate the invite code or remove anyone.
--     (Controls: owner A regenerates in 34 and removes in 35.)
do $$
declare hh uuid := current_setting('t.hh')::uuid; v1 text; v2 text; v_code text;
begin
  begin
    perform public.regenerate_invite_code(hh);
    v1 := 'ACCEPTED';
  exception when others then v1 := sqlstate || ' ' || sqlerrm; end;
  begin
    perform public.remove_member(hh, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    v2 := 'ACCEPTED';
  exception when others then v2 := sqlstate || ' ' || sqlerrm; end;
  select invite_code into v_code from public.households where id = hh;
  perform set_config('t.report', current_setting('t.report') ||
    case when v1 like '42501 Only the household owner%' and v2 like '42501 Only the household owner%'
              and v_code = current_setting('t.code')
         then E'\nPASS 28 member cannot regenerate the code or remove a member; code unchanged'
         else E'\nFAIL 28 regenerate=' || v1 || ' remove=' || v2 end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 28 error: ' || sqlerrm, true);
end $$;

-- B adds and claims a soap (to be dropped when B leaves).
do $$
declare v_soap uuid;
begin
  insert into public.grocery_items (household_id, name) values (current_setting('t.hh')::uuid, 'Soap') returning id into v_soap;
  perform set_config('t.soap', v_soap::text, true);
  perform public.claim_grocery_item(v_soap);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 29 setup (soap) error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- Three chores that depend on B: "Skip" (A is up, B is in the rotation),
-- "Dishes" (B is up), "FixedB" (B holds it for good).
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  rot uuid[] := array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc']::uuid[];
begin
  perform set_config('t.skip', public.create_chore(p_household_id := hh, p_name := 'Skip', p_effort := 1, p_repeat := 'daily', p_rotation := rot)::text, true);
  perform set_config('t.dishes', public.create_chore(p_household_id := hh, p_name := 'Dishes', p_effort := 1, p_repeat := 'daily',
    p_assignee := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', p_rotation := rot)::text, true);
  perform set_config('t.fixedb', public.create_chore(p_household_id := hh, p_name := 'FixedB', p_effort := 1, p_repeat := 'daily',
    p_fixed := true, p_assignee := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')::text, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 29 setup (chores) error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

do $$
begin
  perform public.leave_household(current_setting('t.hh')::uuid);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 29 B leave error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 29: B left. Membership is gone; B drops out of every rotation; chores B
--     held move on (Dishes to the next in rotation, C; "Undo me" wraps to A;
--     the fixed chore loses its fixed assignee and becomes unassigned); B's
--     unbought claim is released but the bought eggs keep B as buyer; B no
--     longer appears in contributions.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  n_member int; n_rot int; v_dishes uuid; v_undome uuid; v_fx public.chores%rowtype;
  v_soap uuid; v_eggs uuid; n_rows int; n_b int;
begin
  select count(*) into n_member from public.household_members where household_id = hh and user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  select count(*) into n_rot from public.chore_rotation where household_id = hh and user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  select assignee into v_dishes from public.chores where id = current_setting('t.dishes')::uuid;
  select assignee into v_undome from public.chores where id = current_setting('t.undome')::uuid;
  select * into v_fx from public.chores where id = current_setting('t.fixedb')::uuid;
  select claimed_by into v_soap from public.grocery_items where id = current_setting('t.soap')::uuid;
  select bought_by into v_eggs from public.grocery_items where id = current_setting('t.eggs')::uuid;
  select count(*), count(*) filter (where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
    into n_rows, n_b from public.household_contributions(hh, null);
  perform set_config('t.report', current_setting('t.report') ||
    case when n_member = 0 and n_rot = 0
              and v_dishes = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
              and v_undome = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
              and not v_fx.fixed and v_fx.assignee is null
              and v_soap is null and v_eggs = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
              and n_rows = 2 and n_b = 0
         then E'\nPASS 29 B left: out of members and rotations; chores moved on; fixed chore unassigned; claim released; history kept'
         else E'\nFAIL 29 members=' || n_member || ' rot=' || n_rot || ' dishes=' || coalesce(v_dishes::text, 'NULL') || ' undome=' || coalesce(v_undome::text, 'NULL')
              || ' fixed=' || v_fx.fixed || ' fx assignee=' || coalesce(v_fx.assignee::text, 'NULL') || ' soap claim=' || coalesce(v_soap::text, 'NULL')
              || ' eggs buyer=' || coalesce(v_eggs::text, 'NULL') || ' contrib rows=' || n_rows || ' B rows=' || n_b end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 29 error: ' || sqlerrm, true);
end $$;

-- 30: rotation skips the member who left. "Skip" rotates A, B, C and A is up;
--     B left, so completing it passes to C, not B. (Control: in 11 the same
--     shape of chore went A to B while B was a member.)
do $$
declare v_next uuid;
begin
  v_next := public.complete_chore(current_setting('t.skip')::uuid);
  perform set_config('t.report', current_setting('t.report') ||
    case when v_next = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
         then E'\nPASS 30 rotation skips the member who left (A to C)'
         else E'\nFAIL 30 next=' || coalesce(v_next::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 30 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B (no longer a member)
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 31: a former member sees nothing and cannot act on the household.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  n_h int; n_m int; n_c int; n_g int; n_k int; v_done text;
begin
  select count(*) into n_h from public.households where id = hh;
  select count(*) into n_m from public.household_members where household_id = hh;
  select count(*) into n_c from public.chores where household_id = hh;
  select count(*) into n_g from public.grocery_items where household_id = hh;
  select count(*) into n_k from public.chore_completions where household_id = hh;
  begin
    perform public.complete_chore(current_setting('t.trash')::uuid);
    v_done := 'ACCEPTED';
  exception when others then v_done := sqlstate; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when n_h + n_m + n_c + n_g + n_k = 0 and v_done = '42501'
         then E'\nPASS 31 former member reads 0 rows and cannot complete chores'
         else E'\nFAIL 31 counts h=' || n_h || ' m=' || n_m || ' c=' || n_c || ' g=' || n_g || ' k=' || n_k || ' complete=' || v_done end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 31 error: ' || sqlerrm, true);
end $$;

-- ============================================================ owner transfer (second household)
-- A creates a second household; B and C join it.
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
do $$
declare r record;
begin
  select * into r from public.create_household('Second house');
  perform set_config('t.hh2', r.household_id::text, true);
  perform set_config('t.code2', r.invite_code, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 32 setup (second household) error: ' || sqlerrm, true);
end $$;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';
do $$
begin
  perform public.join_household(current_setting('t.code2'));
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 32 setup (B joins second) error: ' || sqlerrm, true);
end $$;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';
do $$
begin
  perform public.join_household(current_setting('t.code2'));
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 32 setup (C joins second) error: ' || sqlerrm, true);
end $$;

-- Backdate joins so C joined EARLIER than B. Ids alone would pick B (bbbb is
-- smaller than cccc), so only a real "earliest joined" rule picks C.
reset role;
update public.household_members set joined_at = now() - interval '3 days'
  where household_id = current_setting('t.hh2')::uuid and user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
update public.household_members set joined_at = now() - interval '1 day'
  where household_id = current_setting('t.hh2')::uuid and user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 32: a member cannot remove another member (only the owner can).
do $$
declare v text; n int;
begin
  begin
    perform public.remove_member(current_setting('t.hh2')::uuid, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    v := 'ACCEPTED';
  exception when others then v := sqlstate || ' ' || sqlerrm; end;
  select count(*) into n from public.household_members where household_id = current_setting('t.hh2')::uuid;
  perform set_config('t.report', current_setting('t.report') ||
    case when v like '42501 Only the household owner can remove members%' and n = 3
         then E'\nPASS 32 non-owner cannot remove a member; all 3 still in'
         else E'\nFAIL 32 got: ' || v || ' members=' || n end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 32 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

do $$
begin
  perform public.leave_household(current_setting('t.hh2')::uuid);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 33 owner leave error: ' || sqlerrm, true);
end $$;

-- 33 (part 1, as A): the owner left, so A sees nothing of it and cannot leave twice.
do $$
declare n int; v text;
begin
  select count(*) into n from public.households where id = current_setting('t.hh2')::uuid;
  begin
    perform public.leave_household(current_setting('t.hh2')::uuid);
    v := 'ACCEPTED';
  exception when others then v := sqlstate; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when n = 0 and v = '42501'
         then E'\nPASS 33a the leaving owner no longer sees the household and cannot leave again'
         else E'\nFAIL 33a visible rows=' || n || ' second leave=' || v end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 33a error: ' || sqlerrm, true);
end $$;

-- ============================================================ as C
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';

-- 33 (part 2, as C): ownership went to the EARLIEST joined member (C, not B),
--     and exactly one owner remains.
do $$
declare
  hh2 uuid := current_setting('t.hh2')::uuid;
  v_c text; v_b text; n_owner int;
begin
  select m.role into v_c from public.household_members m where m.household_id = hh2 and m.user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  select m.role into v_b from public.household_members m where m.household_id = hh2 and m.user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  select count(*) into n_owner from public.household_members where household_id = hh2 and role = 'owner';
  perform set_config('t.report', current_setting('t.report') ||
    case when v_c = 'owner' and v_b = 'member' and n_owner = 1
         then E'\nPASS 33 owner left: ownership passed to the earliest-joined member (C, not B), one owner'
         else E'\nFAIL 33 C=' || coalesce(v_c, 'NULL') || ' B=' || coalesce(v_b, 'NULL') || ' owners=' || n_owner end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 33 error: ' || sqlerrm, true);
end $$;

-- C, the new owner, regenerates the code.
do $$
declare v_new text;
begin
  v_new := public.regenerate_invite_code(current_setting('t.hh2')::uuid);
  perform set_config('t.code2new', v_new, true);
  -- A fixed chore held by C: when C, the last member, leaves in 36, deleting
  -- the household must not trip over this chore's "fixed needs an assignee" check.
  perform public.create_chore(p_household_id := current_setting('t.hh2')::uuid, p_name := 'Fixed C', p_effort := 1,
    p_repeat := 'weekly', p_fixed := true, p_assignee := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 34 setup (C regenerates) error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A (now an outsider of the second household)
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 34: the old code stops working (NULL), the new one works, and a
--     non-member cannot regenerate. (A rejoins here, so 36 has two to remove.)
do $$
declare
  hh2 uuid := current_setting('t.hh2')::uuid;
  v_old uuid; v_regen text; v_new uuid; v_fmt boolean;
begin
  v_old := public.join_household(current_setting('t.code2'));
  begin
    perform public.regenerate_invite_code(hh2);
    v_regen := 'ACCEPTED';
  exception when others then v_regen := sqlstate; end;
  v_fmt := current_setting('t.code2new') ~ '^[A-HJKMNP-Z2-9]{12}$' and current_setting('t.code2new') <> current_setting('t.code2');
  v_new := public.join_household(current_setting('t.code2new'));
  perform set_config('t.report', current_setting('t.report') ||
    case when v_old is null and v_regen = '42501' and v_fmt and v_new = hh2
         then E'\nPASS 34 regenerate: old code returns NULL, new code joins, non-member cannot regenerate'
         else E'\nFAIL 34 old=' || coalesce(v_old::text, 'NULL') || ' non-member regenerate=' || v_regen || ' fmt=' || v_fmt || ' new=' || coalesce(v_new::text, 'NULL') end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 34 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as C
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';

-- 35: the owner removes a member; the owner cannot remove themself.
do $$
declare hh2 uuid := current_setting('t.hh2')::uuid; v_self text; n_b int;
begin
  perform public.remove_member(hh2, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  begin
    perform public.remove_member(hh2, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    v_self := 'ACCEPTED';
  exception when others then v_self := sqlerrm; end;
  select count(*) into n_b from public.household_members where household_id = hh2 and user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  perform set_config('t.report', current_setting('t.report') ||
    case when n_b = 0 and v_self like 'Use leave household%'
         then E'\nPASS 35 owner removes a member; owner cannot remove themself'
         else E'\nFAIL 35 B still member=' || n_b || ' self=' || v_self end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 35 error: ' || sqlerrm, true);
end $$;

-- 36: members now are C (owner) and A. A leaves (a plain member), then C, the
--     last one, leaves: the household and its data are deleted. Checked as the
--     editor's role, since nobody can see it any more.
do $$
begin
  perform set_config('t.hh2_members_before', (select count(*) from public.household_members where household_id = current_setting('t.hh2')::uuid)::text, true);
end $$;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
do $$
begin
  perform public.leave_household(current_setting('t.hh2')::uuid);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 36 A leave error: ' || sqlerrm, true);
end $$;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';
do $$
declare n_mid int;
begin
  select count(*) into n_mid from public.household_members where household_id = current_setting('t.hh2')::uuid;
  perform set_config('t.mid', n_mid::text, true);
  perform public.leave_household(current_setting('t.hh2')::uuid);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 36 C leave error: ' || sqlerrm, true);
end $$;

reset role;
do $$
declare n_h int; n_m int; n_c int;
begin
  select count(*) into n_h from public.households where id = current_setting('t.hh2')::uuid;
  select count(*) into n_m from public.household_members where household_id = current_setting('t.hh2')::uuid;
  select count(*) into n_c from public.chores where household_id = current_setting('t.hh2')::uuid;
  perform set_config('t.report', current_setting('t.report') ||
    case when current_setting('t.hh2_members_before') = '2' and current_setting('t.mid') = '1' and n_h = 0 and n_m = 0 and n_c = 0
         then E'\nPASS 36 a plain member leaves (2 to 1 members); the last member leaving deletes the household and its chores'
         else E'\nFAIL 36 before=' || current_setting('t.hh2_members_before') || ' mid=' || current_setting('t.mid') || ' household rows=' || n_h || ' member rows=' || n_m || ' chore rows=' || n_c end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 36 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as anon (not signed in)
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

-- 37: a client that has not signed in can neither read nor call the API.
do $$
declare v_read text; v_read2 text; v_call text; v_call2 text;
begin
  begin
    perform count(*) from public.households;
    v_read := 'allowed';
  exception when others then v_read := sqlstate; end;
  begin
    perform count(*) from public.grocery_items;
    v_read2 := 'allowed';
  exception when others then v_read2 := sqlstate; end;
  begin
    perform public.create_household('Anon house');
    v_call := 'allowed';
  exception when others then v_call := sqlstate; end;
  begin
    perform * from public.household_contributions('00000000-0000-0000-0000-000000000000', null);
    v_call2 := 'allowed';
  exception when others then v_call2 := sqlstate; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v_read = '42501' and v_read2 = '42501' and v_call = '42501' and v_call2 = '42501'
         then E'\nPASS 37 anon: no table read, no RPC execute'
         else E'\nFAIL 37 anon read=' || v_read || ',' || v_read2 || ' call=' || v_call || ',' || v_call2 end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 37 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 38: internal helpers are not part of the API: a signed-in client cannot
--     call them (household_detach_member would remove anyone from anywhere).
do $$
declare v1 text; v2 text;
begin
  begin
    perform public.household_detach_member(current_setting('t.hh')::uuid, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    v1 := 'ACCEPTED';
  exception when others then v1 := sqlstate; end;
  begin
    perform public.generate_invite_code();
    v2 := 'ACCEPTED';
  exception when others then v2 := sqlstate; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v1 = '42501' and v2 = '42501'
         then E'\nPASS 38 internal helper functions are not executable by clients'
         else E'\nFAIL 38 detach=' || v1 || ' generate=' || v2 end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 38 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as postgres
reset role;

-- 39: COMPONENT test of the unique index, bypassing the RPCs (as an admin or
--     a future function might). A live completion for an occurrence blocks a
--     second one (23505, naming the index); an undone one does not.
--     Control: the first insert, and the insert after undo, succeed.
do $$
declare
  hh uuid := current_setting('t.hh')::uuid;
  v_vac uuid := current_setting('t.vac')::uuid;
  v_first uuid := gen_random_uuid();
  v_ctrl text; v_dup text; v_after text;
begin
  begin
    insert into public.chore_completions (id, chore_id, household_id, completed_by, credited_to, due_on, effort)
      values (v_first, v_vac, hh, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', date '2100-01-01', 1);
    v_ctrl := 'ok';
  exception when others then v_ctrl := sqlstate || ' ' || sqlerrm; end;
  begin
    insert into public.chore_completions (chore_id, household_id, completed_by, credited_to, due_on, effort)
      values (v_vac, hh, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', date '2100-01-01', 1);
    v_dup := 'ACCEPTED';
  exception when others then v_dup := sqlstate || ' ' || sqlerrm; end;
  update public.chore_completions set undone_at = now() where id = v_first;
  begin
    insert into public.chore_completions (chore_id, household_id, completed_by, credited_to, due_on, effort)
      values (v_vac, hh, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', date '2100-01-01', 1);
    v_after := 'ok';
  exception when others then v_after := sqlstate || ' ' || sqlerrm; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v_ctrl = 'ok' and v_dup like '23505%chore_completions_one_per_occurrence%' and v_after = 'ok'
         then E'\nPASS 39 unique index rejects a duplicate live completion; allows one after undo'
         else E'\nFAIL 39 first=' || v_ctrl || ' duplicate=' || v_dup || ' after undo=' || v_after end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 39 error: ' || sqlerrm, true);
end $$;

-- 40: COMPONENT test of the table check: a fixed chore must have an assignee.
do $$
declare v text;
begin
  begin
    insert into public.chores (household_id, name, effort, fixed, assignee, created_by)
      values (current_setting('t.hh')::uuid, 'Fixed nobody', 1, true, null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    v := 'ACCEPTED';
  exception when others then v := sqlstate; end;
  perform set_config('t.report', current_setting('t.report') ||
    case when v = '23514' then E'\nPASS 40 table check: a fixed chore without an assignee is rejected'
         else E'\nFAIL 40 got: ' || v end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 40 error: ' || sqlerrm, true);
end $$;

-- 41: Realtime publishes only tables whose DELETE payload (the primary key)
--     leaks nothing: chores, chore_completions, grocery_items (bare uuid
--     keys). Never the member/rotation tables, households (invite code),
--     profiles or join_attempts.
do $$
declare n_ok int; n_bad int;
begin
  select count(*) into n_ok from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename in ('chores', 'chore_completions', 'grocery_items');
  select count(*) into n_bad from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename in ('profiles', 'households', 'household_members', 'join_attempts', 'chore_rotation');
  perform set_config('t.report', current_setting('t.report') ||
    case when n_ok = 3 and n_bad = 0
         then E'\nPASS 41 realtime: chores, chore_completions, grocery_items published; no key-leaking table is'
         else E'\nFAIL 41 published wanted=' || n_ok || '/3 unwanted=' || n_bad end, true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 41 error: ' || sqlerrm, true);
end $$;

-- ---------------------------------------------------------------- report
-- Raises on purpose: shows the report and rolls everything back.
do $$
declare
  v_report text := current_setting('t.report');
  v_pass int := (select count(*) from regexp_matches(v_report, E'\\nPASS', 'g'));
  v_fail int := (select count(*) from regexp_matches(v_report, E'\\nFAIL', 'g'));
begin
  raise exception E'RLS TEST REPORT: % passed, % failed (everything rolled back)%',
    v_pass, v_fail, v_report;
end $$;

rollback;
