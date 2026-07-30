-- Group Readers — database setup
--
-- Run this once in your Supabase project: Dashboard → SQL Editor → New query,
-- paste the whole file, then press Run. It creates every table, permission
-- rule, and piece of server logic the app needs.
--
-- Before running it, turn OFF "Confirm email" under
-- Authentication → Sign In / Providers → Email. The app never sends email, so
-- leaving that on would create teacher accounts that can never sign in.
--
-- ---------------------------------------------------------------------------
-- Starting over
--
-- This file only works on an empty project. If you have run an earlier version
-- of it, uncomment the block below to throw away everything first. That deletes
-- all books, student responses, and saved groups. Teacher accounts themselves
-- live in Authentication → Users and are not touched.
-- ---------------------------------------------------------------------------

-- drop table if exists public.grouping_plans, public.submissions, public.books,
--   public.book_lists, public.teachers cascade;
-- drop function if exists public.handle_new_user() cascade;
-- drop function if exists public.teachers_keep_identity() cascade;
-- drop function if exists public.teachers_keep_share_token() cascade;
-- drop function if exists public.book_lists_guard() cascade;
-- drop function if exists public.books_guard() cascade;
-- drop function if exists public.new_share_token() cascade;
-- drop function if exists public.student_view(text);
-- drop function if exists public.student_submit(text, text, text, uuid[]);
-- drop function if exists public.remove_book(uuid);
-- drop function if exists public.clear_responses();
-- drop function if exists public.clear_responses(uuid);
-- drop function if exists public.add_random_responses(integer);
-- drop function if exists public.add_random_responses(uuid, integer);
-- drop function if exists public.save_groups(jsonb, jsonb);
-- drop function if exists public.save_groups(uuid, jsonb, jsonb);
-- drop policy if exists covers_public_read on storage.objects;
-- drop policy if exists covers_insert_own on storage.objects;
-- drop policy if exists covers_update_own on storage.objects;
-- drop policy if exists covers_delete_own on storage.objects;

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One row per teacher, paired with the Supabase account that owns it.
-- The email address and password live in auth.users, managed by Supabase.
-- "username" is the teacher's display name, shown to students.
create table public.teachers (
  id         uuid primary key references auth.users (id) on delete cascade,
  username   text not null check (username ~ '^[A-Za-z0-9 ._''-]{3,30}$'),
  created_at timestamptz not null default now()
);

-- Display names are unique regardless of capitalisation, so two teachers
-- cannot show students the same name.
create unique index teachers_username_key on public.teachers (lower(username));

-- A teacher keeps one book list per group of students they teach — say one for
-- each class period. Every list has its own books, its own student link, its own
-- responses, and its own saved groups, so the same books can be offered to
-- several classes without their answers mixing together.
create table public.book_lists (
  id           uuid primary key default gen_random_uuid(),
  teacher      uuid not null references public.teachers (id) on delete cascade,
  name         text not null check (char_length(btrim(name)) between 1 and 60),
  -- A private note for the teacher's own dashboard. Students never see it.
  description  text not null default '' check (char_length(description) <= 300),
  -- How many books each student ranks on this list's student page. The teacher
  -- chooses it per list, and the list's link stays shut until the list holds at
  -- least this many books.
  ranked_books integer not null default 4 check (ranked_books between 2 and 10),
  share_token  text not null unique,
  created_at   timestamptz not null default now(),
  -- Redundant on its own, but it lets the tables below point at the pair
  -- (list, teacher) and so guarantees their "teacher" column always agrees
  -- with the list's real owner.
  unique (id, teacher)
);

create index book_lists_teacher_idx on public.book_lists (teacher);

-- Every table below repeats the owning teacher next to the list. That keeps the
-- permission rules a plain "teacher = the signed-in account", and keeps cover
-- images filed under one folder per teacher.
--
-- A list holds however many books its teacher chooses, numbered 1 upwards with
-- no gaps. Removing a book therefore renumbers the ones after it, which briefly
-- reuses a position that is still taken, so the numbering is checked at the end
-- of the change rather than row by row.
create table public.books (
  id       uuid primary key default gen_random_uuid(),
  teacher  uuid not null,
  list     uuid not null,
  position integer not null check (position between 1 and 30),
  title    text not null check (char_length(title) between 1 and 120),
  blurb    text not null check (char_length(blurb) between 1 and 500),
  cover    text not null,
  unique (list, position) deferrable initially immediate,
  foreign key (list, teacher) references public.book_lists (id, teacher) on delete cascade
);

