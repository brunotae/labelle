-- LA BELLE v3.2 — ETAPA 3: permissoes por funcionario, contas de parceiros, acerto de comissao, registro de auditoria
-- Supabase → SQL Editor → New query → colar TUDO → Run  (pode repetir sem problema)
-- Precisa ter rodado antes o labelle_v22.sql

------------------------------------------------------------
-- 1) EQUIPE: funcionario desativado perde o acesso + permissoes
------------------------------------------------------------
alter table public.labelle_staff add column if not exists perms jsonb;

create or replace function public.labelle_is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.labelle_staff
                 where lower(email) = lower(auth.jwt() ->> 'email') and coalesce(active, true));
$$;
create or replace function public.labelle_is_adm()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.labelle_staff
                 where lower(email) = lower(auth.jwt() ->> 'email') and role = 'ADM' and coalesce(active, true));
$$;
create or replace function public.labelle_me_name()
returns text language sql stable security definer set search_path = public as $$
  select name from public.labelle_staff where lower(email) = lower(auth.jwt() ->> 'email') and coalesce(active, true) limit 1;
$$;
-- permissoes: finance (ver valores), files (arquivos do paciente), export (backup)
-- padrao por cargo: ADM tudo · 코디네이터 finance+files · 통역사 files · 직원 files
create or replace function public.labelle_perm(p_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when s.role = 'ADM' then true
                when s.perms ? p_key and jsonb_typeof(s.perms -> p_key) = 'boolean' then (s.perms ->> p_key)::boolean
                else case p_key when 'finance' then s.role = '코디네이터' when 'files' then true else false end end
    from public.labelle_staff s
    where lower(s.email) = lower(auth.jwt() ->> 'email') and coalesce(s.active, true) limit 1), false);
$$;
-- alcance: 'all' = todos os pacientes · 'mine' = so os que ele coordena / interpreta / cadastrou
create or replace function public.labelle_scope_all()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select s.role = 'ADM' or coalesce(s.perms ->> 'scope', case when s.role = '통역사' then 'mine' else 'all' end) = 'all'
    from public.labelle_staff s
    where lower(s.email) = lower(auth.jwt() ->> 'email') and coalesce(s.active, true) limit 1), false);
