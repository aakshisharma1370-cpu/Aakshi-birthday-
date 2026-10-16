-- Aakshi birthday site: shared message wall + quiz leaderboard.
--
-- Run this once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- It is safe to run again; every statement is idempotent.
--
-- Access model (the site has no logins, every visitor uses the public "anon" role):
--   anon can SELECT both tables and INSERT new rows (only the user-facing columns).
--   anon can NOT UPDATE or DELETE anything. You can still edit/delete rows yourself
--   from the Table Editor, which runs with admin rights.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.birthday_messages (
  id          bigint generated always as identity primary key,
  name        text        not null,
  message     text        not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.quiz_scores (
  id               bigint generated always as identity primary key,
  name             text        not null,
  score            integer     not null,
  total_questions  integer     not null default 4,
  created_at       timestamptz not null default now()
);

-- Constraints are dropped and re-added so re-running this file applies any edits.
-- "~ '[^[:space:]]'" = must contain at least one non-whitespace character (so "   " or blank lines are rejected).
alter table public.birthday_messages drop constraint if exists birthday_messages_name_check;
alter table public.birthday_messages add  constraint birthday_messages_name_check
  check (char_length(name) <= 60 and name ~ '[^[:space:]]');
alter table public.birthday_messages drop constraint if exists birthday_messages_message_check;
alter table public.birthday_messages add  constraint birthday_messages_message_check
  check (char_length(message) <= 1000 and message ~ '[^[:space:]]');

alter table public.quiz_scores drop constraint if exists quiz_scores_name_check;
alter table public.quiz_scores add  constraint quiz_scores_name_check
  check (char_length(name) <= 60 and name ~ '[^[:space:]]');
alter table public.quiz_scores drop constraint if exists quiz_scores_score_check;
alter table public.quiz_scores add  constraint quiz_scores_score_check
  check (score between 0 and 4);
alter table public.quiz_scores drop constraint if exists quiz_scores_total_questions_check;
alter table public.quiz_scores add  constraint quiz_scores_total_questions_check
  check (total_questions = 4);

comment on table public.birthday_messages is 'Sticky notes on the birthday message wall. Public read + insert.';
comment on table public.quiz_scores is 'One row per completed quiz attempt. Public read + insert. Scores are browser-reported, not server-verified.';

-- The wall loads newest first; the leaderboard sorts by score desc, then earliest attempt.
create index if not exists birthday_messages_created_at_idx on public.birthday_messages (created_at desc);
create index if not exists quiz_scores_leaderboard_idx      on public.quiz_scores (score desc, created_at asc, id asc);

-- ---------------------------------------------------------------------------
-- Privileges: start from nothing, then grant only what the site needs.
-- (Supabase grants ALL on new public tables to anon/authenticated by default.)
-- ---------------------------------------------------------------------------

revoke all on table public.birthday_messages from anon, authenticated;
revoke all on table public.quiz_scores       from anon, authenticated;

grant select on table public.birthday_messages to anon;
grant select on table public.quiz_scores       to anon;

-- Column-level INSERT: visitors cannot choose id or created_at, so timestamps can't be back-dated
-- to jump the leaderboard tie-break.
grant insert (name, message)                on table public.birthday_messages to anon;
grant insert (name, score, total_questions) on table public.quiz_scores       to anon;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.birthday_messages enable row level security;
alter table public.quiz_scores       enable row level security;

drop policy if exists "Public can read birthday messages" on public.birthday_messages;
create policy "Public can read birthday messages"
  on public.birthday_messages for select
  to anon
  using (true);

drop policy if exists "Public can add birthday messages" on public.birthday_messages;
create policy "Public can add birthday messages"
  on public.birthday_messages for insert
  to anon
  with check (
    char_length(name) <= 60 and name ~ '[^[:space:]]'
    and char_length(message) <= 1000 and message ~ '[^[:space:]]'
  );

drop policy if exists "Public can read quiz scores" on public.quiz_scores;
create policy "Public can read quiz scores"
  on public.quiz_scores for select
  to anon
  using (true);

drop policy if exists "Public can add quiz scores" on public.quiz_scores;
create policy "Public can add quiz scores"
  on public.quiz_scores for insert
  to anon
  with check (
    char_length(name) <= 60 and name ~ '[^[:space:]]'
    and score between 0 and 4
    and total_questions = 4
  );

-- No UPDATE or DELETE policies exist and no UPDATE/DELETE privileges are granted,
-- so anonymous visitors cannot change or remove existing rows.

-- ---------------------------------------------------------------------------
-- Realtime: broadcast new rows so open pages update without a refresh.
-- Realtime still applies the SELECT policies above to each subscriber.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'birthday_messages'
  ) then
    alter publication supabase_realtime add table public.birthday_messages;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'quiz_scores'
  ) then
    alter publication supabase_realtime add table public.quiz_scores;
  end if;
end
$$;
