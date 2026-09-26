-- Shared Spatial AI — Phase 1 schema stubs (Supabase / Postgres)
-- Apply manually when SCENE_STORE=supabase. Not required for local memory mode.

create extension if not exists "pgcrypto";

create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists scenes (
  scene_id text primary key,
  project_id uuid references projects (id) on delete set null,
  room_id text,
  version integer not null default 1,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists scene_objects (
  id text not null,
  scene_id text not null references scenes (scene_id) on delete cascade,
  type text not null,
  product_id text,
  asset_id text,
  movable boolean default true,
  transform jsonb not null,
  dimensions jsonb,
  primary key (scene_id, id)
);

create table if not exists products (
  product_id text primary key,
  name text not null,
  price numeric(12, 2) not null,
  currency text not null default 'USD',
  dimensions jsonb,
  asset_id text,
  tags text[],
  purchasable boolean default true,
  virtual_only boolean default false,
  category text
);

create table if not exists cart_items (
  id uuid primary key default gen_random_uuid(),
  scene_id text not null references scenes (scene_id) on delete cascade,
  product_id text not null references products (product_id),
  quantity integer not null default 1,
  created_at timestamptz not null default now()
);

-- Append-only operation log
create table if not exists scene_ops (
  id uuid primary key default gen_random_uuid(),
  scene_id text not null references scenes (scene_id) on delete cascade,
  op_id text,
  actor_id text,
  base_version integer not null,
  result_version integer not null,
  operations jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists scene_ops_scene_id_idx on scene_ops (scene_id, created_at);