$$;
create or replace function public.labelle_patient_visible(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.labelle_is_staff() and exists (
    select 1 from public.labelle_patients p where p.id = p_id
      and (public.labelle_scope_all() or p.counselor = public.labelle_me_name()
           or p.interpreter = public.labelle_me_name() or p.user_id = auth.uid()));
$$;

drop policy if exists "equipe ve" on public.labelle_patients;
drop policy if exists "equipe cria" on public.labelle_patients;
drop policy if exists "equipe edita" on public.labelle_patients;
drop policy if exists "equipe apaga" on public.labelle_patients;
create policy "equipe ve" on public.labelle_patients for select using (
  public.labelle_is_staff() and (public.labelle_scope_all() or counselor = public.labelle_me_name()
    or interpreter = public.labelle_me_name() or user_id = auth.uid()));
create policy "equipe cria" on public.labelle_patients for insert with check (public.labelle_is_staff());
create policy "equipe edita" on public.labelle_patients for update using (
  public.labelle_is_staff() and (public.labelle_scope_all() or counselor = public.labelle_me_name()
    or interpreter = public.labelle_me_name() or user_id = auth.uid()));
create policy "equipe apaga" on public.labelle_patients for delete using (public.labelle_is_adm());

-- arquivos: chat = participantes · foto de perfil = quem ve o paciente · demais = permissao "files" + ver o paciente
create or replace function public.labelle_file_ok(p_name text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if p_name like 'chat/%' then return public.labelle_room_ok(split_part(p_name, '/', 2)::uuid); end if;
  if split_part(p_name, '/', 2) like 'profile-%' then
    return public.labelle_patient_visible(split_part(p_name, '/', 1)::uuid);
  end if;
  return public.labelle_perm('files') and public.labelle_patient_visible(split_part(p_name, '/', 1)::uuid);
exception when others then return false;
end $$;
drop policy if exists "labelle files ver" on storage.objects;
drop policy if exists "labelle files enviar" on storage.objects;
drop policy if exists "labelle files editar" on storage.objects;
drop policy if exists "labelle files apagar" on storage.objects;
create policy "labelle files ver" on storage.objects for select to authenticated
  using (bucket_id = 'labelle-files' and public.labelle_file_ok(name));
create policy "labelle files enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'labelle-files' and public.labelle_file_ok(name));
create policy "labelle files editar" on storage.objects for update to authenticated
  using (bucket_id = 'labelle-files' and public.labelle_file_ok(name));
create policy "labelle files apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'labelle-files' and public.labelle_file_ok(name));

------------------------------------------------------------
-- 2) REGISTRO DE AUDITORIA (so ADM le)
------------------------------------------------------------
create table if not exists public.labelle_audit (
  id bigserial primary key,
  at timestamptz default now(),
  email text default lower(auth.jwt() ->> 'email'),
  action text not null,
  target text,
  detail jsonb
);
alter table public.labelle_audit enable row level security;
drop policy if exists "auditoria ler" on public.labelle_audit;
drop policy if exists "auditoria gravar" on public.labelle_audit;
create policy "auditoria ler" on public.labelle_audit for select using (public.labelle_is_adm());
create policy "auditoria gravar" on public.labelle_audit for insert to authenticated
  with check (lower(email) = lower(auth.jwt() ->> 'email'));

create or replace function public.labelle_audit_trg()
returns trigger language plpgsql security definer set search_path = public as $$
declare a text; t text; d jsonb;
begin
  if TG_TABLE_NAME = 'labelle_staff' then
    t := coalesce(new.email, old.email);
    if TG_OP = 'UPDATE' and (new.role is distinct from old.role or new.perms is distinct from old.perms or new.active is distinct from old.active) then
      a := '직원 권한 변경'; d := jsonb_build_object('role', new.role, 'active', new.active, 'perms', new.perms);
    elsif TG_OP = 'INSERT' then a := '직원 추가'; d := jsonb_build_object('role', new.role);
    elsif TG_OP = 'DELETE' then a := '직원 삭제';
    else return coalesce(new, old); end if;
  elsif TG_TABLE_NAME = 'labelle_partner_users' then
    t := coalesce(new.email, old.email);
    a := case TG_OP when 'INSERT' then '파트너 계정 추가' when 'DELETE' then '파트너 계정 삭제' else '파트너 계정 변경' end;
    d := jsonb_build_object('active', coalesce(new.active, old.active));
  elsif TG_TABLE_NAME = 'labelle_patients' then
    t := coalesce(old.patient_code, '') || ' ' || coalesce(old.name, ''); a := '환자 삭제';
  elsif TG_TABLE_NAME = 'labelle_settlements' then
    t := coalesce(new.agency, old.agency) || ' ' || coalesce(new.period, old.period);
    if TG_OP = 'UPDATE' and new.status is not distinct from old.status then return new; end if;
    a := '정산서 ' || case TG_OP when 'DELETE' then '삭제' else coalesce(new.status, '') end;
    d := jsonb_build_object('total', coalesce(new.total, old.total));
  end if;
  insert into public.labelle_audit (email, action, target, detail) values (lower(auth.jwt() ->> 'email'), a, t, d);
  return coalesce(new, old);
end $$;

drop trigger if exists labelle_audit_staff on public.labelle_staff;
create trigger labelle_audit_staff after insert or update or delete on public.labelle_staff
  for each row execute function public.labelle_audit_trg();
drop trigger if exists labelle_audit_patients on public.labelle_patients;
create trigger labelle_audit_patients after delete on public.labelle_patients
  for each row execute function public.labelle_audit_trg();

------------------------------------------------------------
-- 3) CONTAS DE PARCEIROS (agencias) — nunca leem as tabelas direto,
--    so por funcoes que devolvem apenas os pacientes da propria agencia
------------------------------------------------------------
create table if not exists public.labelle_partner_users (
  email text primary key,
  agency_id uuid not null references public.labelle_agencies(id) on delete cascade,
  name text,
  active boolean default true,
  created_at timestamptz default now(),
  created_by text default lower(auth.jwt() ->> 'email')
);
alter table public.labelle_partner_users enable row level security;
drop policy if exists "adm parceiros" on public.labelle_partner_users;
drop policy if exists "equipe ve parceiros" on public.labelle_partner_users;
create policy "adm parceiros" on public.labelle_partner_users for all using (public.labelle_is_adm()) with check (public.labelle_is_adm());
create policy "equipe ve parceiros" on public.labelle_partner_users for select using (public.labelle_is_staff());
drop trigger if exists labelle_audit_pusers on public.labelle_partner_users;
create trigger labelle_audit_pusers after insert or update or delete on public.labelle_partner_users
  for each row execute function public.labelle_audit_trg();

