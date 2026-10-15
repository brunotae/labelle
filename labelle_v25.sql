-- =====================================================================
-- LA BELLE LB v3.5 — ETAPA 1 (1단계: 보안·계정)
-- Supabase → SQL Editor → New query → colar TUDO → Run  (pode repetir sem problema)
-- Precisa ter rodado antes o LABELLE_banco_completo.sql (ou v16 … v24).
--
-- O que este arquivo faz
--  1) Papeis novos: 최고관리자(ADM) · 운영관리자 · 코디네이터 · 상담 담당자 · 의료일정 담당자 · 재무 담당자
--     (+ 파트너 = contas de agencia, e SOFIA = funcao no servidor)
--  2) Permissoes por papel no servidor: 환자 범위, 재무, 파일, 개인정보(PII), 의료정보, 내보내기
--  3) Contas de teste: so veem pacientes de teste; nunca veem pedidos/mensagens reais
--  4) Dados pessoais (연락처·여권·생년월일·이메일·메신저) escondidos para quem nao tem permissao
--  5) Informacao medica em tabela separada, so por funcao, com registro de cada leitura
--  6) MFA obrigatorio (app autenticador) para 최고관리자 · 재무 담당자 · 파트너
--  7) Tela de gestao: ultimo login, MFA, pacientes por funcionario, falhas de login
--  8) 10 contas de coordenador (teste) + Janice como 최고관리자
-- =====================================================================

------------------------------------------------------------
-- 1) EQUIPE: colunas novas
------------------------------------------------------------
alter table public.labelle_staff add column if not exists login_id text;
alter table public.labelle_staff add column if not exists real_name text;
alter table public.labelle_staff add column if not exists dept text;
alter table public.labelle_staff add column if not exists is_test boolean default false;
alter table public.labelle_staff add column if not exists invited_at timestamptz;
create unique index if not exists labelle_staff_login_uq on public.labelle_staff (lower(login_id)) where login_id is not null;

alter table public.labelle_patients add column if not exists is_test boolean default false;
alter table public.labelle_patients add column if not exists deleted_at timestamptz;

insert into public.labelle_settings (key, value) values
  ('mfa_enforce', 'true'::jsonb),          -- MFA obrigatorio para os papeis abaixo
  ('mfa_roles', '["ADM","재무 담당자"]'::jsonb)
on conflict (key) do nothing;

------------------------------------------------------------
-- 2) FUNCOES BASE (papel, MFA, conta de teste)
------------------------------------------------------------
create or replace function public.labelle_me()
returns public.labelle_staff language sql stable security definer set search_path = public as $$
  select * from public.labelle_staff where lower(email) = lower(auth.jwt() ->> 'email') and coalesce(active, true) limit 1;
$$;

-- MFA: papel exige MFA? entao a sessao precisa ser aal2
create or replace function public.labelle_mfa_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select value::text from public.labelle_settings where key = 'mfa_enforce'), 'true') <> 'true'
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
      or not exists (
        select 1 from public.labelle_staff s, public.labelle_settings c
        where lower(s.email) = lower(auth.jwt() ->> 'email') and coalesce(s.active, true)
          and c.key = 'mfa_roles' and c.value ? s.role);
$$;

create or replace function public.labelle_is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.labelle_staff
                 where lower(email) = lower(auth.jwt() ->> 'email') and coalesce(active, true))
     and public.labelle_mfa_ok();
$$;
create or replace function public.labelle_is_adm()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.labelle_staff
                 where lower(email) = lower(auth.jwt() ->> 'email') and role = 'ADM' and coalesce(active, true))
     and public.labelle_mfa_ok();
$$;
-- conta de teste?
create or replace function public.labelle_me_test()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_test from public.labelle_staff where lower(email) = lower(auth.jwt() ->> 'email') limit 1), false);
$$;
-- equipe real (nao teste): pode ver pedidos e mensagens de clientes reais
create or replace function public.labelle_is_real_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select public.labelle_is_staff() and not public.labelle_me_test();
$$;

