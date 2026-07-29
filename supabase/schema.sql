-- Book Club Builder — database setup
--
-- Run this once in your Supabase project: Dashboard → SQL Editor → New query,
-- paste the whole file, then press Run. It creates every table, permission
-- rule, and piece of server logic the app needs.
--
-- Before running it, turn OFF "Confirm email" under
-- Authentication → Sign In / Providers → Email. The app never sends email, so
-- leaving that on would create teacher accounts that can never sign in.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One row per teacher, paired with the Supabase account that owns it.
-- The email address and password live in auth.users, managed by Supabase.
-- "username" is the teacher's display name, shown to students.
create table public.teachers (
  id          uuid primary key references auth.users (id) on delete cascade,
  username    text not null check (username ~ '^[A-Za-z0-9 ._''-]{3,30}$'),
  share_token text not null unique,
  created_at  timestamptz not null default now()
);

-- Display names are unique regardless of capitalisation, so two teachers
-- cannot show students the same name.
create unique index teachers_username_key on public.teachers (lower(username));

create table public.books (
  id       uuid primary key default gen_random_uuid(),
  teacher  uuid not null references public.teachers (id) on delete cascade,
  position integer not null check (position between 1 and 10),
  title    text not null check (char_length(title) between 1 and 120),
  blurb    text not null check (char_length(blurb) between 1 and 500),
  cover    text not null,
  unique (teacher, position)
);

create index books_teacher_idx on public.books (teacher);

-- "choices" is ordered: the first entry is the student's first choice.
create table public.submissions (
  id           uuid primary key default gen_random_uuid(),
  teacher      uuid not null references public.teachers (id) on delete cascade,
  first_name   text not null check (char_length(first_name) between 1 and 50),
  last_initial text not null check (last_initial ~ '^[A-Z]$'),
  student_key  text not null check (char_length(student_key) between 3 and 60),
  choices      uuid[] not null check (array_length(choices, 1) = 4),
  unique (teacher, student_key)
);

create index submissions_teacher_idx on public.submissions (teacher);

create table public.grouping_plans (
  id       uuid primary key default gen_random_uuid(),
  teacher  uuid not null unique references public.teachers (id) on delete cascade,
  settings jsonb not null,
  result   jsonb not null
);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- When someone signs up, create their teacher row and mint the secret token
-- that their student link is built from.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.teachers (id, username, share_token)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'username'), ''), 'Teacher'),
    replace(replace(encode(extensions.gen_random_bytes(30), 'base64'), '/', '_'), '+', '-')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- A teacher may rename themselves, but never reissue their own share token.
create function public.teachers_keep_share_token()
returns trigger
language plpgsql
as $$
begin
  new.id := old.id;
  new.share_token := old.share_token;
  new.created_at := old.created_at;
  return new;
end;
$$;

create trigger teachers_keep_share_token
  before update on public.teachers
  for each row execute function public.teachers_keep_share_token();

-- Once a single student has responded, the book list is frozen so every
-- ranking stays meaningful. Ten books is the hard ceiling.
create function public.books_guard()
returns trigger
language plpgsql
as $$
declare
  owner_id uuid;
begin
  if tg_op = 'DELETE' then
    owner_id := old.teacher;
  else
    owner_id := new.teacher;
  end if;

  if exists (select 1 from public.submissions where teacher = owner_id) then
    raise exception 'Clear student responses before changing the book list.';
  end if;

  if tg_op = 'INSERT'
     and (select count(*) from public.books where teacher = owner_id) >= 10 then
    raise exception 'A book club can have only ten books.';
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
-- Row level security
--
-- Teachers can only ever see and touch their own rows. Student responses and
-- saved groups are read-only from the browser; they are written exclusively by
-- the functions further down, which do their own validation.
-- ---------------------------------------------------------------------------

alter table public.teachers enable row level security;
alter table public.books enable row level security;
alter table public.submissions enable row level security;
alter table public.grouping_plans enable row level security;

create policy teachers_select_own on public.teachers
  for select to authenticated using (id = (select auth.uid()));
create policy teachers_update_own on public.teachers
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

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
-- public to read. Writing is limited to the folder named after the teacher.
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
-- the caller already holds the teacher's secret share token.
-- ---------------------------------------------------------------------------