create or replace function public.labelle_partner_agency()
returns public.labelle_agencies language sql stable security definer set search_path = public as $$
  select a.* from public.labelle_partner_users u join public.labelle_agencies a on a.id = u.agency_id
  where lower(u.email) = lower(auth.jwt() ->> 'email') and coalesce(u.active, true)
    and not public.labelle_is_staff() limit 1;
$$;

create or replace function public.labelle_partner_me()
returns table (agency text, code text, country text, commission_pct numeric, user_name text)
language sql stable security definer set search_path = public as $$
  select a.name, a.code, a.country, a.commission_pct, u.name
  from public.labelle_partner_users u join public.labelle_agencies a on a.id = u.agency_id
  where lower(u.email) = lower(auth.jwt() ->> 'email') and coalesce(u.active, true)
    and not public.labelle_is_staff() limit 1;
$$;

-- pacientes da agencia: dados basicos, etapa, agenda (sem notas) e comissao. Sem arquivos, sem valores do hospital.
create or replace function public.labelle_partner_patients()
returns table (id uuid, patient_code text, name text, nationality text, gender text, birth date, department text,
  procedure text, hospital text, stage int, status text, arrival_date date, surgery_date date, departure_date date,
  counselor text, created_at timestamptz, events jsonb, commission bigint)
language sql stable security definer set search_path = public as $$
  with ag as (select * from public.labelle_partner_agency())
  select p.id, p.patient_code, p.name, p.nationality, p.gender, p.birth, p.department, p.procedure, p.hospital,
    coalesce(p.stage, 0), p.status, p.arrival_date, p.surgery_date, p.departure_date, p.counselor, p.created_at,
    (select coalesce(jsonb_agg(jsonb_build_object('date', e ->> 'date', 'time', e ->> 'time', 'type', e ->> 'type',
              'done', (e ->> 'done') = 'true') order by e ->> 'date', e ->> 'time'), '[]'::jsonb)
       from jsonb_array_elements(case when jsonb_typeof(p.events) = 'array' then p.events else '[]'::jsonb end) e),
    round(coalesce(p.paid_krw, 0) * coalesce(ag.commission_pct, 0) / 100)::bigint
  from public.labelle_patients p, ag
  where ag.id is not null and (p.agency_code = ag.code or (p.agency_code is null and p.agency = ag.name))
  order by p.created_at desc;
$$;

