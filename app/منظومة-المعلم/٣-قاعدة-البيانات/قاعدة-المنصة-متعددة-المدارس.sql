-- =====================================================================
--  منظومة المعلم — قاعدة بيانات المنصّة متعددة المدارس (Multi-Tenant)
--  الأمان: Supabase Auth + Row Level Security (RLS) على كل جدول
--  نفّذها في مشروع Supabase جديد (SQL Editor) دفعة واحدة
-- =====================================================================
create extension if not exists pgcrypto;

-- ---------- 1) الأدوار ----------
do $$ begin
  create type app_role as enum ('super_admin','school_manager','teacher','assistant','guardian');
exception when duplicate_object then null; end $$;

-- ---------- 2) المدارس (كل مدرسة = مستأجر مستقل) ----------
create table if not exists public.schools (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  edu_admin   text,
  city        text,
  logo        text,
  owner_id    uuid not null references auth.users(id) on delete restrict,
  created_at  timestamptz not null default now()
);

-- ---------- 3) ملفات المستخدمين (مرتبطة بحساب Auth) ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  email       text,
  phone       text,
  created_at  timestamptz not null default now()
);

-- ---------- 4) عضويات المدرسة (مستخدم ← مدرسة ← دور) ----------
create table if not exists public.memberships (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references public.schools(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        app_role not null default 'teacher',
  status      text not null default 'active',        -- active | pending | disabled
  created_at  timestamptz not null default now(),
  unique(school_id, user_id)
);

-- ---------- 5) الاشتراكات (على مستوى المدرسة والمعلّم — للمستقبل) ----------
create table if not exists public.subscriptions (
  id            uuid primary key default gen_random_uuid(),
  scope         text not null,                       -- 'school' | 'teacher'
  school_id     uuid references public.schools(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete cascade,
  plan          text not null default 'free',        -- free | basic | pro | school
  status        text not null default 'active',      -- active | trialing | past_due | canceled
  seats         int  not null default 1,
  started_at    timestamptz not null default now(),
  expires_at    timestamptz,
  meta          jsonb not null default '{}'::jsonb
);

-- ---------- 6) الجداول التشغيلية (كل صف يحمل school_id + owner) ----------
-- نستخدم عمود data jsonb مرنًا حتى لا نحتاج ترحيلًا عند أي تحديث مستقبلي (لا فقد بيانات)
create table if not exists public.classes      ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), name text, grade text, section text, year text, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.subjects     ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), name text, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.students     ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), class_id uuid references public.classes(id) on delete set null, name text, number text, national_id text, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.schedule     ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.lessons      ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), class_id uuid, subject_id uuid, date date, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.interactions ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), student_id uuid, type text, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.assessments  ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), class_id uuid, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.referrals    ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), student_id uuid, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.curriculum   ( id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), subject_id uuid, week_no int, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );
create table if not exists public.periodic_exams(id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade, owner_id uuid not null references auth.users(id), student_id uuid, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now() );

create index if not exists idx_students_school on public.students(school_id);
create index if not exists idx_lessons_owner   on public.lessons(owner_id, date);
create index if not exists idx_members_user    on public.memberships(user_id);

-- ---------- 7) دوال مساعدة للأمان (SECURITY DEFINER لتفادي التكرار اللانهائي في RLS) ----------
create or replace function public.my_school_ids()
returns setof uuid language sql stable security definer set search_path=public as $$
  select school_id from public.memberships where user_id = auth.uid() and status='active'
$$;

create or replace function public.is_school_manager(p_school uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.memberships
    where user_id=auth.uid() and school_id=p_school and status='active'
      and role in ('school_manager','super_admin'))
$$;

-- ---------- 8) تفعيل RLS على كل الجداول ----------
alter table public.schools       enable row level security;
alter table public.profiles      enable row level security;
alter table public.memberships   enable row level security;
alter table public.subscriptions enable row level security;
alter table public.classes       enable row level security;
alter table public.subjects      enable row level security;
alter table public.students      enable row level security;
alter table public.schedule      enable row level security;
alter table public.lessons       enable row level security;
alter table public.interactions  enable row level security;
alter table public.assessments   enable row level security;
alter table public.referrals     enable row level security;
alter table public.curriculum    enable row level security;
alter table public.periodic_exams enable row level security;

-- ---------- 9) السياسات ----------
-- profiles: كل مستخدم يرى ويعدّل ملفه فقط
drop policy if exists p_profiles on public.profiles;
create policy p_profiles on public.profiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- schools: الأعضاء يرونها، والمدير/المالك يعدّلها
drop policy if exists p_schools_sel on public.schools;
create policy p_schools_sel on public.schools for select to authenticated
  using (id in (select public.my_school_ids()));
drop policy if exists p_schools_mod on public.schools;
create policy p_schools_mod on public.schools for all to authenticated
  using (owner_id = auth.uid() or public.is_school_manager(id))
  with check (owner_id = auth.uid() or public.is_school_manager(id));

-- memberships: الأعضاء يرون عضويات مدرستهم، المدير يديرها
drop policy if exists p_members_sel on public.memberships;
create policy p_members_sel on public.memberships for select to authenticated
  using (school_id in (select public.my_school_ids()));
drop policy if exists p_members_mod on public.memberships;
create policy p_members_mod on public.memberships for all to authenticated
  using (public.is_school_manager(school_id)) with check (public.is_school_manager(school_id));

-- subscriptions: يراها أعضاء المدرسة، يعدّلها المدير فقط
drop policy if exists p_subs on public.subscriptions;
create policy p_subs on public.subscriptions for all to authenticated
  using (school_id in (select public.my_school_ids()))
  with check (public.is_school_manager(school_id));

-- الجداول التشغيلية: المعلّم يرى/يعدّل ما يملكه، والمدير يرى/يعدّل كل مدرسته
-- (نطبّق نفس النمط على كل جدول عبر دالة توليد)
do $$
declare t text;
begin
  foreach t in array array['classes','subjects','students','schedule','lessons','interactions','assessments','referrals','curriculum','periodic_exams']
  loop
    execute format('drop policy if exists p_%1$s_sel on public.%1$s;', t);
    execute format($f$create policy p_%1$s_sel on public.%1$s for select to authenticated
        using (school_id in (select public.my_school_ids()));$f$, t);
    execute format('drop policy if exists p_%1$s_mod on public.%1$s;', t);
    execute format($f$create policy p_%1$s_mod on public.%1$s for all to authenticated
        using (owner_id = auth.uid() or public.is_school_manager(school_id))
        with check (owner_id = auth.uid() or public.is_school_manager(school_id));$f$, t);
  end loop;
end $$;

-- ---------- 10) تحديث updated_at تلقائيًا ----------
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
do $$
declare t text;
begin
  foreach t in array array['classes','subjects','students','schedule','lessons','interactions','assessments','referrals','curriculum','periodic_exams']
  loop
    execute format('drop trigger if exists trg_%1$s_touch on public.%1$s;', t);
    execute format('create trigger trg_%1$s_touch before update on public.%1$s for each row execute function public.touch_updated_at();', t);
  end loop;
end $$;

-- ---------- 11) إنشاء ملف المستخدم تلقائيًا عند التسجيل ----------
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists trg_new_user on auth.users;
create trigger trg_new_user after insert on auth.users for each row execute function public.handle_new_user();