create index books_list_idx on public.books (list);

-- "choices" is ordered: the first entry is the student's first choice. How many
-- entries there are is the owning list's "ranked_books", which a check
-- constraint here cannot reach; student_submit below holds them to it.
create table public.submissions (
  id           uuid primary key default gen_random_uuid(),
  teacher      uuid not null,
  list         uuid not null,
  first_name   text not null check (char_length(first_name) between 1 and 50),
  last_initial text not null check (last_initial ~ '^[A-Z]$'),
  student_key  text not null check (char_length(student_key) between 3 and 60),
  choices      uuid[] not null check (array_length(choices, 1) between 2 and 10),
  unique (list, student_key),
  foreign key (list, teacher) references public.book_lists (id, teacher) on delete cascade
);

create index submissions_list_idx on public.submissions (list);

create table public.grouping_plans (
  id       uuid primary key default gen_random_uuid(),
  teacher  uuid not null,
  list     uuid not null unique,
  settings jsonb not null,
  result   jsonb not null,
  foreign key (list, teacher) references public.book_lists (id, teacher) on delete cascade
);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- The secret that a student link is built from. Long and random enough that a
-- link cannot be guessed, and safe to paste into a URL.
create function public.new_share_token()
returns text
language sql
volatile
set search_path = public, extensions
as $$
  select replace(replace(encode(extensions.gen_random_bytes(30), 'base64'), '/', '_'), '+', '-');
$$;

-- When someone signs up, create their teacher row along with a first book list
-- so they have somewhere to start.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.teachers (id, username)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'username'), ''), 'Teacher')
  );

  insert into public.book_lists (teacher, name) values (new.id, 'My book list');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- A teacher may rename themselves, but nothing else about the row is theirs to
-- change.
create function public.teachers_keep_identity()
returns trigger
language plpgsql
as $$
begin
  new.id := old.id;
  new.created_at := old.created_at;
  return new;
end;
$$;

create trigger teachers_keep_identity
  before update on public.teachers
  for each row execute function public.teachers_keep_identity();

-- The share token is minted here rather than by the browser, so nobody can
-- choose their own link. Renaming a list is allowed; reissuing its link is not,
-- and neither is moving the goalposts under students who have already answered.
create function public.book_lists_guard()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if tg_op = 'INSERT' then
    new.teacher := coalesce(new.teacher, auth.uid());
    new.share_token := public.new_share_token();
    new.created_at := now();

    if (select count(*) from public.book_lists where teacher = new.teacher) >= 20 then
      raise exception 'You can keep up to 20 book lists. Delete one you no longer need.';
    end if;
  else
    new.id := old.id;
    new.teacher := old.teacher;
    new.share_token := old.share_token;
    new.created_at := old.created_at;

    if new.ranked_books <> old.ranked_books
       and exists (select 1 from public.submissions where list = old.id) then
      raise exception 'Clear student responses before changing how many books students rank.';
    end if;
  end if;

  return new;
end;
$$;

create trigger book_lists_guard
  before insert or update on public.book_lists
  for each row execute function public.book_lists_guard();

-- Once a single student has responded, that list's books are frozen so every
-- ranking stays meaningful. Thirty books is the hard ceiling.
create function public.books_guard()
returns trigger
language plpgsql
as $$
declare
  list_id uuid;
begin
  if tg_op = 'DELETE' then
    list_id := old.list;
  else
    list_id := new.list;
  end if;

  if exists (select 1 from public.submissions where list = list_id) then
    raise exception 'Clear student responses before changing the book list.';
  end if;

  if tg_op = 'INSERT'
     and (select count(*) from public.books where list = list_id) >= 30 then
    raise exception 'A book list can hold up to thirty books.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger books_guard
  before insert or update or delete on public.books
  for each row execute function public.books_guard();