-- padrao de cada papel (o ADM pode mudar por pessoa em perms; 의료정보 nunca para 재무 담당자)
create or replace function public.labelle_role_default(p_role text, p_key text)
returns jsonb language sql immutable as $$
  select case p_key
    when 'scope' then to_jsonb(case when p_role in ('코디네이터','상담 담당자','통역사') then 'mine' else 'all' end)
    when 'finance' then to_jsonb(p_role in ('ADM','재무 담당자'))
    when 'files' then to_jsonb(p_role in ('ADM','운영관리자','코디네이터','통역사','직원'))
    when 'pii' then to_jsonb(p_role in ('ADM','운영관리자','코디네이터','상담 담당자','통역사','직원'))
    when 'export' then to_jsonb(p_role = 'ADM')
    when 'medical' then 'false'::jsonb   -- 의료정보: 처음에는 모두 차단, ADM이 사람별로 부여
    else 'false'::jsonb end;
$$;

create or replace function public.labelle_perm(p_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select case
      when p_key = 'medical' and s.role in ('재무 담당자') then false
      when s.perms ? p_key and jsonb_typeof(s.perms -> p_key) = 'boolean' then (s.perms ->> p_key)::boolean
      when s.role = 'ADM' and p_key <> 'medical' then true
      else (public.labelle_role_default(s.role, p_key))::text = 'true' end
    from public.labelle_staff s
    where lower(s.email) = lower(auth.jwt() ->> 'email') and coalesce(s.active, true) limit 1), false)
    and public.labelle_mfa_ok();
$$;
create or replace function public.labelle_scope_all()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select s.role = 'ADM' or coalesce(s.perms ->> 'scope', public.labelle_role_default(s.role, 'scope') #>> '{}') = 'all'
    from public.labelle_staff s
    where lower(s.email) = lower(auth.jwt() ->> 'email') and coalesce(s.active, true) limit 1), false);
$$;
create or replace function public.labelle_patient_visible(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.labelle_is_staff() and exists (
    select 1 from public.labelle_patients p where p.id = p_id
      and (not public.labelle_me_test() or coalesce(p.is_test, false))
      and (public.labelle_scope_all() or p.counselor = public.labelle_me_name()
           or p.interpreter = public.labelle_me_name() or p.user_id = auth.uid()));
$$;

------------------------------------------------------------
-- 3) PACIENTES: regras novas (conta de teste so ve teste)
------------------------------------------------------------
drop policy if exists "equipe ve" on public.labelle_patients;
drop policy if exists "equipe cria" on public.labelle_patients;
drop policy if exists "equipe edita" on public.labelle_patients;
drop policy if exists "equipe apaga" on public.labelle_patients;
create policy "equipe ve" on public.labelle_patients for select using (public.labelle_patient_visible(id));
create policy "equipe cria" on public.labelle_patients for insert with check (
  public.labelle_is_staff() and (not public.labelle_me_test() or coalesce(is_test, false)));
create policy "equipe edita" on public.labelle_patients for update using (public.labelle_patient_visible(id));
create policy "equipe apaga" on public.labelle_patients for delete using (public.labelle_is_adm());

-- conta de teste: tudo que cadastrar vira paciente de teste.
-- sem permissao de dados pessoais: nao consegue apagar/alterar esses campos (o app recebe vazio).
create or replace function public.labelle_patient_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.labelle_me_test() then new.is_test := true; end if;
  if TG_OP = 'UPDATE' and not public.labelle_perm('pii') then
    new.contact := old.contact; new.phone := old.phone; new.email := old.email; new.messenger := old.messenger;
    new.messenger_id := old.messenger_id; new.passport_exp := old.passport_exp; new.birth := old.birth;
  end if;
  return new;
end $$;
drop trigger if exists labelle_patient_guard on public.labelle_patients;
create trigger labelle_patient_guard before insert or update on public.labelle_patients
  for each row execute function public.labelle_patient_guard();

