-- ============================================================
-- منظومة المعلم — أكواد Supabase (نسخة مضمونة)
-- تحذف كل نسخ الدوال القديمة مهما كانت بارامتراتها ثم تُنشئها
-- Supabase ← SQL Editor ← الصق الكل ثم Run
-- ============================================================

-- (0) حذف كل الدوال القديمة بأي توقيع (يحل خطأ cannot change return type نهائيًا)
DO $drop$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('guardian_publish','guardian_lookup','guardian_ack',
                        'guardian_ack_list','guardian_ack_delete','evidence_view')
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS '||r.sig||' CASCADE';
  END LOOP;
END
$drop$;

-- (1) جدول المزامنة الرئيسي
create table if not exists public.teacher_data (
  id text primary key, data jsonb, teacher text, updated_at timestamptz default now()
);
alter table public.teacher_data enable row level security;
drop policy if exists td_all on public.teacher_data;
create policy td_all on public.teacher_data for all to anon using (true) with check (true);

-- (2) جداول بوابة ولي الأمر
create table if not exists public.guardian_public (
  sync_id text primary key, payload jsonb, updated_at timestamptz default now()
);
alter table public.guardian_public enable row level security;
drop policy if exists gp_read on public.guardian_public;
create policy gp_read on public.guardian_public for select to anon using (true);
drop policy if exists gp_write on public.guardian_public;
create policy gp_write on public.guardian_public for all to anon using (true) with check (true);

create table if not exists public.guardian_acks (
  id uuid primary key default gen_random_uuid(),
  sync_id text, student_id text, lookup_id text, school_year text,
  accepted_at timestamptz default now()
);
alter table public.guardian_acks enable row level security;
drop policy if exists ga_all on public.guardian_acks;
create policy ga_all on public.guardian_acks for all to anon using (true) with check (true);

-- (3) الدوال
create function public.guardian_publish(p_sync_id text, p_payload jsonb)
returns void language plpgsql security definer set search_path=public as $f$
begin
  insert into public.guardian_public(sync_id,payload,updated_at)
  values (p_sync_id,p_payload,now())
  on conflict (sync_id) do update set payload=excluded.payload, updated_at=now();
end; $f$;
grant execute on function public.guardian_publish(text,jsonb) to anon;

create function public.guardian_lookup(p_sync_id text, p_lookup text)
returns jsonb language plpgsql security definer set search_path=public as $f$
declare v jsonb; begin
  select payload into v from public.guardian_public where sync_id=p_sync_id; return v;
end; $f$;
grant execute on function public.guardian_lookup(text,text) to anon;

create function public.guardian_ack(p_sync_id text, p_student_id text, p_lookup_id text, p_year text)
returns void language plpgsql security definer set search_path=public as $f$
begin
  insert into public.guardian_acks(sync_id,student_id,lookup_id,school_year)
  values (p_sync_id,p_student_id,p_lookup_id,p_year);
end; $f$;
grant execute on function public.guardian_ack(text,text,text,text) to anon;

create function public.guardian_ack_list(p_sync_id text)
returns setof public.guardian_acks language sql security definer set search_path=public as $f$
  select * from public.guardian_acks where sync_id=p_sync_id order by accepted_at desc;
$f$;
grant execute on function public.guardian_ack_list(text) to anon;

create function public.guardian_ack_delete(p_id uuid, p_sync_id text, p_student_id text, p_lookup_id text, p_year text)
returns void language plpgsql security definer set search_path=public as $f$
begin delete from public.guardian_acks where id=p_id; end; $f$;
grant execute on function public.guardian_ack_delete(uuid,text,text,text,text) to anon;

create function public.evidence_view(p_sync_id text, p_criterion_id text)
returns jsonb language plpgsql security definer set search_path=public as $f$
declare v_payload jsonb; v_crit jsonb; v_dom jsonb; v_evs jsonb;
begin
  select payload into v_payload from public.guardian_public where sync_id=p_sync_id;
  if v_payload is null then return null; end if;
  select c into v_crit from jsonb_array_elements(coalesce(v_payload->'criteria','[]'::jsonb)) c
    where c->>'id'=p_criterion_id limit 1;
  if v_crit is null then return null; end if;
  select d into v_dom from jsonb_array_elements(coalesce(v_payload->'domains','[]'::jsonb)) d
    where d->>'id'=(v_crit->>'domainId') limit 1;
  select coalesce(jsonb_agg(e),'[]'::jsonb) into v_evs
    from jsonb_array_elements(coalesce(v_payload->'evidences','[]'::jsonb)) e
    where e->>'criterionId'=p_criterion_id;
  return jsonb_build_object('criterion',v_crit,'domain',v_dom,'evidences',v_evs,'school',coalesce(v_payload->'school','{}'::jsonb));
end; $f$;
grant execute on function public.evidence_view(text,text) to anon;

-- (4) صندوق تخزين مرفقات الشواهد
insert into storage.buckets (id,name,public) values ('evidence','evidence',true)
on conflict (id) do update set public=true;
drop policy if exists ev_insert on storage.objects;
create policy ev_insert on storage.objects for insert to anon with check (bucket_id='evidence');
drop policy if exists ev_select on storage.objects;
create policy ev_select on storage.objects for select to anon using (bucket_id='evidence');
drop policy if exists ev_delete on storage.objects;
create policy ev_delete on storage.objects for delete to anon using (bucket_id='evidence');

-- تمّ. النتيجة المتوقعة: Success. No rows returned
