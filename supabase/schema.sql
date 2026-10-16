-- Aakshi birthday site: shared message wall + quiz leaderboard.
--
-- Run this once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- It is safe to run again; every statement is idempotent.
--
-- Access model (the site has no logins, every visitor uses the public "anon" role):
--   anon can SELECT both tables and INSERT new messages (only name + message).
--   anon can NOT insert quiz scores directly; it calls submit_quiz_attempt(name, answers),
--   which grades the answers in the database and stores the score.
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

-- Column-level INSERT: visitors cannot choose id or created_at.
grant insert (name, message) on table public.birthday_messages to anon;
-- No INSERT on quiz_scores at all: scores are only written by submit_quiz_attempt() below,
-- which grades the visitor's answers itself. Nobody can send a score directly.

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

-- (removed in favour of server-side grading; dropped so re-running cleans up older setups)
drop policy if exists "Public can add quiz scores" on public.quiz_scores;

-- No UPDATE or DELETE policies exist and no UPDATE/DELETE privileges are granted,
-- so anonymous visitors cannot change or remove existing rows.

-- ---------------------------------------------------------------------------
-- Server-side quiz grading
-- The page sends the option index (0-3) picked for each of the 4 questions; the database
-- compares them with this answer key and stores the resulting score.
-- Keep the key in the same order as QUESTIONS in index.html.
-- ---------------------------------------------------------------------------

create table if not exists public.quiz_answer_key (
  question_no     integer primary key check (question_no between 1 and 4),
  correct_option  integer not null check (correct_option between 0 and 3)
);
insert into public.quiz_answer_key (question_no, correct_option) values
  (1, 3),  -- Sanrio character: Kuromi
  (2, 0),  -- food: White sauce pasta
  (3, 1),  -- COD gun: QQ9
  (4, 0)   -- song: Vienna
on conflict (question_no) do update set correct_option = excluded.correct_option;
revoke all on table public.quiz_answer_key from anon, authenticated;
alter table public.quiz_answer_key enable row level security;  -- no policies: only the function reads it

create or replace function public.submit_quiz_attempt(p_name text, p_answers integer[])
returns public.quiz_scores
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name  text := btrim(p_name);
  v_score integer;
  v_row   public.quiz_scores;
begin
  if v_name is null or v_name !~ '[^[:space:]]' or char_length(v_name) > 60 then
    raise exception 'name must be 1-60 characters' using errcode = '22023';
  end if;
  if p_answers is null or array_ndims(p_answers) <> 1 or cardinality(p_answers) <> 4
     or array_lower(p_answers, 1) <> 1 or array_position(p_answers, null) is not null then
    raise exception 'expected exactly 4 answers' using errcode = '22023';
  end if;
  if (select count(*) from public.quiz_answer_key) <> 4 then
    raise exception 'quiz answer key is not set up' using errcode = '55000';
  end if;

  select count(*) into v_score
  from public.quiz_answer_key k
  where p_answers[k.question_no] = k.correct_option;

  insert into public.quiz_scores (name, score, total_questions)
  values (v_name, v_score, 4)
  returning * into v_row;
  return v_row;
end;
$$;

revoke all on function public.submit_quiz_attempt(text, integer[]) from public, anon, authenticated;
grant execute on function public.submit_quiz_attempt(text, integer[]) to anon;

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