------------------------------------------------------------
-- 4) DADOS PESSOAIS: leitura so pela visao labelle_patients_v
--    (sem permissao 'pii' → 연락처·여권·생년월일·이메일·메신저 vem vazios)
------------------------------------------------------------
-- a visao precisa esconder as colunas: recria com as colunas pessoais mascaradas
do $$
declare cols text; pii text[] := array['contact','phone','email','messenger','messenger_id','passport_exp','birth'];
begin
  select string_agg(case when c.column_name = any(pii)
           then format('case when public.labelle_perm(''pii'') then p.%I end as %I', c.column_name, c.column_name)
           else format('p.%I', c.column_name) end, ', ' order by c.ordinal_position)
    into cols
    from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'labelle_patients';
  execute 'drop view if exists public.labelle_patients_v';
  execute format('create view public.labelle_patients_v as select %s, not public.labelle_perm(''pii'') as pii_masked
                  from public.labelle_patients p where public.labelle_patient_visible(p.id)', cols);
end $$;
grant select on public.labelle_patients_v to authenticated;
revoke select on public.labelle_patients_v from anon;

-- tabela direta: ler so colunas nao pessoais (gravar continua igual, com as regras acima)
do $$
declare cols text; pii text[] := array['contact','phone','email','messenger','messenger_id','passport_exp','birth'];
begin
  execute 'revoke select on public.labelle_patients from anon, authenticated';
  select string_agg(quote_ident(column_name), ', ') into cols
    from information_schema.columns where table_schema = 'public' and table_name = 'labelle_patients'
     and not (column_name = any(pii));
  execute format('grant select (%s) on public.labelle_patients to authenticated', cols);
end $$;

------------------------------------------------------------
-- 5) INFORMACAO MEDICA (병력·약·검사·사진·동의서·경과·합병증)
--    Sem acesso direto: so pelas funcoes abaixo, que conferem a permissao 'medical' e registram cada leitura.
------------------------------------------------------------
create table if not exists public.labelle_patient_medical (
  patient_id uuid primary key references public.labelle_patients(id) on delete cascade,
  history text,          -- 병력·기저질환
  allergies text,        -- 알레르기
  medications text,      -- 복용 약물
  health_status text,    -- 건강 상태
  exams text,            -- 검사 결과·진단서·소견서
  consult_health text,   -- 상담 중 건강 관련 내용
  procedure_detail text, -- 시술·수술 상세 및 경과
  complications text,    -- 합병증·부작용·사후관리
  consents text,         -- 수술·의료 동의서 메모
  updated_at timestamptz default now(),
  updated_by text
);
alter table public.labelle_patient_medical enable row level security;
revoke all on public.labelle_patient_medical from anon, authenticated;

create or replace function public.labelle_medical_get(p_id uuid)
returns public.labelle_patient_medical language plpgsql security definer set search_path = public as $$
declare r public.labelle_patient_medical; nm text;
begin
  if not (public.labelle_perm('medical') and public.labelle_patient_visible(p_id)) then
    raise exception 'medical_denied' using errcode = '42501';
  end if;
  select * into r from public.labelle_patient_medical where patient_id = p_id;
  select coalesce(patient_code, '') || ' ' || coalesce(name, '') into nm from public.labelle_patients where id = p_id;
  insert into public.labelle_audit (email, action, target) values (lower(auth.jwt() ->> 'email'), '의료정보 열람', nm);
  return r;
end $$;

