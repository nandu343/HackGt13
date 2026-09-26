-- Shared Spatial AI — Phase 5 auth, projects, realtime, soft-locks
-- Apply after 001_init.sql when using Supabase.
-- Local demos work without this (in-memory store + FastAPI WebSocket).

-- ---------------------------------------------------------------------------
-- Auth notes (configure in Supabase Dashboard; not pure SQL):
--   1. Authentication → Providers → Email: enable Magic Link
--   2. Authentication → Providers → Anonymous: enable for hackathon demo guests
--   3. Site URL: http://localhost:3000
--   4. Redirect URLs: http://localhost:3000/**
-- Clients: use anon key (NEXT_PUBLIC_SUPABASE_ANON_KEY). API uses service role.
-- ---------------------------------------------------------------------------

-- Project membership (each project owns one primary scene)
create table if not exists project_members (
  project_id uuid not null references projects (id) on delete cascade,
  user_id uuid not null,
  role text not null default 'editor' check (role in ('owner', 'editor', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create index if not exists project_members_user_idx on project_members (user_id);

-- Soft-lock columns on normalized scene_objects (payload JSON also carries lockedBy/lockedUntil)
alter table scene_objects
  add column if not exists locked_by text,
  add column if not exists locked_until timestamptz;

-- Optional presence mirror for debugging (primary presence is Realtime Presence / WS)
create table if not exists scene_presence (
  scene_id text not null references scenes (scene_id) on delete cascade,
  user_id text not null,
  display_name text not null,
  color text,
  selected_object_id text,
  last_seen_at timestamptz not null default now(),
  primary key (scene_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Realtime: enable replication for scenes (Dashboard → Database → Replication)
-- or via SQL (Supabase):
--   alter publication supabase_realtime add table scenes;
--   alter publication supabase_realtime add table scene_objects;
-- Client channel: `scene:{sceneId}` — subscribe to postgres_changes on scenes
-- where scene_id=eq.{sceneId}, plus Presence for cursors/selection.
-- ---------------------------------------------------------------------------

-- RLS sketches (enable when using anon client against Postgres directly)
alter table projects enable row level security;
alter table project_members enable row level security;
alter table scenes enable row level security;

-- Demo policies: members can read/write their project scenes
drop policy if exists projects_member_select on projects;
create policy projects_member_select on projects
  for select using (
    auth.uid() = owner_id
    or exists (
      select 1 from project_members m
      where m.project_id = projects.id and m.user_id = auth.uid()
    )
  );

drop policy if exists scenes_member_all on scenes;
create policy scenes_member_all on scenes
  for all using (
    project_id is null  -- seed / public demo scenes
    or exists (
      select 1 from project_members m
      where m.project_id = scenes.project_id and m.user_id = auth.uid()
    )
  )
  with check (
    project_id is null
    or exists (
      select 1 from project_members m
      where m.project_id = scenes.project_id and m.user_id = auth.uid()
    )
  );

-- Anonymous / magic-link path for the web app:
--   supabase.auth.signInAnonymously()
--   OR supabase.auth.signInWithOtp({ email })
-- Then create a project + scene row, store sceneId, join Realtime channel.
-- If SUPABASE_* env is missing, web should fall back to API:
--   GET /scene/{id} + WS /ws/scene/{id}