create function public.student_view(token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  owner  public.teachers%rowtype;
  titles jsonb;
begin
  if token is null or char_length(token) < 24 then
    raise exception 'This book club link is not valid.';
  end if;

  select * into owner from public.teachers where share_token = token;
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
   where b.teacher = owner.id;

  if titles is null or jsonb_array_length(titles) <> 10 then
    raise exception 'This book club is not ready yet.';
  end if;

  return jsonb_build_object('teacher', owner.username, 'books', titles);
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
  owner_id      uuid;
  clean_first   text;
  clean_initial text;
  key           text;
  matching      integer;
begin
  if token is null or char_length(token) < 24 then
    raise exception 'This book club link is not valid.';
  end if;

  select id into owner_id from public.teachers where share_token = token;
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

  if coalesce(array_length(book_choices, 1), 0) <> 4
     or (select count(distinct choice) from unnest(book_choices) as choice) <> 4 then
    raise exception 'Choose four different books.';
  end if;

  select count(*) into matching
    from public.books
   where id = any (book_choices) and teacher = owner_id;

  if matching <> 4 then
    raise exception 'One or more selected books are not available.';
  end if;

  -- Re-submitting under the same name replaces the earlier ranking.
  key := lower(clean_first) || '|' || lower(clean_initial);

  insert into public.submissions (teacher, first_name, last_initial, student_key, choices)
  values (
    owner_id,
    upper(left(clean_first, 1)) || substr(clean_first, 2),
    clean_initial,
    key,
    book_choices
  )
  on conflict (teacher, student_key) do update
    set first_name   = excluded.first_name,
        last_initial = excluded.last_initial,
        choices      = excluded.choices;

  -- Any saved grouping is now out of date.
  delete from public.grouping_plans where teacher = owner_id;

  return jsonb_build_object('success', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Teacher actions
-- ---------------------------------------------------------------------------

create function public.clear_responses()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  owner_id uuid := auth.uid();
begin
  if owner_id is null then
    raise exception 'Please sign in again.';
  end if;

  delete from public.submissions where teacher = owner_id;
  delete from public.grouping_plans where teacher = owner_id;
end;
$$;

-- Fills the class with make-believe responses so a teacher can try out
-- grouping before their students have answered.
create function public.add_random_responses(response_count integer)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  owner_id uuid := auth.uid();
  names    text[] := array[
    'Avery', 'Blake', 'Casey', 'Dakota', 'Emerson', 'Finley', 'Gray', 'Harper',
    'Indigo', 'Jules', 'Kai', 'Logan', 'Morgan', 'Nico', 'Oakley', 'Parker',
    'Quinn', 'Riley', 'Sage', 'Taylor'
  ];
  book_ids uuid[];
  picked   uuid[];
  made     integer;
begin
  if owner_id is null then
    raise exception 'Please sign in again.';
  end if;

  if response_count is null or response_count < 1 or response_count > 100 then
    raise exception 'Choose a number from 1 to 100.';
  end if;

  select array_agg(id order by position) into book_ids
    from public.books where teacher = owner_id;

  if coalesce(array_length(book_ids, 1), 0) <> 10 then
    raise exception 'Add all ten books before creating test responses.';
  end if;

  for made in 1 .. response_count loop
    with shuffled as (
      select id, row_number() over (order by random()) as slot
        from unnest(book_ids) as id
    )
    select array_agg(id order by slot) into picked from shuffled where slot <= 4;

    insert into public.submissions (teacher, first_name, last_initial, student_key, choices)
    values (
      owner_id,
      names[1 + floor(random() * array_length(names, 1))::integer] || ' (Test)',
      chr(65 + floor(random() * 26)::integer),
      'test-' || replace(gen_random_uuid()::text, '-', ''),
      picked
    );
  end loop;

  delete from public.grouping_plans where teacher = owner_id;
  return response_count;
end;
$$;

-- The grouping itself is worked out in the browser. This re-checks the whole
-- draft against the real data before saving it, so a tampered-with draft can
-- never be stored.
create function public.save_groups(plan_settings jsonb, plan_result jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  owner_id       uuid := auth.uid();
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
  if owner_id is null then
    raise exception 'Please sign in again.';
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

  -- Every one of the teacher's books needs a sensible group limit.
  for book_id in select id::text from public.books where teacher = owner_id loop
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
          where teacher = owner_id and id::text = one_group ->> 'bookId'
       )
       or jsonb_typeof(one_group -> 'members') <> 'array'
       or jsonb_array_length(one_group -> 'members') < minimum
       or jsonb_array_length(one_group -> 'members') > maximum then
      raise exception 'One or more groups do not meet the selected limits.';
    end if;

    for one_member in select value from jsonb_array_elements(one_group -> 'members') loop
      select choices into member_choices
        from public.submissions
       where teacher = owner_id and id::text = one_member ->> 'id';

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

  select count(*) into total_students from public.submissions where teacher = owner_id;

  if coalesce(array_length(assigned, 1), 0) <> total_students
     or (select count(distinct student) from unnest(assigned) as student) <> total_students
     or exists (
          select 1 from unnest(assigned) as student
           where not exists (
             select 1 from public.submissions
              where teacher = owner_id and id::text = student
           )
        ) then
    raise exception 'Every student must appear exactly once in the grouping draft.';
  end if;

  insert into public.grouping_plans (teacher, settings, result)
  values (owner_id, plan_settings, plan_result)
  on conflict (teacher) do update
    set settings = excluded.settings,
        result   = excluded.result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Who may call what
-- ---------------------------------------------------------------------------

revoke all on function public.student_view(text) from public;
revoke all on function public.student_submit(text, text, text, uuid[]) from public;
revoke all on function public.clear_responses() from public;
revoke all on function public.add_random_responses(integer) from public;
revoke all on function public.save_groups(jsonb, jsonb) from public;

grant execute on function public.student_view(text) to anon, authenticated;
grant execute on function public.student_submit(text, text, text, uuid[]) to anon, authenticated;
grant execute on function public.clear_responses() to authenticated;
grant execute on function public.add_random_responses(integer) to authenticated;
grant execute on function public.save_groups(jsonb, jsonb) to authenticated;