create or replace function public.labelle_medical_save(p_id uuid, d jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if not (public.labelle_perm('medical') and public.labelle_patient_visible(p_id)) then
    raise exception 'medical_denied' using errcode = '42501';
  end if;
  insert into public.labelle_patient_medical as m (patient_id, history, allergies, medications, health_status, exams,
      consult_health, procedure_detail, complications, consents, updated_at, updated_by)
  values (p_id, d->>'history', d->>'allergies', d->>'medications', d->>'health_status', d->>'exams',
      d->>'consult_health', d->>'procedure_detail', d->>'complications', d->>'consents', now(), lower(auth.jwt() ->> 'email'))
  on conflict (patient_id) do update set history = excluded.history, allergies = excluded.allergies,
      medications = excluded.medications, health_status = excluded.health_status, exams = excluded.exams,
      consult_health = excluded.consult_health, procedure_detail = excluded.procedure_detail,
      complications = excluded.complications, consents = excluded.consents, updated_at = now(), updated_by = excluded.updated_by;
  select coalesce(patient_code, '') || ' ' || coalesce(name, '') into nm from public.labelle_patients where id = p_id;
  insert into public.labelle_audit (email, action, target) values (lower(auth.jwt() ->> 'email'), '의료정보 수정', nm);
end $$;
revoke execute on function public.labelle_medical_get(uuid) from public, anon;
revoke execute on function public.labelle_medical_save(uuid, jsonb) from public, anon;
grant execute on function public.labelle_medical_get(uuid) to authenticated;
grant execute on function public.labelle_medical_save(uuid, jsonb) to authenticated;

-- arquivos medicos: nome comeca com 'med-' → precisa da permissao 'medical'
create or replace function public.labelle_file_ok(p_name text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if p_name like 'chat/%' then return public.labelle_room_ok(split_part(p_name, '/', 2)::uuid); end if;
  if split_part(p_name, '/', 2) like 'profile-%' then
    return public.labelle_patient_visible(split_part(p_name, '/', 1)::uuid);
  end if;
  if split_part(p_name, '/', 2) like 'med-%' then
    return public.labelle_perm('medical') and public.labelle_patient_visible(split_part(p_name, '/', 1)::uuid);
  end if;
  return public.labelle_perm('files') and public.labelle_patient_visible(split_part(p_name, '/', 1)::uuid);
exception when others then return false;
end $$;

------------------------------------------------------------
-- 6) PEDIDOS E MENSAGENS DE CLIENTES: conta de teste nao ve
------------------------------------------------------------
drop policy if exists "equipe ve leads" on public.labelle_leads;
drop policy if exists "equipe edita leads" on public.labelle_leads;
create policy "equipe ve leads" on public.labelle_leads for select using (public.labelle_is_real_staff());
create policy "equipe edita leads" on public.labelle_leads for update using (public.labelle_is_real_staff());
drop policy if exists "equipe conversas" on public.labelle_threads;
drop policy if exists "equipe conversas msgs" on public.labelle_thread_msgs;
create policy "equipe conversas" on public.labelle_threads for all
  using (public.labelle_is_real_staff()) with check (public.labelle_is_real_staff());
create policy "equipe conversas msgs" on public.labelle_thread_msgs for all
  using (public.labelle_is_real_staff()) with check (public.labelle_is_real_staff() and sender in ('staff','system'));

------------------------------------------------------------
-- 7) PARCEIROS: MFA obrigatorio tambem
------------------------------------------------------------
create or replace function public.labelle_partner_agency()
returns public.labelle_agencies language sql stable security definer set search_path = public as $$
  select a.* from public.labelle_partner_users u join public.labelle_agencies a on a.id = u.agency_id
  where lower(u.email) = lower(auth.jwt() ->> 'email') and coalesce(u.active, true)
    and not public.labelle_is_staff()
    and (coalesce((select value::text from public.labelle_settings where key = 'mfa_enforce'), 'true') <> 'true'
         or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2')
  limit 1;
$$;

------------------------------------------------------------
-- 8) QUEM SOU EU (funciona antes do MFA, para o app saber o que pedir)
------------------------------------------------------------
create or replace function public.labelle_whoami()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object('kind', 'staff', 'email', s.email, 'name', s.name, 'role', s.role, 'is_test', coalesce(s.is_test, false),
      'mfa_required', coalesce((select value::text from public.labelle_settings where key = 'mfa_enforce'), 'true') = 'true'
                      and exists (select 1 from public.labelle_settings c where c.key = 'mfa_roles' and c.value ? s.role),
      'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'))
    from public.labelle_staff s where lower(s.email) = lower(auth.jwt() ->> 'email') and coalesce(s.active, true) limit 1),
    (select jsonb_build_object('kind', 'partner', 'email', u.email, 'name', u.name,
      'mfa_required', coalesce((select value::text from public.labelle_settings where key = 'mfa_enforce'), 'true') = 'true',
      'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'))
     from public.labelle_partner_users u where lower(u.email) = lower(auth.jwt() ->> 'email') and coalesce(u.active, true) limit 1),
    jsonb_build_object('kind', 'none'));
$$;
grant execute on function public.labelle_whoami() to authenticated;