-- ---------------------------------------------------------------------------
-- Table privileges
--
-- The rules below narrow a signed-in teacher down to their own rows, but
-- Postgres first has to be told that signed-in teachers may touch the table at
-- all. Without these grants every query fails with "permission denied for
-- table ...". Signed-out visitors get nothing here; the student page reaches
-- the data only through the functions further down.
-- ---------------------------------------------------------------------------

revoke all on public.teachers, public.book_lists, public.books,
  public.submissions, public.grouping_plans from anon, authenticated;

grant select, update on public.teachers to authenticated;
grant select, insert, update, delete on public.book_lists to authenticated;
grant select, insert, update, delete on public.books to authenticated;
grant select on public.submissions to authenticated;
grant select on public.grouping_plans to authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
--
-- Teachers can only ever see and touch their own rows. Student responses and
-- saved groups are read-only from the browser; they are written exclusively by
-- the functions further down, which do their own validation.
-- ---------------------------------------------------------------------------

alter table public.teachers enable row level security;
alter table public.book_lists enable row level security;
alter table public.books enable row level security;
alter table public.submissions enable row level security;
alter table public.grouping_plans enable row level security;

create policy teachers_select_own on public.teachers
  for select to authenticated using (id = (select auth.uid()));
create policy teachers_update_own on public.teachers
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy book_lists_select_own on public.book_lists
  for select to authenticated using (teacher = (select auth.uid()));
create policy book_lists_insert_own on public.book_lists
  for insert to authenticated with check (teacher = (select auth.uid()));
create policy book_lists_update_own on public.book_lists
  for update to authenticated
  using (teacher = (select auth.uid())) with check (teacher = (select auth.uid()));
create policy book_lists_delete_own on public.book_lists
  for delete to authenticated using (teacher = (select auth.uid()));

create policy books_select_own on public.books
  for select to authenticated using (teacher = (select auth.uid()));
create policy books_insert_own on public.books
  for insert to authenticated with check (teacher = (select auth.uid()));
create policy books_update_own on public.books
  for update to authenticated
  using (teacher = (select auth.uid())) with check (teacher = (select auth.uid()));
create policy books_delete_own on public.books
  for delete to authenticated using (teacher = (select auth.uid()));

create policy submissions_select_own on public.submissions
  for select to authenticated using (teacher = (select auth.uid()));