-- parceiro cadastra paciente: o codigo e gerado na hora (ex.: MN-GRG-2610-004)
create or replace function public.labelle_partner_add(p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare ag public.labelle_agencies; who text; cc text; pre text; n int; c text; tries int := 0; cnt int; nat text; nm text;
begin
  select * into ag from public.labelle_partner_agency();
  if ag.id is null then raise exception 'not partner'; end if;
  who := lower(auth.jwt() ->> 'email');
  nm := left(trim(coalesce(p ->> 'name', '')), 80);
  if nm = '' then raise exception 'name'; end if;
  if coalesce(p ->> 'consent', 'false') <> 'true' then raise exception 'consent'; end if;
  select count(*) into cnt from public.labelle_patients where agency_code = ag.code and created_at > now() - interval '1 day';
  if cnt >= 100 then raise exception 'limit'; end if;
  nat := nullif(p ->> 'nationality', '');
  cc := case nat when '몽골' then 'MN' when '브라질' then 'BR' when '스리랑카' then 'LK' when '중국' then 'CN' when '미국' then 'US'
                 when '캐나다' then 'CA' when '호주' then 'AU' when '중동' then 'ME' else 'ET' end;
  pre := cc || '-' || ag.code || '-' || to_char(now() at time zone 'Asia/Seoul', 'YYMM');
  loop
    select coalesce(max(nullif(regexp_replace(substr(patient_code, length(pre) + 2), '\D', '', 'g'), '')::int), 0) + 1 + tries
      into n from public.labelle_patients where patient_code like pre || '-%';
    c := pre || '-' || lpad(n::text, 3, '0');
    begin
      insert into public.labelle_patients (name, birth, gender, nationality, language, phone, email, messenger, messenger_id,
        department, procedure, notes, agency, agency_code, partner, source, stage, status, patient_code, tier, consent, events, files, log)
      values (nm, nullif(p ->> 'birth', '')::date, left(p ->> 'gender', 10), nat, left(p ->> 'language', 20),
        left(p ->> 'phone', 40), left(p ->> 'email', 120), left(p ->> 'messenger', 30), left(p ->> 'messenger_id', 80),
        left(p ->> 'department', 20), left(p ->> 'procedure', 120), left(p ->> 'notes', 1500),
        ag.name, ag.code, ag.name, '해외 파트너', 0, 'active', c, '잠재고객',
        jsonb_build_object('by', 'partner', 'partner_user', who, 'confirmed', true, 'version', 'partner-2026-10-v1', 'at', now()),
        '[]'::jsonb, '[]'::jsonb,
        jsonb_build_array(jsonb_build_object('at', to_char(now() at time zone 'Asia/Seoul', 'FMMM/FMDD HH24:MI'), 'text', '파트너 등록 · ' || ag.name || ' · ' || who)));
      exit;
    exception when unique_violation then
      tries := tries + 1; if tries > 5 then raise; end if;
    end;
  end loop;
  insert into public.labelle_audit (email, action, target, detail) values (who, '파트너 환자 등록', c || ' ' || nm, jsonb_build_object('agency', ag.name));
  return c;
end $$;

------------------------------------------------------------
-- 4) ACERTO DE COMISSAO (정산서) por agencia e mes
------------------------------------------------------------
create table if not exists public.labelle_settlements (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid references public.labelle_agencies(id) on delete set null,
  agency text not null,
  agency_code text,
  period text not null,               -- 'YYYY-MM'
  pct numeric,
  items jsonb default '[]'::jsonb,    -- [{patient_id, code, name, surgery_date, procedure, base, commission}]
  subtotal bigint default 0,
  adjust bigint default 0,
  total bigint default 0,
  status text default 'draft' check (status in ('draft','confirmed','paid')),
  note text,
  confirmed_at timestamptz,
  paid_at timestamptz,
  created_by text default lower(auth.jwt() ->> 'email'),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create unique index if not exists labelle_settlements_uq on public.labelle_settlements (agency_code, period);
alter table public.labelle_settlements enable row level security;
drop policy if exists "financeiro acertos" on public.labelle_settlements;
create policy "financeiro acertos" on public.labelle_settlements for all
  using (public.labelle_is_staff() and public.labelle_perm('finance'))
  with check (public.labelle_is_staff() and public.labelle_perm('finance'));
drop trigger if exists labelle_audit_settle on public.labelle_settlements;
create trigger labelle_audit_settle after insert or update or delete on public.labelle_settlements
  for each row execute function public.labelle_audit_trg();

-- parceiro ve so os acertos confirmados/pagos da propria agencia
create or replace function public.labelle_partner_settlements()
returns setof public.labelle_settlements language sql stable security definer set search_path = public as $$
  select s.* from public.labelle_settlements s, public.labelle_partner_agency() ag
  where ag.id is not null and s.agency_code = ag.code and s.status in ('confirmed','paid')
  order by s.period desc;
$$;

grant execute on function public.labelle_partner_me() to authenticated;
grant execute on function public.labelle_partner_patients() to authenticated;
grant execute on function public.labelle_partner_add(jsonb) to authenticated;
grant execute on function public.labelle_partner_settlements() to authenticated;
revoke execute on function public.labelle_partner_me() from public, anon;
revoke execute on function public.labelle_partner_patients() from public, anon;
revoke execute on function public.labelle_partner_add(jsonb) from public, anon;
revoke execute on function public.labelle_partner_settlements() from public, anon;