------------------------------------------------------------
-- 9) PROTECAO DO ADM: nao pode se rebaixar/desativar, e sempre sobra 1 ADM ativo
------------------------------------------------------------
create or replace function public.labelle_staff_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if TG_OP in ('UPDATE','DELETE') and old.role = 'ADM'
     and (TG_OP = 'DELETE' or new.role <> 'ADM' or coalesce(new.active, true) = false) then
    if lower(old.email) = lower(auth.jwt() ->> 'email') then
      raise exception '본인의 최고관리자 권한은 직접 해제할 수 없습니다.';
    end if;
    if (select count(*) from public.labelle_staff where role = 'ADM' and coalesce(active, true) and email <> old.email) = 0 then
      raise exception '최고관리자는 최소 1명 있어야 합니다.';
    end if;
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists labelle_staff_guard on public.labelle_staff;
create trigger labelle_staff_guard before update or delete on public.labelle_staff
  for each row execute function public.labelle_staff_guard();

------------------------------------------------------------
-- 10) TELA DE GESTAO (so ADM): ultimo login, MFA, pacientes, falhas de login
------------------------------------------------------------
create table if not exists public.labelle_login_log (
  id bigserial primary key,
  at timestamptz default now(),
  login text,
  email text,
  ok boolean,
  reason text
);
alter table public.labelle_login_log enable row level security;
drop policy if exists "login log adm" on public.labelle_login_log;
create policy "login log adm" on public.labelle_login_log for select using (public.labelle_is_adm());

create or replace function public.labelle_admin_staff()
returns table (email text, login_id text, name text, real_name text, dept text, role text, perms jsonb, active boolean,
  is_test boolean, created_at timestamptz, invited_at timestamptz, last_sign_in_at timestamptz, confirmed boolean,
  mfa boolean, patients int, fails_24h int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.labelle_is_adm() then raise exception 'denied' using errcode = '42501'; end if;
  return query
  select s.email, s.login_id, s.name, s.real_name, s.dept, s.role, s.perms, coalesce(s.active, true), coalesce(s.is_test, false),
    s.created_at, s.invited_at, u.last_sign_in_at, (u.email_confirmed_at is not null),
    exists (select 1 from auth.mfa_factors f where f.user_id = u.id and f.status = 'verified'),
    (select count(*)::int from public.labelle_patients p where p.counselor = s.name and p.status is distinct from 'canceled'),
    (select count(*)::int from public.labelle_login_log l where l.ok = false and l.at > now() - interval '24 hours'
       and (lower(l.email) = lower(s.email) or lower(l.login) = lower(s.login_id)))
  from public.labelle_staff s left join auth.users u on lower(u.email) = lower(s.email)
  order by (s.role = 'ADM') desc, s.name;
end $$;
revoke execute on function public.labelle_admin_staff() from public, anon;
grant execute on function public.labelle_admin_staff() to authenticated;

------------------------------------------------------------
-- 11) CONTAS INICIAIS
--     Janice e Tae = 최고관리자. 10 coordenadores de TESTE (sem e-mail ainda: o ADM convida pela tela).
------------------------------------------------------------
insert into public.labelle_staff (email, name, role, login_id, active) values
  ('labellelb0415@gmail.com', 'Janice', 'ADM', 'janice', true)
on conflict (email) do update set role = 'ADM', active = true, login_id = coalesce(public.labelle_staff.login_id, 'janice');
update public.labelle_staff set login_id = 'tae' where lower(email) = 'bruno@mintess.com' and login_id is null;

insert into public.labelle_staff (email, name, role, login_id, dept, is_test, active, color)
select 'staff_' || lower(n) || '@pending.labellelb', n, '코디네이터', 'staff_' || lower(n), '의료관광 운영팀', true, false, c
from (values ('ARI','#E0457B'),('SEOUL','#3E7CB1'),('HANNA','#7A5BB5'),('NARA','#2E9C7A'),('BORA','#B5652E'),
             ('HANA','#C2408F'),('MISO','#4F8A3A'),('NARI','#3A6FA8'),('NURI','#A8873A'),('SORA','#5B6BB5')) v(n, c)
where not exists (select 1 from public.labelle_staff s where lower(s.login_id) = 'staff_' || lower(v.n));