create policy grouping_plans_select_own on public.grouping_plans
  for select to authenticated using (teacher = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Cover image storage
--
-- Covers must load on the student page, which has no account, so the bucket is
-- public to read. Writing is limited to the folder named after the teacher, so
-- the same folder holds the covers for all of that teacher's book lists.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('covers', 'covers', true)
on conflict (id) do update set public = true;

create policy covers_public_read on storage.objects
  for select using (bucket_id = 'covers');

create policy covers_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'covers' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy covers_update_own on storage.objects
  for update to authenticated
  using (bucket_id = 'covers' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy covers_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'covers' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- The student link
--
-- Both functions are reachable without an account. They reveal nothing unless
-- the caller already holds the secret token of one book list, and they only
-- ever touch that one list.
-- ---------------------------------------------------------------------------

create function public.student_view(token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  list_id    uuid;
  list_name  text;
  owner_name text;
  wanted     integer;
  titles     jsonb;
begin
  if token is null or char_length(token) < 24 then
    raise exception 'This book club link is not valid.';
  end if;

  select lists.id, lists.name, teacher.username, lists.ranked_books
    into list_id, list_name, owner_name, wanted
    from public.book_lists lists
    join public.teachers teacher on teacher.id = lists.teacher
   where lists.share_token = token;
  if not found then
    raise exception 'This book club link is not valid.';
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'id', b.id,
             'position', b.position,
             'title', b.title,
             'blurb', b.blurb,
             'cover', b.cover
           ) order by b.position
         )
    into titles
    from public.books b
   where b.list = list_id;

  -- A student ranks as many books as the teacher asked for, so a list holding
  -- fewer than that has nothing to offer them yet.
  if titles is null or jsonb_array_length(titles) < wanted then
    raise exception 'This book club is not ready yet.';
  end if;

  -- The list name goes back with the books so a student can see at a glance
  -- that the link they opened is the one meant for their class.
  return jsonb_build_object('teacher', owner_name, 'name', list_name, 'rankedBooks', wanted, 'books', titles);
end;
$$;

create function public.student_submit(
  token text,
  student_first_name text,
  student_last_initial text,
  book_choices uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  list_id       uuid;
  owner_id      uuid;
  clean_first   text;
  clean_initial text;
  key           text;
  wanted        integer;
  matching      integer;
begin
  if token is null or char_length(token) < 24 then
    raise exception 'This book club link is not valid.';
  end if;

  select id, teacher, ranked_books into list_id, owner_id, wanted
    from public.book_lists where share_token = token;
  if not found then
    raise exception 'This book club link is not valid.';
  end if;

  clean_first := regexp_replace(btrim(coalesce(student_first_name, '')), '\s+', ' ', 'g');
  clean_initial := upper(left(btrim(coalesce(student_last_initial, '')), 1));

  if clean_first !~ '^[A-Za-z][A-Za-z ''-]{0,48}[A-Za-z]$' and clean_first !~ '^[A-Za-z]$' then
    raise exception 'Enter a valid first name.';
  end if;

  if clean_initial !~ '^[A-Z]$' then
    raise exception 'Enter one letter for the last initial.';
  end if;

  if coalesce(array_length(book_choices, 1), 0) <> wanted
     or (select count(distinct choice) from unnest(book_choices) as choice) <> wanted then
    raise exception 'Choose % different books.', wanted;
  end if;

  select count(*) into matching
    from public.books
   where id = any (book_choices) and list = list_id;

  if matching <> wanted then
    raise exception 'One or more selected books are not available.';
  end if;

  -- Re-submitting under the same name replaces the earlier ranking.
  key := lower(clean_first) || '|' || lower(clean_initial);

  insert into public.submissions (teacher, list, first_name, last_initial, student_key, choices)
  values (
    owner_id,
    list_id,
    upper(left(clean_first, 1)) || substr(clean_first, 2),
    clean_initial,
    key,
    book_choices
  )
  on conflict (list, student_key) do update
    set first_name   = excluded.first_name,
        last_initial = excluded.last_initial,
        choices      = excluded.choices;

  -- Any saved grouping for this list is now out of date.
  delete from public.grouping_plans where list = list_id;

  return jsonb_build_object('success', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Teacher actions
--
-- Each one names the book list it should act on, and each one checks that the
-- signed-in teacher really owns that list before touching anything.
-- ---------------------------------------------------------------------------

-- Takes one book off a list and closes the gap it leaves, so the remaining books
-- keep their numbering running 1, 2, 3 upwards. Deleting the row and shifting
-- the rest has to happen together, which is why it is one function rather than
-- two calls from the browser. The cover image is thrown away by the browser
-- afterwards, since only it can reach the storage bucket.
create function public.remove_book(target_book uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  list_id  uuid;
  gone     integer;
begin
  select books.list, books.position into list_id, gone
    from public.books books
    join public.book_lists lists on lists.id = books.list
   where books.id = target_book and lists.teacher = auth.uid();
  if not found then
    raise exception 'That book is not available.';
  end if;

  if exists (select 1 from public.submissions where list = list_id) then
    raise exception 'Clear student responses before changing the book list.';
  end if;

  -- Shifting each later book down one step passes through numbers that are
  -- still in use, so uniqueness is judged once the whole shift is finished.
  set constraints all deferred;

  delete from public.books where id = target_book;

  update public.books set position = position - 1
   where list = list_id and position > gone;
end;
$$;

create function public.clear_responses(target_list uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not exists (
       select 1 from public.book_lists
        where id = target_list and teacher = auth.uid()
     ) then
    raise exception 'That book list is not available.';
  end if;

  delete from public.submissions where list = target_list;
  delete from public.grouping_plans where list = target_list;
end;
$$;

-- Fills the list with make-believe responses so a teacher can try out grouping
-- before their students have answered.
create function public.add_random_responses(target_list uuid, response_count integer)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  owner_id uuid;
  names    text[] := array[
    'Avery', 'Blake', 'Casey', 'Dakota', 'Emerson', 'Finley', 'Gray', 'Harper',
    'Indigo', 'Jules', 'Kai', 'Logan', 'Morgan', 'Nico', 'Oakley', 'Parker',
    'Quinn', 'Riley', 'Sage', 'Taylor'
  ];
  book_ids uuid[];
  -- One appeal figure per book, in the same order as book_ids. A real class does
  -- not spread itself evenly over the shelf: a couple of books are the ones
  -- everybody wants and a couple are the ones nobody reaches for. Appeal is how
  -- much more or less likely a book is to be chosen than an average one, and it
  -- is drawn once per batch so every make-believe student in that batch agrees
  -- about which books are the popular ones.
  appeal   double precision[];
  picked   uuid[];
  wanted   integer;
  made     integer;
begin
  select teacher, ranked_books into owner_id, wanted from public.book_lists
   where id = target_list and teacher = auth.uid();
  if not found then
    raise exception 'That book list is not available.';
  end if;

  if response_count is null or response_count < 1 or response_count > 100 then
    raise exception 'Choose a number from 1 to 100.';
  end if;

  select array_agg(id order by position) into book_ids
    from public.books where list = target_list;

  if coalesce(array_length(book_ids, 1), 0) < wanted then
    raise exception 'Add at least % books before creating test responses.', wanted;
  end if;

  -- 2 ^ (a number from -1 to 1): half as likely as average at worst, twice as
  -- likely at best, with the middling books far commoner than either extreme.
  select array_agg(power(2.0, 2 * random() - 1) order by ordinality) into appeal
    from unnest(book_ids) with ordinality as b(id, ordinality);

  for made in 1 .. response_count loop
    -- Draws "wanted" books without repeats, each book's chance of coming out
    -- next set by its appeal. Raising a random number to the power of one over
    -- the appeal does that: a sought-after book lands nearer the top of the pile
    -- more often, so it is both picked more and ranked higher, while an unpopular
    -- one still shows up now and then.
    with shuffled as (
      select b.id, row_number() over (order by power(random(), 1.0 / b.appeal) desc) as slot
        from unnest(book_ids, appeal) as b(id, appeal)
    )
    select array_agg(id order by slot) into picked from shuffled where slot <= wanted;

    insert into public.submissions (teacher, list, first_name, last_initial, student_key, choices)
    values (
      owner_id,
      target_list,
      names[1 + floor(random() * array_length(names, 1))::integer] || ' (Test)',
      chr(65 + floor(random() * 26)::integer),
      'test-' || replace(gen_random_uuid()::text, '-', ''),
      picked
    );
  end loop;

  delete from public.grouping_plans where list = target_list;
  return response_count;
end;
$$;

-- The grouping itself is worked out in the browser. This re-checks the whole
-- draft against the real data before saving it, so a tampered-with draft can
-- never be stored.
create function public.save_groups(target_list uuid, plan_settings jsonb, plan_result jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  owner_id       uuid;
  minimum        integer;
  maximum        integer;
  book_limits    jsonb;
  book_id        text;
  limit_value    numeric;
  counted        record;
  one_group      jsonb;
  one_member     jsonb;
  member_choices uuid[];
  assigned       text[] := '{}';
  total_students integer;
begin
  select teacher into owner_id from public.book_lists
   where id = target_list and teacher = auth.uid();
  if not found then
    raise exception 'That book list is not available.';
  end if;

  if length(plan_settings::text) > 50000 or length(plan_result::text) > 200000 then
    raise exception 'The grouping draft is too large to save.';
  end if;

  if jsonb_typeof(plan_settings -> 'minimumSize') <> 'number'
     or jsonb_typeof(plan_settings -> 'maximumSize') <> 'number' then
    raise exception 'Choose valid minimum and maximum group sizes.';
  end if;

  minimum := (plan_settings ->> 'minimumSize')::numeric;
  maximum := (plan_settings ->> 'maximumSize')::numeric;
  if minimum < 2 or maximum > 12 or minimum > maximum then
    raise exception 'Choose valid minimum and maximum group sizes.';
  end if;

  book_limits := plan_settings -> 'bookLimits';
  if coalesce(plan_settings ->> 'strategy', '') not in ('overall', 'first', 'last')
     or jsonb_typeof(book_limits) <> 'object'
     or jsonb_typeof(plan_result -> 'groups') <> 'array'
     or jsonb_typeof(plan_result -> 'unplaced') <> 'array' then
    raise exception 'The grouping draft is not valid.';
  end if;

  -- Every one of the list's books needs a sensible group limit.
  for book_id in select id::text from public.books where list = target_list loop
    if book_limits ? book_id and jsonb_typeof(book_limits -> book_id) <> 'number' then
      raise exception 'Choose a valid maximum number of groups for each book.';
    end if;
    limit_value := coalesce((book_limits ->> book_id)::numeric, 0);
    if limit_value < 0 or limit_value > 5 or limit_value <> trunc(limit_value) then
      raise exception 'Choose a valid maximum number of groups for each book.';
    end if;
  end loop;

  -- No book may end up with more groups than the teacher allowed.
  for counted in
    select entry ->> 'bookId' as book_id, count(*) as total
      from jsonb_array_elements(plan_result -> 'groups') as entry
     group by 1
  loop
    if counted.book_id is null
       or coalesce((book_limits ->> counted.book_id)::numeric, 0) < counted.total then
      raise exception 'A book has more groups than its selected limit.';
    end if;
  end loop;

  for one_group in select value from jsonb_array_elements(plan_result -> 'groups') loop
    if not exists (
         select 1 from public.books
          where list = target_list and id::text = one_group ->> 'bookId'
       )
       or jsonb_typeof(one_group -> 'members') <> 'array'
       or jsonb_array_length(one_group -> 'members') < minimum
       or jsonb_array_length(one_group -> 'members') > maximum then
      raise exception 'One or more groups do not meet the selected limits.';
    end if;

    for one_member in select value from jsonb_array_elements(one_group -> 'members') loop
      select choices into member_choices
        from public.submissions
       where list = target_list and id::text = one_member ->> 'id';

      -- The claimed rank has to match where that book really sits in the
      -- student's own ranking.
      if not found
         or jsonb_typeof(one_member -> 'rank') <> 'number'
         or array_position(member_choices, (one_group ->> 'bookId')::uuid)
            is distinct from (one_member ->> 'rank')::integer then
        raise exception 'One or more student placements are not valid.';
      end if;

      assigned := assigned || (one_member ->> 'id');
    end loop;
  end loop;

  for one_member in select value from jsonb_array_elements(plan_result -> 'unplaced') loop
    assigned := assigned || (one_member ->> 'id');
  end loop;

  select count(*) into total_students from public.submissions where list = target_list;

  if coalesce(array_length(assigned, 1), 0) <> total_students
     or (select count(distinct student) from unnest(assigned) as student) <> total_students
     or exists (
          select 1 from unnest(assigned) as student
           where not exists (
             select 1 from public.submissions
              where list = target_list and id::text = student
           )
        ) then
    raise exception 'Every student must appear exactly once in the grouping draft.';
  end if;

  insert into public.grouping_plans (teacher, list, settings, result)
  values (owner_id, target_list, plan_settings, plan_result)
  on conflict (list) do update
    set settings = excluded.settings,
        result   = excluded.result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Who may call what
-- ---------------------------------------------------------------------------

revoke all on function public.new_share_token() from public;
revoke all on function public.student_view(text) from public;
revoke all on function public.student_submit(text, text, text, uuid[]) from public;
revoke all on function public.remove_book(uuid) from public;
revoke all on function public.clear_responses(uuid) from public;
revoke all on function public.add_random_responses(uuid, integer) from public;
revoke all on function public.save_groups(uuid, jsonb, jsonb) from public;

-- The book_lists trigger mints tokens as whoever is creating the list, so a
-- signed-in teacher has to be allowed to reach the generator itself.
grant execute on function public.new_share_token() to authenticated;

grant execute on function public.student_view(text) to anon, authenticated;
grant execute on function public.student_submit(text, text, text, uuid[]) to anon, authenticated;
grant execute on function public.remove_book(uuid) to authenticated;
grant execute on function public.clear_responses(uuid) to authenticated;
grant execute on function public.add_random_responses(uuid, integer) to authenticated;
grant execute on function public.save_groups(uuid, jsonb, jsonb) to authenticated;
