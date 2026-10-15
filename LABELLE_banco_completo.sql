-- =====================================================================
-- LA BELLE LB — BANCO DE DADOS COMPLETO (v3.5) · todos os SQL em ordem
-- Uso: Supabase → SQL Editor → New query → colar TUDO → Run
-- Serve para (1) recriar o sistema num projeto Supabase novo e
--            (2) rodar de novo num projeto existente (nao apaga dados).
-- Contem: pacientes, equipe e permissoes, arquivos, agencias, consultas,
--         ponto, pedidos, chat, chatbot + 40 FAQ (5 idiomas), parceiros,
--         acertos de comissao, registro de auditoria, SOFIA (uso da IA) e
--         etapa 1 de seguranca (papeis, MFA, contas de teste, dados pessoais e medicos protegidos).
-- Nao contem senhas nem chaves secretas.
-- =====================================================================


-- ---------------------------------------------------------------------
-- [labelle_patients.sql]
-- ---------------------------------------------------------------------
-- LA BELLE 환자 여정 (데모) — 가상 데이터 전용
create table if not exists public.labelle_patients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  nationality text,
  language text,
  contact text,
  counselor text,
  department text,
  procedure text,
  hospital text,
  source text,
  partner text,
  stage int default 0,
  arrival_date date,
  surgery_date date,
  departure_date date,
  quote_krw bigint,
  paid_krw bigint,
  notes text,
  events jsonb default '[]'::jsonb,
  log jsonb default '[]'::jsonb,
  status text default 'active',
  created_at timestamptz default now(),
  canceled_at timestamptz
);
alter table public.labelle_patients enable row level security;
drop policy if exists "ver os meus" on public.labelle_patients;
create policy "ver os meus" on public.labelle_patients for select using (auth.uid() = user_id);
drop policy if exists "criar os meus" on public.labelle_patients;
create policy "criar os meus" on public.labelle_patients for insert with check (auth.uid() = user_id);
drop policy if exists "editar os meus" on public.labelle_patients;
create policy "editar os meus" on public.labelle_patients for update using (auth.uid() = user_id);
drop policy if exists "apagar os meus" on public.labelle_patients;
create policy "apagar os meus" on public.labelle_patients for delete using (auth.uid() = user_id);


-- ---------------------------------------------------------------------
-- [labelle_acessos.sql]
-- ---------------------------------------------------------------------
-- LA BELLE — equipe compartilhada (todos os ADM veem e editam os mesmos pacientes)
-- Rodar UMA vez no Supabase → SQL Editor → New query → Run

-- 1) Tabela de acessos
create table if not exists public.labelle_staff (
  email text primary key,
  name text,
  role text not null default 'ADM',
  created_at timestamptz default now()
);
alter table public.labelle_staff enable row level security;
drop policy if exists "ver o proprio acesso" on public.labelle_staff;
create policy "ver o proprio acesso" on public.labelle_staff
  for select using (lower(email) = lower(auth.jwt() ->> 'email'));

-- 2) Funcao: o usuario logado esta na equipe?
create or replace function public.labelle_is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.labelle_staff
                 where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

-- 3) Trocar as regras "cada um ve o seu" por "a equipe ve tudo"
drop policy if exists "ver os meus" on public.labelle_patients;
drop policy if exists "criar os meus" on public.labelle_patients;
drop policy if exists "editar os meus" on public.labelle_patients;
drop policy if exists "apagar os meus" on public.labelle_patients;
drop policy if exists "equipe ve" on public.labelle_patients;
drop policy if exists "equipe cria" on public.labelle_patients;
drop policy if exists "equipe edita" on public.labelle_patients;
drop policy if exists "equipe apaga" on public.labelle_patients;
create policy "equipe ve" on public.labelle_patients for select using (public.labelle_is_staff());
create policy "equipe cria" on public.labelle_patients for insert with check (public.labelle_is_staff());
create policy "equipe edita" on public.labelle_patients for update using (public.labelle_is_staff());
create policy "equipe apaga" on public.labelle_patients for delete using (public.labelle_is_staff());

-- 4) Quem e ADM  (confira se o e-mail do Tae e o mesmo que ele usa no login)
-- primeiros administradores (num cliente novo, troque estes e-mails)
insert into public.labelle_staff (email, name, role) values
  ('bruno@mintess.com',   'Tae',    'ADM'),
  ('janice@labelle.app',  'Janice', 'ADM')
on conflict (email) do nothing;


-- ---------------------------------------------------------------------
-- [labelle_files.sql]
-- ---------------------------------------------------------------------
-- LA BELLE v1.4 — coluna para os registros de fotos/exames/documentos (demo)
alter table public.labelle_patients add column if not exists files jsonb default '[]'::jsonb;


-- ---------------------------------------------------------------------
-- [labelle_v16.sql]
-- ---------------------------------------------------------------------
-- LA BELLE v1.6 — rodar UMA vez: Supabase → SQL Editor → New query → colar → Run
-- (pode rodar mesmo que ja tenha rodado os SQL anteriores)

-- 1) Campos novos do paciente
alter table public.labelle_patients add column if not exists files jsonb default '[]'::jsonb;
alter table public.labelle_patients add column if not exists patient_code text;
alter table public.labelle_patients add column if not exists agency text;
alter table public.labelle_patients add column if not exists agency_code text;
alter table public.labelle_patients add column if not exists interpreter text;
alter table public.labelle_patients add column if not exists program text;
alter table public.labelle_patients add column if not exists payment_method text;
alter table public.labelle_patients add column if not exists profile_path text;
create unique index if not exists labelle_patients_code_uq
  on public.labelle_patients (patient_code) where patient_code is not null;

-- 2) Equipe (caso ainda nao exista)
create table if not exists public.labelle_staff (
  email text primary key, name text, role text not null default 'ADM', created_at timestamptz default now());
alter table public.labelle_staff enable row level security;
create or replace function public.labelle_is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.labelle_staff where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

-- 3) Agencias (codigo usado no codigo do paciente: MN-GRG-2610-001)
create table if not exists public.labelle_agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  country text,
  created_at timestamptz default now()
);
alter table public.labelle_agencies enable row level security;
drop policy if exists "equipe agencias" on public.labelle_agencies;
create policy "equipe agencias" on public.labelle_agencies
  for all using (public.labelle_is_staff()) with check (public.labelle_is_staff());

-- 4) Arquivos (privado, so a equipe acessa; limite 50 MB por arquivo)
insert into storage.buckets (id, name, public, file_size_limit)
values ('labelle-files', 'labelle-files', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = 52428800;

drop policy if exists "labelle files ver" on storage.objects;
drop policy if exists "labelle files enviar" on storage.objects;
drop policy if exists "labelle files editar" on storage.objects;
drop policy if exists "labelle files apagar" on storage.objects;
create policy "labelle files ver" on storage.objects for select to authenticated
  using (bucket_id = 'labelle-files' and public.labelle_is_staff());
create policy "labelle files enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'labelle-files' and public.labelle_is_staff());
create policy "labelle files editar" on storage.objects for update to authenticated
  using (bucket_id = 'labelle-files' and public.labelle_is_staff());
create policy "labelle files apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'labelle-files' and public.labelle_is_staff());


-- ---------------------------------------------------------------------
-- [labelle_v17.sql]
-- ---------------------------------------------------------------------
-- LA BELLE v1.7 — rodar UMA vez: Supabase → SQL Editor → New query → colar → Run
-- (rode antes o labelle_v16.sql, se ainda nao rodou)

-- 1) Equipe: cor, link de consulta, cargo
alter table public.labelle_staff add column if not exists color text;
alter table public.labelle_staff add column if not exists slug text;
alter table public.labelle_staff add column if not exists active boolean default true;
create unique index if not exists labelle_staff_slug_uq on public.labelle_staff (slug) where slug is not null;

create or replace function public.labelle_is_adm()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.labelle_staff
                 where lower(email) = lower(auth.jwt() ->> 'email') and role = 'ADM');
$$;

drop policy if exists "ver o proprio acesso" on public.labelle_staff;
drop policy if exists "equipe ve equipe" on public.labelle_staff;
drop policy if exists "adm gerencia equipe" on public.labelle_staff;
create policy "equipe ve equipe" on public.labelle_staff for select using (public.labelle_is_staff());
create policy "adm gerencia equipe" on public.labelle_staff for all
  using (public.labelle_is_adm()) with check (public.labelle_is_adm());

-- 2) Registro de consultas (conta no calendario de cada coordenador)
create table if not exists public.labelle_consults (
  id uuid primary key default gen_random_uuid(),
  at_date date not null,
  at_time text,
  staff text not null,
  patient_id uuid,
  lead_id uuid,
  subject text,
  channel text,
  minutes int,
  note text,
  created_by text,
  created_at timestamptz default now()
);
alter table public.labelle_consults enable row level security;
drop policy if exists "equipe consultas" on public.labelle_consults;
create policy "equipe consultas" on public.labelle_consults
  for all using (public.labelle_is_staff()) with check (public.labelle_is_staff());

-- 3) Ponto (entrada / saida)
create table if not exists public.labelle_worklog (
  id uuid primary key default gen_random_uuid(),
  staff text not null,
  email text,
  start_at timestamptz not null default now(),
  end_at timestamptz,
  created_at timestamptz default now()
);
alter table public.labelle_worklog enable row level security;
drop policy if exists "equipe ponto" on public.labelle_worklog;
create policy "equipe ponto" on public.labelle_worklog
  for all using (public.labelle_is_staff()) with check (public.labelle_is_staff());

-- 4) Pedidos de consulta enviados pelo proprio cliente (formulario publico)
create table if not exists public.labelle_leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  form_lang text,
  name text not null,
  birth date,
  gender text,
  nationality text,
  phone text,
  messenger text,
  messenger_id text,
  email text,
  department text,
  procedure text,
  visit_month text,
  message text,
  coord_slug text,
  coordinator text,
  consent_privacy boolean not null default false,
  consent_sensitive boolean not null default false,
  consent_third boolean not null default false,
  consent_overseas boolean default false,
  consent_marketing boolean default false,
  consent_version text,
  status text default 'new',
  claimed_by text,
  claimed_at timestamptz,
  patient_id uuid,
  staff_note text
);
alter table public.labelle_leads enable row level security;
drop policy if exists "cliente envia" on public.labelle_leads;
drop policy if exists "equipe ve leads" on public.labelle_leads;
drop policy if exists "equipe edita leads" on public.labelle_leads;
drop policy if exists "equipe apaga leads" on public.labelle_leads;
create policy "cliente envia" on public.labelle_leads for insert to anon, authenticated
  with check (consent_privacy and consent_sensitive and consent_third and status = 'new'
              and claimed_by is null and patient_id is null);
create policy "equipe ve leads" on public.labelle_leads for select using (public.labelle_is_staff());
create policy "equipe edita leads" on public.labelle_leads for update using (public.labelle_is_staff());
create policy "equipe apaga leads" on public.labelle_leads for delete using (public.labelle_is_adm());

-- nome e cor do coordenador do link (o cliente nao ve mais nada da equipe)
create or replace function public.labelle_coord(p_slug text)
returns table (name text, color text) language sql stable security definer set search_path = public as $$
  select s.name, s.color from public.labelle_staff s
  where s.slug = lower(p_slug) and coalesce(s.active, true) limit 1;
$$;
grant execute on function public.labelle_coord(text) to anon, authenticated;

-- 5) Consentimento guardado no paciente
alter table public.labelle_patients add column if not exists consent jsonb;
alter table public.labelle_patients add column if not exists lead_id uuid;

-- 6) Cores e links iniciais (ajuste no app, aba 직원)
update public.labelle_staff set color = coalesce(color, '#FF2E8B'), slug = coalesce(slug, 'tae') where email = 'bruno@mintess.com';
update public.labelle_staff set color = coalesce(color, '#5BE3A8'), slug = coalesce(slug, 'janice') where email = 'janice@labelle.app';


-- ---------------------------------------------------------------------
-- [labelle_v20.sql]
-- ---------------------------------------------------------------------
-- LA BELLE v2.0 — nivel do cliente (잠재고객 / 일반고객 / VIP / 임직원가족고객)
alter table public.labelle_patients add column if not exists tier text default '일반고객';


-- ---------------------------------------------------------------------
-- [labelle_v21.sql]
-- ---------------------------------------------------------------------
-- LA BELLE v3.0 — cadastro em 5 etapas, pos-operatorio e parceiros
-- Supabase → SQL Editor → New query → colar → Run (pode repetir sem problema)
alter table public.labelle_patients add column if not exists birth date;
alter table public.labelle_patients add column if not exists gender text;
alter table public.labelle_patients add column if not exists phone text;
alter table public.labelle_patients add column if not exists email text;
alter table public.labelle_patients add column if not exists messenger text;
alter table public.labelle_patients add column if not exists messenger_id text;
alter table public.labelle_patients add column if not exists passport_exp date;
alter table public.labelle_patients add column if not exists aftercare jsonb default '[]'::jsonb;
alter table public.labelle_patients add column if not exists tier text default '일반고객';

alter table public.labelle_agencies add column if not exists contact_name text;
alter table public.labelle_agencies add column if not exists contact text;
alter table public.labelle_agencies add column if not exists commission_pct numeric;

alter table public.labelle_staff add column if not exists gender text;


-- ---------------------------------------------------------------------
-- [labelle_v22.sql]
-- ---------------------------------------------------------------------
-- LA BELLE v3.1 — ETAPA 2: chat da equipe, mensagens de clientes e chatbot (FAQ)
-- Supabase → SQL Editor → New query → colar TUDO → Run  (pode repetir sem problema)

------------------------------------------------------------
-- 1) CHAT DA EQUIPE  (1:1, grupo, por paciente, "전체")
------------------------------------------------------------
create table if not exists public.labelle_rooms (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('all','dm','group','patient')),
  name text,
  patient_id uuid,
  members text[] not null default '{}',
  created_by text,
  created_at timestamptz default now(),
  last_at timestamptz default now(),
  last_text text
);
create unique index if not exists labelle_rooms_patient_uq on public.labelle_rooms (patient_id) where kind = 'patient';
create unique index if not exists labelle_rooms_all_uq on public.labelle_rooms (kind) where kind = 'all';

create table if not exists public.labelle_msgs (
  id bigserial primary key,
  room_id uuid not null references public.labelle_rooms(id) on delete cascade,
  sender text not null,
  sender_name text,
  body text,
  file_path text,
  file_name text,
  file_size bigint,
  created_at timestamptz default now()
);
create index if not exists labelle_msgs_room_idx on public.labelle_msgs (room_id, id);

create table if not exists public.labelle_reads (
  room_id uuid not null references public.labelle_rooms(id) on delete cascade,
  email text not null,
  last_id bigint default 0,
  primary key (room_id, email)
);

-- quem pode ver a sala: 1:1 e grupo = so os membros (nem o ADM le conversa privada);
-- "전체" e sala de paciente = toda a equipe
create or replace function public.labelle_room_ok(p_room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.labelle_is_staff() and exists (
    select 1 from public.labelle_rooms r where r.id = p_room
      and (r.kind in ('all','patient') or lower(auth.jwt() ->> 'email') = any(r.members)));
$$;

alter table public.labelle_rooms enable row level security;
alter table public.labelle_msgs  enable row level security;
alter table public.labelle_reads enable row level security;
drop policy if exists "salas ver" on public.labelle_rooms;
drop policy if exists "salas criar" on public.labelle_rooms;
drop policy if exists "salas editar" on public.labelle_rooms;
drop policy if exists "salas apagar" on public.labelle_rooms;
create policy "salas ver" on public.labelle_rooms for select using (
  public.labelle_is_staff() and (kind in ('all','patient') or lower(auth.jwt() ->> 'email') = any(members)));
create policy "salas criar" on public.labelle_rooms for insert with check (
  public.labelle_is_staff() and lower(created_by) = lower(auth.jwt() ->> 'email')
  and (kind in ('patient') or lower(auth.jwt() ->> 'email') = any(members)));
create policy "salas editar" on public.labelle_rooms for update using (
  public.labelle_is_staff() and (lower(created_by) = lower(auth.jwt() ->> 'email') or public.labelle_is_adm()) and kind <> 'all');
create policy "salas apagar" on public.labelle_rooms for delete using (
  public.labelle_is_staff() and (lower(created_by) = lower(auth.jwt() ->> 'email') or public.labelle_is_adm()) and kind <> 'all');

drop policy if exists "msgs ver" on public.labelle_msgs;
drop policy if exists "msgs enviar" on public.labelle_msgs;
drop policy if exists "msgs apagar" on public.labelle_msgs;
create policy "msgs ver" on public.labelle_msgs for select using (public.labelle_room_ok(room_id));
create policy "msgs enviar" on public.labelle_msgs for insert with check (
  public.labelle_room_ok(room_id) and lower(sender) = lower(auth.jwt() ->> 'email'));
create policy "msgs apagar" on public.labelle_msgs for delete using (lower(sender) = lower(auth.jwt() ->> 'email'));

drop policy if exists "lidas" on public.labelle_reads;
create policy "lidas" on public.labelle_reads for all
  using (lower(email) = lower(auth.jwt() ->> 'email'))
  with check (lower(email) = lower(auth.jwt() ->> 'email') and public.labelle_room_ok(room_id));

-- atualiza "ultima mensagem" da sala automaticamente
create or replace function public.labelle_msgs_touch()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.labelle_rooms
     set last_at = new.created_at,
         last_text = coalesce(nullif(left(new.body, 120), ''), '📎 ' || coalesce(new.file_name, ''))
   where id = new.room_id;
  return new;
end $$;
drop trigger if exists labelle_msgs_touch on public.labelle_msgs;
create trigger labelle_msgs_touch after insert on public.labelle_msgs
  for each row execute function public.labelle_msgs_touch();

-- arquivos do chat: so quem participa da conversa abre (pasta chat/<sala>/...)
create or replace function public.labelle_file_ok(p_name text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if p_name not like 'chat/%' then return public.labelle_is_staff(); end if;
  return public.labelle_room_ok(split_part(p_name, '/', 2)::uuid);
exception when others then return false;
end $$;
drop policy if exists "labelle files ver" on storage.objects;
create policy "labelle files ver" on storage.objects for select to authenticated
  using (bucket_id = 'labelle-files' and public.labelle_file_ok(name));

insert into public.labelle_rooms (kind, name, created_by)
select 'all', '전체 공지', 'system' where not exists (select 1 from public.labelle_rooms where kind = 'all');

------------------------------------------------------------
-- 2) CONVERSAS DE CLIENTES (chatbot → atendente)
--    O cliente nao tem login: ele so acessa a propria conversa
--    por um codigo secreto (token) e por funcoes controladas.
------------------------------------------------------------
create table if not exists public.labelle_threads (
  id uuid primary key default gen_random_uuid(),
  token uuid not null unique default gen_random_uuid(),
  created_at timestamptz default now(),
  last_at timestamptz default now(),
  lang text,
  coord_slug text,
  coordinator text,
  name text,
  nationality text,
  messenger text,
  messenger_id text,
  phone text,
  status text default 'bot' check (status in ('bot','waiting','open','closed')),
  assigned text,
  lead_id uuid,
  staff_unread int default 0,
  emergency boolean default false
);
create table if not exists public.labelle_thread_msgs (
  id bigserial primary key,
  thread_id uuid not null references public.labelle_threads(id) on delete cascade,
  sender text not null check (sender in ('customer','bot','staff','system')),
  staff_name text,
  body text not null,
  faq_id text,
  created_at timestamptz default now()
);
create index if not exists labelle_thread_msgs_idx on public.labelle_thread_msgs (thread_id, id);

alter table public.labelle_threads enable row level security;
alter table public.labelle_thread_msgs enable row level security;
drop policy if exists "equipe conversas" on public.labelle_threads;
drop policy if exists "equipe conversas msgs" on public.labelle_thread_msgs;
create policy "equipe conversas" on public.labelle_threads for all
  using (public.labelle_is_staff()) with check (public.labelle_is_staff());
create policy "equipe conversas msgs" on public.labelle_thread_msgs for all
  using (public.labelle_is_staff()) with check (public.labelle_is_staff() and sender in ('staff','system'));

create or replace function public.labelle_thread_touch()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.labelle_threads set last_at = new.created_at,
    staff_unread = case when new.sender = 'customer' then staff_unread + 1
                        when new.sender = 'staff' then 0 else staff_unread end,
    status = case when new.sender = 'staff' and status in ('bot','waiting') then 'open' else status end
  where id = new.thread_id;
  return new;
end $$;
drop trigger if exists labelle_thread_touch on public.labelle_thread_msgs;
create trigger labelle_thread_touch after insert on public.labelle_thread_msgs
  for each row execute function public.labelle_thread_touch();

-- cliente: abre conversa
create or replace function public.labelle_bot_start(p_lang text, p_slug text)
returns uuid language plpgsql security definer set search_path = public as $$
declare t uuid; c text;
begin
  select s.name into c from public.labelle_staff s where s.slug = lower(p_slug) and coalesce(s.active, true) limit 1;
  insert into public.labelle_threads (lang, coord_slug, coordinator)
  values (left(p_lang, 5), nullif(lower(p_slug), ''), c) returning token into t;
  return t;
end $$;

-- cliente: envia mensagem (a resposta automatica do bot tambem passa por aqui)
create or replace function public.labelle_bot_post(p_token uuid, p_sender text, p_body text, p_faq text default null, p_emergency boolean default false)
returns bigint language plpgsql security definer set search_path = public as $$
declare th uuid; n int; i bigint;
begin
  if p_sender not in ('customer','bot') then raise exception 'sender'; end if;
  select id into th from public.labelle_threads where token = p_token and status <> 'closed';
  if th is null then raise exception 'thread'; end if;
  select count(*) into n from public.labelle_thread_msgs where thread_id = th;
  if n >= 400 then raise exception 'limit'; end if;
  insert into public.labelle_thread_msgs (thread_id, sender, body, faq_id)
  values (th, p_sender, left(coalesce(p_body, ''), 2000), left(p_faq, 20)) returning id into i;
  if p_emergency then update public.labelle_threads set emergency = true where id = th; end if;
  return i;
end $$;

-- cliente: le a propria conversa
create or replace function public.labelle_bot_fetch(p_token uuid, p_after bigint)
returns table (id bigint, sender text, staff_name text, body text, created_at timestamptz, status text)
language sql stable security definer set search_path = public as $$
  select m.id, m.sender, m.staff_name, m.body, m.created_at, t.status
  from public.labelle_thread_msgs m join public.labelle_threads t on t.id = m.thread_id
  where t.token = p_token and m.id > coalesce(p_after, 0)
  order by m.id limit 200;
$$;

-- cliente: pede atendente humano (cria tambem o pedido de consulta em 상담 관리)
create or replace function public.labelle_bot_handoff(p_token uuid, p_name text, p_nationality text,
  p_messenger text, p_messenger_id text, p_phone text, p_note text,
  p_privacy boolean, p_sensitive boolean, p_third boolean)
returns boolean language plpgsql security definer set search_path = public as $$
declare th public.labelle_threads; lid uuid;
begin
  select * into th from public.labelle_threads where token = p_token;
  if th.id is null then raise exception 'thread'; end if;
  if not (p_privacy and p_sensitive and p_third) then raise exception 'consent'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name'; end if;
  if th.lead_id is null then
    insert into public.labelle_leads (form_lang, name, nationality, phone, messenger, messenger_id, message,
      coord_slug, coordinator, consent_privacy, consent_sensitive, consent_third, consent_version, status)
    values (th.lang, left(p_name, 80), left(p_nationality, 30), left(p_phone, 40), left(p_messenger, 30), left(p_messenger_id, 80),
      left('[챗봇] ' || coalesce(p_note, ''), 1500), th.coord_slug, th.coordinator, true, true, true, 'bot-2026-10-v1', 'new')
    returning id into lid;
  end if;
  update public.labelle_threads set name = left(p_name, 80), nationality = left(p_nationality, 30),
    messenger = left(p_messenger, 30), messenger_id = left(p_messenger_id, 80), phone = left(p_phone, 40),
    lead_id = coalesce(lead_id, lid), status = case when status = 'bot' then 'waiting' else status end
  where id = th.id;
  insert into public.labelle_thread_msgs (thread_id, sender, body) values (th.id, 'system', '상담원 연결 요청');
  update public.labelle_threads set staff_unread = staff_unread + 1 where id = th.id;
  return true;
end $$;

grant execute on function public.labelle_bot_start(text, text) to anon, authenticated;
grant execute on function public.labelle_bot_post(uuid, text, text, text, boolean) to anon, authenticated;
grant execute on function public.labelle_bot_fetch(uuid, bigint) to anon, authenticated;
grant execute on function public.labelle_bot_handoff(uuid, text, text, text, text, text, text, boolean, boolean, boolean) to anon, authenticated;

------------------------------------------------------------
-- 3) FAQ (base de conhecimento do chatbot) — 5 idiomas
--    status: draft (rascunho) → approved (o cliente so ve os aprovados)
------------------------------------------------------------
create table if not exists public.labelle_faq (
  id text primary key,
  cat jsonb,
  q jsonb not null,
  a jsonb not null,
  kw jsonb default '{}'::jsonb,
  link boolean default false,
  emergency boolean default false,
  status text default 'draft' check (status in ('draft','approved','hidden')),
  sort int default 0,
  updated_at timestamptz default now(),
  updated_by text
);
alter table public.labelle_faq enable row level security;
drop policy if exists "faq publico" on public.labelle_faq;
drop policy if exists "faq equipe ve" on public.labelle_faq;
drop policy if exists "faq adm edita" on public.labelle_faq;
create policy "faq publico" on public.labelle_faq for select to anon using (status = 'approved');
create policy "faq equipe ve" on public.labelle_faq for select to authenticated using (status = 'approved' or public.labelle_is_staff());
create policy "faq adm edita" on public.labelle_faq for all using (public.labelle_is_adm()) with check (public.labelle_is_adm());

------------------------------------------------------------
-- 4) TEMPO REAL (mensagens chegam na hora)
------------------------------------------------------------
do $$ begin
  begin alter publication supabase_realtime add table public.labelle_msgs; exception when others then null; end;
  begin alter publication supabase_realtime add table public.labelle_thread_msgs; exception when others then null; end;
  begin alter publication supabase_realtime add table public.labelle_threads; exception when others then null; end;
end $$;

------------------------------------------------------------
-- 5) 40 perguntas iniciais (rascunho). Ja existentes nao sao sobrescritas.
------------------------------------------------------------
insert into public.labelle_faq (id, cat, q, a, kw, link, emergency, status, sort) values
('FAQ-001', '{"ko": "플랫폼 소개 및 이용 안내", "en": "About LA BELLE LB", "mn": "LA BELLE LB-ийн тухай", "zh": "关于 LA BELLE LB", "pt": "Sobre a LA BELLE LB"}'::jsonb, '{"ko": "LA BELLE LB는 어떤 서비스를 제공하나요?", "en": "What services does LA BELLE LB provide?", "mn": "LA BELLE LB ямар үйлчилгээ үзүүлдэг вэ?", "zh": "LA BELLE LB 提供哪些服务？", "pt": "Quais serviços a LA BELLE LB oferece?"}'::jsonb, '{"ko": "LA BELLE LB는 해외 고객과 한국 의료기관을 연결하는 글로벌 의료관광 플랫폼입니다. 병원 상담, 진료 예약, 의료관광 일정 조율 및 K-Beauty·웰니스 연계 서비스를 안내합니다.", "en": "LA BELLE LB is a global medical tourism platform connecting international clients with Korean medical institutions. We guide you through hospital consultations, appointment booking, medical travel scheduling, and linked K-Beauty and wellness services.", "mn": "LA BELLE LB нь гадаадын үйлчлүүлэгчдийг Солонгосын эмнэлгүүдтэй холбодог дэлхийн эмчилгээний аялал жуулчлалын платформ юм. Эмнэлгийн зөвлөгөө, цаг захиалга, эмчилгээний аяллын хуваарь болон K-Beauty, эрүүл мэндийн үйлчилгээг зохион байгуулахад тусална.", "zh": "LA BELLE LB 是连接海外客户与韩国医疗机构的全球医疗旅游平台，提供医院咨询、就诊预约、医疗旅游行程安排以及 K-Beauty·健康养生相关服务。", "pt": "A LA BELLE LB é uma plataforma global de turismo médico que conecta clientes estrangeiros a instituições médicas da Coreia. Orientamos consultas hospitalares, agendamentos, a organização da viagem médica e serviços integrados de K-Beauty e bem-estar."}'::jsonb, '{}'::jsonb, false, false, 'draft', 1),
('FAQ-002', '{"ko": "플랫폼 소개 및 이용 안내", "en": "About LA BELLE LB", "mn": "LA BELLE LB-ийн тухай", "zh": "关于 LA BELLE LB", "pt": "Sobre a LA BELLE LB"}'::jsonb, '{"ko": "외국인도 한국 병원에서 진료받을 수 있나요?", "en": "Can foreigners receive treatment at Korean hospitals?", "mn": "Гадаад хүн Солонгосын эмнэлэгт эмчлүүлж болох уу?", "zh": "外国人可以在韩国医院就诊吗？", "pt": "Estrangeiros podem se tratar em hospitais coreanos?"}'::jsonb, '{"ko": "네. 외국인도 한국 의료기관에서 진료받을 수 있습니다. 진료 가능 여부와 준비사항은 병원 및 고객의 건강 상태에 따라 달라집니다.", "en": "Yes. Foreigners can receive treatment at Korean medical institutions. Eligibility and preparation depend on the hospital and on your health condition.", "mn": "Тийм. Гадаадын иргэд Солонгосын эмнэлэгт эмчлүүлэх боломжтой. Эмчлүүлэх боломж болон бэлтгэл нь эмнэлэг болон таны эрүүл мэндийн байдлаас хамаарна.", "zh": "可以。外国人可以在韩国医疗机构就诊。能否就诊及所需准备会根据医院和客户的健康状况而有所不同。", "pt": "Sim. Estrangeiros podem receber tratamento em instituições médicas coreanas. A possibilidade de atendimento e a preparação necessária dependem do hospital e do seu estado de saúde."}'::jsonb, '{}'::jsonb, false, false, 'draft', 2),
('FAQ-003', '{"ko": "플랫폼 소개 및 이용 안내", "en": "About LA BELLE LB", "mn": "LA BELLE LB-ийн тухай", "zh": "关于 LA BELLE LB", "pt": "Sobre a LA BELLE LB"}'::jsonb, '{"ko": "어떤 진료 분야를 상담할 수 있나요?", "en": "Which medical fields can I consult about?", "mn": "Ямар чиглэлээр зөвлөгөө авч болох вэ?", "zh": "可以咨询哪些医疗领域？", "pt": "Sobre quais áreas médicas posso pedir consulta?"}'::jsonb, '{"ko": "성형외과, 피부과, 치과, 건강검진, 정형외과 및 척추 관련 진료 등 다양한 분야의 상담을 접수합니다. 실제 병원 연결 가능 여부는 확인 후 안내합니다.", "en": "We accept inquiries in many fields, including plastic surgery, dermatology, dentistry, health check-ups, orthopedics and spine care. We will confirm whether a hospital connection is possible and let you know.", "mn": "Гоо сайхны мэс засал, арьс, шүд, эрүүл мэндийн үзлэг, ортопед, нурууны эмчилгээ зэрэг олон чиглэлээр хүсэлт хүлээн авна. Эмнэлэгтэй холбох боломжийг шалгаад танд мэдэгдэнэ.", "zh": "我们受理整形外科、皮肤科、牙科、健康体检、骨科及脊柱等多个领域的咨询。能否对接医院将在确认后通知您。", "pt": "Recebemos pedidos em diversas áreas, como cirurgia plástica, dermatologia, odontologia, check-up, ortopedia e coluna. Confirmamos se é possível a conexão com um hospital e avisamos você."}'::jsonb, '{"ko": "성형 코 눈 쌍꺼풀 피부 치과 건강검진", "en": "plastic surgery nose eyes skin dental checkup", "mn": "хамар нүд арьс шүд хамар хамрын зовхи", "zh": "整形 鼻子 眼睛 双眼皮 皮肤 牙科 体检", "pt": "plástica nariz olhos pele dentista check-up"}'::jsonb, true, false, 'draft', 3),
('FAQ-004', '{"ko": "플랫폼 소개 및 이용 안내", "en": "About LA BELLE LB", "mn": "LA BELLE LB-ийн тухай", "zh": "关于 LA BELLE LB", "pt": "Sobre a LA BELLE LB"}'::jsonb, '{"ko": "원하는 병원을 직접 선택할 수 있나요?", "en": "Can I choose the hospital myself?", "mn": "Эмнэлгээ өөрөө сонгож болох уу?", "zh": "可以自己选择医院吗？", "pt": "Posso escolher o hospital?"}'::jsonb, '{"ko": "네. 희망하는 병원이나 의료진이 있다면 알려주세요. 해당 의료기관과의 상담 및 예약 연계 가능 여부를 확인해 드립니다.", "en": "Yes. If you have a preferred hospital or doctor, please tell us. We will check whether a consultation and booking with that institution can be arranged.", "mn": "Тийм. Хүссэн эмнэлэг эсвэл эмч байвал бидэнд хэлээрэй. Тухайн эмнэлэгтэй зөвлөгөө, цаг захиалах боломжийг шалгаж өгнө.", "zh": "可以。如果您有希望的医院或医生，请告诉我们。我们会确认能否与该医疗机构安排咨询和预约。", "pt": "Sim. Se tiver um hospital ou médico de preferência, informe-nos. Verificaremos se é possível marcar consulta e agendamento com essa instituição."}'::jsonb, '{}'::jsonb, false, false, 'draft', 4),
('FAQ-005', '{"ko": "플랫폼 소개 및 이용 안내", "en": "About LA BELLE LB", "mn": "LA BELLE LB-ийн тухай", "zh": "关于 LA BELLE LB", "pt": "Sobre a LA BELLE LB"}'::jsonb, '{"ko": "한국어를 못해도 이용할 수 있나요?", "en": "Can I use the service without speaking Korean?", "mn": "Солонгос хэл мэдэхгүй ч ашиглаж болох уу?", "zh": "不会韩语也可以使用吗？", "pt": "Posso usar o serviço sem falar coreano?"}'::jsonb, '{"ko": "네. 외국어 상담 및 통역 지원 가능 여부를 확인해 드립니다. 지원 언어와 통역 비용은 상담 시 안내합니다.", "en": "Yes. We will check the availability of foreign-language consultation and interpreter support. Supported languages and interpreter fees are explained during the consultation.", "mn": "Тийм. Гадаад хэлээрх зөвлөгөө болон орчуулагчийн дэмжлэгийн боломжийг шалгаж өгнө. Дэмжих хэл болон орчуулагчийн төлбөрийг зөвлөгөөний үеэр мэдэгдэнэ.", "zh": "可以。我们会确认外语咨询及翻译支持的可能性。支持的语言和翻译费用将在咨询时告知。", "pt": "Sim. Verificamos a disponibilidade de atendimento em idioma estrangeiro e de intérprete. Os idiomas disponíveis e o custo do intérprete são informados na consulta."}'::jsonb, '{"ko": "통역 언어 몽골어", "en": "interpreter language translator", "mn": "орчуулагч хэл", "zh": "翻译 语言", "pt": "intérprete idioma tradutor"}'::jsonb, false, false, 'draft', 5),
('FAQ-006', '{"ko": "플랫폼 소개 및 이용 안내", "en": "About LA BELLE LB", "mn": "LA BELLE LB-ийн тухай", "zh": "关于 LA BELLE LB", "pt": "Sobre a LA BELLE LB"}'::jsonb, '{"ko": "상담은 무료인가요?", "en": "Is the consultation free?", "mn": "Зөвлөгөө үнэгүй юу?", "zh": "咨询免费吗？", "pt": "A consulta é gratuita?"}'::jsonb, '{"ko": "기본 서비스 문의는 무료로 접수할 수 있습니다. 다만 의료진 상담, 화상 상담 또는 전문 서비스에는 별도 비용이 발생할 수 있으며 사전에 안내합니다.", "en": "General service inquiries are free. However, consultations with doctors, video consultations or specialized services may involve separate fees, which we will inform you of in advance.", "mn": "Үйлчилгээний ерөнхий лавлагаа үнэгүй. Харин эмчийн зөвлөгөө, видео зөвлөгөө эсвэл тусгай үйлчилгээнд нэмэлт төлбөр гарч болох бөгөөд урьдчилан мэдэгдэнэ.", "zh": "一般服务咨询免费。但医生面诊、视频咨询或专业服务可能会产生额外费用，我们会事先告知。", "pt": "Pedidos de informação sobre o serviço são gratuitos. Consultas com médicos, consultas por vídeo ou serviços especializados podem ter custo à parte, sempre informado com antecedência."}'::jsonb, '{"ko": "무료 비용 상담료", "en": "free fee", "mn": "үнэгүй төлбөр", "zh": "免费 收费", "pt": "grátis gratuito preço"}'::jsonb, true, false, 'draft', 6),
('FAQ-007', '{"ko": "의료 상담 및 병원 예약", "en": "Medical consultation & hospital booking", "mn": "Эмчийн зөвлөгөө ба эмнэлгийн цаг", "zh": "医疗咨询与医院预约", "pt": "Consulta médica e agendamento"}'::jsonb, '{"ko": "병원 상담은 어떻게 신청하나요?", "en": "How do I request a hospital consultation?", "mn": "Эмнэлгийн зөвлөгөөнд хэрхэн хүсэлт гаргах вэ?", "zh": "如何申请医院咨询？", "pt": "Como solicito uma consulta no hospital?"}'::jsonb, '{"ko": "희망 진료 분야와 방문 예정일, 기본 연락처를 알려주세요. 담당자가 내용을 확인하고 상담 절차를 안내합니다.", "en": "Please tell us the medical field you are interested in, your planned visit date and your basic contact details. A staff member will review your request and guide you through the consultation process.", "mn": "Сонирхож буй эмчилгээний чиглэл, ирэх товлосон огноо, холбоо барих мэдээллээ үлдээнэ үү. Хариуцсан ажилтан шалгаад зөвлөгөөний дарааллыг танилцуулна.", "zh": "请告诉我们希望的就诊领域、预计来访日期和基本联系方式。负责人确认后会为您说明咨询流程。", "pt": "Informe a área de interesse, a data prevista da visita e seus dados de contato. Um responsável analisará o pedido e explicará os próximos passos."}'::jsonb, '{"ko": "상담 신청 예약 연락", "en": "book consultation contact appointment", "mn": "зөвлөгөө хүсэлт цаг захиалах", "zh": "申请 咨询 预约", "pt": "agendar consulta marcar"}'::jsonb, true, false, 'draft', 7),
('FAQ-008', '{"ko": "의료 상담 및 병원 예약", "en": "Medical consultation & hospital booking", "mn": "Эмчийн зөвлөгөө ба эмнэлгийн цаг", "zh": "医疗咨询与医院预约", "pt": "Consulta médica e agendamento"}'::jsonb, '{"ko": "한국에 방문하기 전에 온라인 상담이 가능한가요?", "en": "Can I have an online consultation before visiting Korea?", "mn": "Солонгост ирэхээс өмнө онлайн зөвлөгөө авч болох уу?", "zh": "来韩国之前可以在线咨询吗？", "pt": "Posso fazer uma consulta online antes de ir à Coreia?"}'::jsonb, '{"ko": "병원별 운영 방식에 따라 사전 상담이나 화상 상담을 조율할 수 있습니다. 상담 가능 일정은 별도로 확인해야 합니다.", "en": "Depending on each hospital''s policy, a pre-consultation or video consultation can be arranged. Available consultation times must be confirmed separately.", "mn": "Эмнэлэг бүрийн журмаас хамааран урьдчилсан эсвэл видео зөвлөгөө зохион байгуулах боломжтой. Зөвлөгөөний цагийг тусад нь баталгаажуулна.", "zh": "根据各医院的运营方式，可以安排事前咨询或视频咨询。可咨询的时间需另行确认。", "pt": "Dependendo de cada hospital, é possível combinar uma pré-consulta ou consulta por vídeo. Os horários disponíveis precisam ser confirmados à parte."}'::jsonb, '{}'::jsonb, true, false, 'draft', 8),
('FAQ-009', '{"ko": "의료 상담 및 병원 예약", "en": "Medical consultation & hospital booking", "mn": "Эмчийн зөвлөгөө ба эмнэлгийн цаг", "zh": "医疗咨询与医院预约", "pt": "Consulta médica e agendamento"}'::jsonb, '{"ko": "사진으로 수술 상담을 받을 수 있나요?", "en": "Can I get a surgery consultation with photos?", "mn": "Зургаар мэс заслын зөвлөгөө авч болох уу?", "zh": "可以通过照片进行手术咨询吗？", "pt": "Posso fazer a consulta de cirurgia por fotos?"}'::jsonb, '{"ko": "의료기관의 상담 절차에 따라 사진을 참고자료로 제출할 수 있습니다. 사진만으로 정확한 진단이나 수술 가능 여부를 확정할 수는 없습니다.", "en": "Depending on the hospital''s consultation process, you may submit photos as reference material. However, photos alone cannot confirm an accurate diagnosis or whether surgery is possible.", "mn": "Эмнэлгийн журмын дагуу зургийг лавлагаа болгон илгээж болно. Гэхдээ зөвхөн зургаар оношийг эсвэл мэс засал хийх боломжийг баттай тогтоох боломжгүй.", "zh": "根据医疗机构的咨询流程，可以提交照片作为参考资料。但仅凭照片无法确定准确诊断或能否手术。", "pt": "Conforme o procedimento do hospital, você pode enviar fotos como referência. Mas somente por fotos não é possível confirmar um diagnóstico preciso nem se a cirurgia é viável."}'::jsonb, '{}'::jsonb, true, false, 'draft', 9),
('FAQ-010', '{"ko": "의료 상담 및 병원 예약", "en": "Medical consultation & hospital booking", "mn": "Эмчийн зөвлөгөө ба эмнэлгийн цаг", "zh": "医疗咨询与医院预约", "pt": "Consulta médica e agendamento"}'::jsonb, '{"ko": "병원 예약은 언제 확정되나요?", "en": "When is my hospital appointment confirmed?", "mn": "Эмнэлгийн цаг хэзээ баталгаажих вэ?", "zh": "医院预约什么时候确定？", "pt": "Quando o agendamento no hospital é confirmado?"}'::jsonb, '{"ko": "병원에서 진료 가능 일정과 예약 조건을 확인한 후 예약이 확정됩니다. 상담 신청만으로 예약이 완료되는 것은 아닙니다.", "en": "Your appointment is confirmed after the hospital checks available dates and booking conditions. Submitting a consultation request alone does not complete a booking.", "mn": "Эмнэлэг боломжит өдөр, захиалгын нөхцөлийг шалгасны дараа цаг баталгаажна. Зөвхөн зөвлөгөөний хүсэлт илгээснээр захиалга дуусахгүй.", "zh": "医院确认可就诊日期和预约条件后，预约才会确定。仅提交咨询申请并不代表预约完成。", "pt": "O agendamento é confirmado depois que o hospital verifica a disponibilidade de datas e as condições. Apenas enviar o pedido de consulta não conclui a reserva."}'::jsonb, '{}'::jsonb, true, false, 'draft', 10),
('FAQ-011', '{"ko": "의료 상담 및 병원 예약", "en": "Medical consultation & hospital booking", "mn": "Эмчийн зөвлөгөө ба эмнэлгийн цаг", "zh": "医疗咨询与医院预约", "pt": "Consulta médica e agendamento"}'::jsonb, '{"ko": "여러 병원을 비교할 수 있나요?", "en": "Can I compare several hospitals?", "mn": "Хэд хэдэн эмнэлгийг харьцуулж болох уу?", "zh": "可以比较多家医院吗？", "pt": "Posso comparar vários hospitais?"}'::jsonb, '{"ko": "희망 진료 분야와 조건을 알려주시면 비교 상담이 가능한 의료기관을 확인해 드립니다.", "en": "Tell us the medical field and conditions you want, and we will find institutions that can offer comparison consultations.", "mn": "Хүссэн чиглэл, нөхцөлөө хэлбэл харьцуулсан зөвлөгөө өгөх боломжтой эмнэлгүүдийг шалгаж өгнө.", "zh": "请告诉我们希望的就诊领域和条件，我们会为您确认可进行比较咨询的医疗机构。", "pt": "Informe a área e as condições desejadas e indicaremos instituições onde é possível fazer consultas comparativas."}'::jsonb, '{}'::jsonb, false, false, 'draft', 11),
('FAQ-012', '{"ko": "의료 상담 및 병원 예약", "en": "Medical consultation & hospital booking", "mn": "Эмчийн зөвлөгөө ба эмнэлгийн цаг", "zh": "医疗咨询与医院预约", "pt": "Consulta médica e agendamento"}'::jsonb, '{"ko": "의료진을 직접 선택할 수 있나요?", "en": "Can I choose my doctor?", "mn": "Эмчээ сонгож болох уу?", "zh": "可以指定医生吗？", "pt": "Posso escolher o médico?"}'::jsonb, '{"ko": "희망 의료진을 요청하실 수 있습니다. 실제 예약 가능 여부는 의료진 일정과 병원 운영 상황에 따라 달라집니다.", "en": "You may request a preferred doctor. Actual availability depends on the doctor''s schedule and the hospital''s operations.", "mn": "Хүссэн эмчээ хүсэлтээр сонгох боломжтой. Бодит боломж нь эмчийн хуваарь болон эмнэлгийн ажиллагаанаас хамаарна.", "zh": "您可以申请希望的医生。能否实际预约取决于医生日程和医院运营情况。", "pt": "Você pode solicitar um médico de preferência. A disponibilidade depende da agenda do médico e da operação do hospital."}'::jsonb, '{}'::jsonb, false, false, 'draft', 12),
('FAQ-013', '{"ko": "의료 상담 및 병원 예약", "en": "Medical consultation & hospital booking", "mn": "Эмчийн зөвлөгөө ба эмнэлгийн цаг", "zh": "医疗咨询与医院预约", "pt": "Consulta médica e agendamento"}'::jsonb, '{"ko": "상담 후 반드시 수술해야 하나요?", "en": "Do I have to have surgery after the consultation?", "mn": "Зөвлөгөө авсны дараа заавал мэс засал хийлгэх ёстой юу?", "zh": "咨询后必须做手术吗？", "pt": "Sou obrigado(a) a operar depois da consulta?"}'::jsonb, '{"ko": "아니요. 상담 후 치료 여부는 고객이 결정할 수 있습니다. 의료진의 설명을 충분히 듣고 신중하게 결정하시기 바랍니다.", "en": "No. You decide whether to proceed with treatment after the consultation. Please listen carefully to the doctor''s explanation and make a careful decision.", "mn": "Үгүй. Эмчилгээ хийлгэх эсэхээ зөвлөгөөний дараа та өөрөө шийднэ. Эмчийн тайлбарыг сайн сонсож, болгоомжтой шийдвэр гаргаарай.", "zh": "不是。咨询后是否治疗由客户自己决定。请充分听取医生的说明后慎重决定。", "pt": "Não. Após a consulta, a decisão sobre o tratamento é sua. Ouça com atenção as explicações do médico e decida com calma."}'::jsonb, '{}'::jsonb, true, false, 'draft', 13),
('FAQ-014', '{"ko": "수술·시술 및 의료 안전", "en": "Surgery, procedures & medical safety", "mn": "Мэс засал, эмчилгээ ба аюулгүй байдал", "zh": "手术·治疗与医疗安全", "pt": "Cirurgias, procedimentos e segurança"}'::jsonb, '{"ko": "수술 비용은 어떻게 확인하나요?", "en": "How can I find out the cost of surgery?", "mn": "Мэс заслын үнийг хэрхэн мэдэх вэ?", "zh": "如何了解手术费用？", "pt": "Como sei o valor da cirurgia?"}'::jsonb, '{"ko": "희망 시술, 수술 범위, 병원 및 의료진의 판단에 따라 비용이 달라집니다. 상담 정보를 바탕으로 의료기관에 확인한 후 개별 견적을 안내합니다.", "en": "Costs vary depending on the desired procedure, the scope of surgery, and the judgment of the hospital and doctor. Based on your consultation details, we check with the medical institution and provide an individual quote.", "mn": "Үнэ нь хүссэн эмчилгээ, мэс заслын хэмжээ, эмнэлэг болон эмчийн дүгнэлтээс хамаарна. Зөвлөгөөний мэдээлэлд үндэслэн эмнэлэгтэй шалгаад тусгай үнийн санал өгнө.", "zh": "费用会根据希望的项目、手术范围以及医院和医生的判断而不同。我们将根据咨询信息向医疗机构确认后提供个别报价。", "pt": "O valor varia conforme o procedimento desejado, a extensão da cirurgia e a avaliação do hospital e do médico. Com base nas informações da consulta, verificamos com a instituição e enviamos um orçamento individual."}'::jsonb, '{"ko": "가격 비용 얼마 견적", "en": "price cost how much", "mn": "үнэ хэд төлбөр хэдэн төгрөг", "zh": "价格 多少钱 费用", "pt": "preço valor quanto custa orçamento custa"}'::jsonb, true, false, 'draft', 14),
('FAQ-015', '{"ko": "수술·시술 및 의료 안전", "en": "Surgery, procedures & medical safety", "mn": "Мэс засал, эмчилгээ ба аюулгүй байдал", "zh": "手术·治疗与医疗安全", "pt": "Cirurgias, procedimentos e segurança"}'::jsonb, '{"ko": "안내받은 견적에 모든 비용이 포함되나요?", "en": "Does the quote include all costs?", "mn": "Үнийн саналд бүх зардал багтсан уу?", "zh": "报价包含所有费用吗？", "pt": "O orçamento inclui todos os custos?"}'::jsonb, '{"ko": "견적마다 포함 항목이 다를 수 있습니다. 진료비, 검사비, 마취비, 입원비, 약제비 및 사후관리비 등 포함·제외 항목을 확인해 주세요.", "en": "Included items may differ between quotes. Please check which items are included or excluded, such as treatment, tests, anesthesia, hospitalization, medication and aftercare fees.", "mn": "Үнийн санал бүрт багтах зүйл өөр байж болно. Эмчилгээ, шинжилгээ, мэдээ алдуулалт, хэвтэн эмчлүүлэх, эм, мэс заслын дараах хяналтын төлбөр зэрэг багтсан, багтаагүй зүйлсийг шалгана уу.", "zh": "每份报价包含的项目可能不同。请确认诊疗费、检查费、麻醉费、住院费、药费及术后管理费等包含与不包含的项目。", "pt": "Os itens incluídos podem variar. Confira o que está incluído ou não, como honorários, exames, anestesia, internação, medicamentos e acompanhamento pós-operatório."}'::jsonb, '{}'::jsonb, true, false, 'draft', 15),
('FAQ-016', '{"ko": "수술·시술 및 의료 안전", "en": "Surgery, procedures & medical safety", "mn": "Мэс засал, эмчилгээ ба аюулгүй байдал", "zh": "手术·治疗与医疗安全", "pt": "Cirurgias, procedimentos e segurança"}'::jsonb, '{"ko": "여러 수술을 동시에 받을 수 있나요?", "en": "Can I have several surgeries at the same time?", "mn": "Хэд хэдэн мэс заслыг нэг дор хийлгэж болох уу?", "zh": "可以同时做多项手术吗？", "pt": "Posso fazer várias cirurgias ao mesmo tempo?"}'::jsonb, '{"ko": "동시 수술 가능 여부는 환자의 건강 상태, 수술 범위 및 마취 위험 등을 고려하여 의료진이 판단합니다.", "en": "Whether simultaneous surgeries are possible is decided by the medical team, considering your health condition, the scope of surgery and anesthesia risks.", "mn": "Нэг дор мэс засал хийх боломжийг өвчтөний биеийн байдал, мэс заслын хэмжээ, мэдээ алдуулалтын эрсдэлийг харгалзан эмч шийднэ.", "zh": "能否同时手术由医生根据患者的健康状况、手术范围及麻醉风险等综合判断。", "pt": "A equipe médica decide se cirurgias simultâneas são possíveis, considerando seu estado de saúde, a extensão das cirurgias e os riscos da anestesia."}'::jsonb, '{}'::jsonb, false, false, 'draft', 16),
('FAQ-017', '{"ko": "수술·시술 및 의료 안전", "en": "Surgery, procedures & medical safety", "mn": "Мэс засал, эмчилгээ ба аюулгүй байдал", "zh": "手术·治疗与医疗安全", "pt": "Cirurgias, procedimentos e segurança"}'::jsonb, '{"ko": "수술 결과를 보장하나요?", "en": "Are surgery results guaranteed?", "mn": "Мэс заслын үр дүнг баталгаажуулдаг уу?", "zh": "手术效果有保证吗？", "pt": "O resultado da cirurgia é garantido?"}'::jsonb, '{"ko": "의료행위의 결과는 개인마다 다르며 특정 결과를 보장할 수 없습니다. 기대 효과와 부작용, 합병증 가능성을 의료진에게 충분히 확인하시기 바랍니다.", "en": "Results of medical procedures vary from person to person and no specific outcome can be guaranteed. Please discuss expected effects, side effects and possible complications thoroughly with your doctor.", "mn": "Эмчилгээний үр дүн хүн бүрт өөр бөгөөд тодорхой үр дүнг баталгаажуулах боломжгүй. Хүлээгдэж буй үр дүн, гаж нөлөө, хүндрэлийн талаар эмчээсээ сайтар асуугаарай.", "zh": "医疗结果因人而异，无法保证特定效果。请向医生充分确认预期效果、副作用及并发症的可能性。", "pt": "Os resultados de procedimentos médicos variam de pessoa para pessoa e não é possível garantir um resultado específico. Converse bem com o médico sobre efeitos esperados, efeitos colaterais e possíveis complicações."}'::jsonb, '{}'::jsonb, false, false, 'draft', 17),
('FAQ-018', '{"ko": "수술·시술 및 의료 안전", "en": "Surgery, procedures & medical safety", "mn": "Мэс засал, эмчилгээ ба аюулгүй байдал", "zh": "手术·治疗与医疗安全", "pt": "Cirurgias, procedimentos e segurança"}'::jsonb, '{"ko": "기저질환이 있어도 수술받을 수 있나요?", "en": "Can I have surgery if I have an underlying condition?", "mn": "Архаг өвчтэй байсан ч мэс засал хийлгэж болох уу?", "zh": "有基础疾病也可以做手术吗？", "pt": "Posso operar se tiver alguma doença preexistente?"}'::jsonb, '{"ko": "기저질환과 복용 중인 약물은 수술 안전성에 영향을 줄 수 있습니다. 의료진에게 관련 정보를 정확히 알려주셔야 하며, 수술 가능 여부는 진료 후 결정됩니다.", "en": "Underlying conditions and medications you take can affect surgical safety. Please give the medical team accurate information; whether surgery is possible will be decided after examination.", "mn": "Архаг өвчин болон хэрэглэж буй эм нь мэс заслын аюулгүй байдалд нөлөөлж болно. Эмчид үнэн зөв мэдээлэл өгөх шаардлагатай бөгөөд боломжийг үзлэгийн дараа шийднэ.", "zh": "基础疾病和正在服用的药物可能影响手术安全。请如实告知医生相关信息，能否手术将在诊疗后决定。", "pt": "Doenças preexistentes e medicamentos em uso podem afetar a segurança da cirurgia. Informe tudo com precisão à equipe médica; a viabilidade será decidida após a avaliação."}'::jsonb, '{}'::jsonb, false, false, 'draft', 18),
('FAQ-019', '{"ko": "수술·시술 및 의료 안전", "en": "Surgery, procedures & medical safety", "mn": "Мэс засал, эмчилгээ ба аюулгүй байдал", "zh": "手术·治疗与医疗安全", "pt": "Cirurgias, procedimentos e segurança"}'::jsonb, '{"ko": "수술 전 어떤 준비가 필요한가요?", "en": "What preparation is needed before surgery?", "mn": "Мэс заслын өмнө ямар бэлтгэл хэрэгтэй вэ?", "zh": "手术前需要做哪些准备？", "pt": "Que preparação é necessária antes da cirurgia?"}'::jsonb, '{"ko": "수술 종류에 따라 필요한 검사, 금식, 약물 관련 주의사항 등이 달라집니다. 담당 의료기관에서 제공하는 수술 전 안내를 따라주세요.", "en": "Required tests, fasting and medication precautions vary by type of surgery. Please follow the pre-surgery instructions provided by your medical institution.", "mn": "Мэс заслын төрлөөс хамааран шинжилгээ, өлөн байх, эмийн анхааруулга зэрэг өөр өөр байна. Эмнэлгээс өгсөн мэс заслын өмнөх зааврыг дагана уу.", "zh": "根据手术种类，所需检查、禁食及用药注意事项等会有所不同。请遵循负责医疗机构提供的术前说明。", "pt": "Exames, jejum e cuidados com medicamentos variam conforme o tipo de cirurgia. Siga as orientações pré-operatórias da instituição responsável."}'::jsonb, '{}'::jsonb, false, false, 'draft', 19),
('FAQ-020', '{"ko": "수술·시술 및 의료 안전", "en": "Surgery, procedures & medical safety", "mn": "Мэс засал, эмчилгээ ба аюулгүй байдал", "zh": "手术·治疗与医疗安全", "pt": "Cirurgias, procedimentos e segurança"}'::jsonb, '{"ko": "수술 후 부작용이 발생하면 어떻게 하나요?", "en": "What should I do if side effects occur after surgery?", "mn": "Мэс заслын дараа гаж нөлөө гарвал яах вэ?", "zh": "术后出现副作用怎么办？", "pt": "O que faço se tiver efeitos colaterais após a cirurgia?"}'::jsonb, '{"ko": "증상이 발생하면 담당 의료기관에 즉시 연락해 주세요. 심한 출혈, 호흡곤란, 의식 변화 등 응급 증상이 있다면 상담 답변을 기다리지 말고 즉시 현지 응급의료서비스를 이용하세요.", "en": "If symptoms occur, contact your medical institution immediately. If you have emergency symptoms such as heavy bleeding, difficulty breathing or a change in consciousness, do not wait for a reply — use local emergency medical services right away.", "mn": "Шинж тэмдэг илэрвэл хариуцсан эмнэлэгтээ нэн даруй холбогдоорой. Их хэмжээний цус алдалт, амьсгал давчдах, ухаан санаа өөрчлөгдөх зэрэг яаралтай шинж тэмдэг байвал хариу хүлээлгүй орон нутгийн түргэн тусламжийн үйлчилгээг яаралтай ашиглана уу.", "zh": "如出现症状，请立即联系负责的医疗机构。如有大量出血、呼吸困难、意识改变等紧急症状，请不要等待咨询回复，立即使用当地急救医疗服务。", "pt": "Se surgir algum sintoma, entre em contato imediatamente com a instituição médica. Em caso de sinais de emergência, como sangramento intenso, falta de ar ou alteração de consciência, não espere a resposta — procure imediatamente o serviço de emergência local."}'::jsonb, '{"ko": "부작용 출혈 피 호흡 숨 열 응급 통증 붓기 감염", "en": "side effect bleeding blood breathing fever emergency pain swelling infection", "mn": "гаж нөлөө цус амьсгал халуурах яаралтай өвдөх хавдах", "zh": "副作用 出血 流血 呼吸 发烧 紧急 疼痛 肿 感染", "pt": "efeito colateral sangramento sangue respirar febre emergência dor inchaço infecção"}'::jsonb, true, true, 'draft', 20),
('FAQ-021', '{"ko": "의료관광 비자 및 입국", "en": "Medical tourism visa & entry", "mn": "Эмчилгээний аялалын виз ба нэвтрэлт", "zh": "医疗旅游签证与入境", "pt": "Visto e entrada no país"}'::jsonb, '{"ko": "한국 방문에 비자가 필요한가요?", "en": "Do I need a visa to visit Korea?", "mn": "Солонгост очиход виз хэрэгтэй юу?", "zh": "访问韩国需要签证吗？", "pt": "Preciso de visto para ir à Coreia?"}'::jsonb, '{"ko": "비자 필요 여부는 국적, 체류기간 및 방문 목적에 따라 다릅니다. 한국 입국 전 해당 국가의 대한민국 공관 또는 공식 비자 안내를 확인해 주세요.", "en": "Visa requirements depend on your nationality, length of stay and purpose of visit. Before entering Korea, please check with the Korean embassy or consulate in your country or the official visa information.", "mn": "Виз шаардлагатай эсэх нь иргэншил, байх хугацаа, зорилгоос хамаарна. Солонгост нэвтрэхээс өмнө өөрийн улс дахь БНСУ-ын Элчин сайдын яам эсвэл албан ёсны визийн мэдээллээс шалгана уу.", "zh": "是否需要签证取决于国籍、停留时间和访问目的。入境韩国前，请向所在国家的韩国驻外使领馆或官方签证信息确认。", "pt": "A necessidade de visto depende da sua nacionalidade, do tempo de estadia e do motivo da viagem. Antes de viajar, consulte a embaixada ou consulado da Coreia no seu país ou as informações oficiais de visto."}'::jsonb, '{"ko": "비자 입국", "en": "visa entry", "mn": "виз", "zh": "签证 入境", "pt": "visto entrada"}'::jsonb, true, false, 'draft', 21),
('FAQ-022', '{"ko": "의료관광 비자 및 입국", "en": "Medical tourism visa & entry", "mn": "Эмчилгээний аялалын виз ба нэвтрэлт", "zh": "医疗旅游签证与入境", "pt": "Visto e entrada no país"}'::jsonb, '{"ko": "의료관광 비자 신청을 지원하나요?", "en": "Do you help with medical tourism visa applications?", "mn": "Эмчилгээний аяллын виз мэдүүлэхэд тусалдаг уу?", "zh": "你们协助申请医疗旅游签证吗？", "pt": "Vocês ajudam com o visto de turismo médico?"}'::jsonb, '{"ko": "의료관광 관련 비자 준비 절차와 필요 서류를 안내할 수 있습니다. 개별 신청 지원 범위는 확인이 필요하며, 비자 발급은 대한민국의 관할 기관이 결정합니다.", "en": "We can explain the visa preparation process and required documents for medical tourism. The scope of individual application support needs to be confirmed, and visas are issued at the discretion of the competent Korean authorities.", "mn": "Эмчилгээний аяллын визийн бэлтгэл, шаардлагатай бичиг баримтын талаар зөвлөж чадна. Хувь хүний мэдүүлгийн дэмжлэгийн хүрээг тодруулах шаардлагатай бөгөөд визийг БНСУ-ын эрх бүхий байгууллага олгоно.", "zh": "我们可以说明医疗旅游签证的准备流程和所需材料。个别申请协助的范围需要确认，签证签发由韩国主管机关决定。", "pt": "Podemos orientar sobre o processo e os documentos do visto de turismo médico. O alcance do apoio individual precisa ser confirmado, e a emissão do visto é decidida pelas autoridades coreanas competentes."}'::jsonb, '{}'::jsonb, true, false, 'draft', 22),
('FAQ-023', '{"ko": "의료관광 비자 및 입국", "en": "Medical tourism visa & entry", "mn": "Эмчилгээний аялалын виз ба нэвтрэлт", "zh": "医疗旅游签证与入境", "pt": "Visto e entrada no país"}'::jsonb, '{"ko": "의료관광 초청장을 받을 수 있나요?", "en": "Can I receive a medical tourism invitation letter?", "mn": "Эмчилгээний аяллын урилга авч болох уу?", "zh": "可以获得医疗旅游邀请函吗？", "pt": "Posso receber uma carta-convite para turismo médico?"}'::jsonb, '{"ko": "초청장 발급 가능 여부는 의료기관, 진료계획 및 신청 조건에 따라 달라집니다. 필요한 정보를 접수한 후 확인해 드립니다.", "en": "Whether an invitation letter can be issued depends on the medical institution, the treatment plan and the application conditions. We will check after receiving the necessary information.", "mn": "Урилга олгох боломж нь эмнэлэг, эмчилгээний төлөвлөгөө, хүсэлтийн нөхцөлөөс хамаарна. Шаардлагатай мэдээллийг хүлээн авсны дараа шалгаж өгнө.", "zh": "能否签发邀请函取决于医疗机构、诊疗计划及申请条件。收到必要信息后我们会为您确认。", "pt": "A emissão da carta-convite depende da instituição médica, do plano de tratamento e das condições do pedido. Verificamos após receber as informações necessárias."}'::jsonb, '{}'::jsonb, true, false, 'draft', 23),
('FAQ-024', '{"ko": "의료관광 비자 및 입국", "en": "Medical tourism visa & entry", "mn": "Эмчилгээний аялалын виз ба нэвтрэлт", "zh": "医疗旅游签证与入境", "pt": "Visto e entrada no país"}'::jsonb, '{"ko": "비자 신청에 어떤 서류가 필요한가요?", "en": "What documents are needed for a visa application?", "mn": "Визийн мэдүүлэгт ямар бичиг баримт хэрэгтэй вэ?", "zh": "申请签证需要哪些材料？", "pt": "Quais documentos são necessários para o visto?"}'::jsonb, '{"ko": "일반적으로 여권, 비자 신청서, 진료 관련 서류, 재정증빙 등이 요구될 수 있습니다. 정확한 서류는 비자 유형과 심사기관의 안내에 따릅니다.", "en": "Generally, a passport, visa application form, medical documents and proof of funds may be required. The exact documents depend on the visa type and the instructions of the reviewing authority.", "mn": "Ерөнхийдөө гадаад паспорт, визийн өргөдөл, эмчилгээний бичиг баримт, санхүүгийн баталгаа зэрэг шаардагдаж болно. Яг ямар баримт хэрэгтэйг визийн төрөл болон хянах байгууллагын зааврын дагуу тогтооно.", "zh": "一般可能需要护照、签证申请表、医疗相关文件、资金证明等。具体材料以签证类型和审核机关的说明为准。", "pt": "Em geral podem ser pedidos passaporte, formulário de visto, documentos médicos e comprovação financeira. Os documentos exatos dependem do tipo de visto e das instruções do órgão responsável."}'::jsonb, '{}'::jsonb, true, false, 'draft', 24),
('FAQ-025', '{"ko": "의료관광 비자 및 입국", "en": "Medical tourism visa & entry", "mn": "Эмчилгээний аялалын виз ба нэвтрэлт", "zh": "医疗旅游签证与入境", "pt": "Visto e entrada no país"}'::jsonb, '{"ko": "가족이나 보호자도 동반할 수 있나요?", "en": "Can family members or a guardian come with me?", "mn": "Гэр бүлийн гишүүн эсвэл асран хамгаалагч хамт ирж болох уу?", "zh": "家人或陪同人员可以一起来吗？", "pt": "Familiares ou acompanhantes podem ir junto?"}'::jsonb, '{"ko": "동반 방문을 계획하실 수 있습니다. 동반자의 입국 자격과 필요 서류는 별도로 확인해야 합니다.", "en": "You may plan to travel with companions. Their entry eligibility and required documents must be checked separately.", "mn": "Хамт аялахаар төлөвлөж болно. Дагалдан яваа хүний нэвтрэх эрх, шаардлагатай бичиг баримтыг тусад нь шалгах шаардлагатай.", "zh": "可以计划陪同来访。陪同人员的入境资格和所需材料需另行确认。", "pt": "Você pode planejar a viagem com acompanhantes. As condições de entrada e os documentos de cada acompanhante devem ser verificados separadamente."}'::jsonb, '{}'::jsonb, false, false, 'draft', 25),
('FAQ-026', '{"ko": "의료관광 비자 및 입국", "en": "Medical tourism visa & entry", "mn": "Эмчилгээний аялалын виз ба нэвтрэлт", "zh": "医疗旅游签证与入境", "pt": "Visto e entrada no país"}'::jsonb, '{"ko": "비자가 거절되면 환불받을 수 있나요?", "en": "Can I get a refund if my visa is refused?", "mn": "Виз татгалзвал мөнгөө буцааж авах уу?", "zh": "签证被拒可以退款吗？", "pt": "Se o visto for negado, recebo reembolso?"}'::jsonb, '{"ko": "비자 거절 시 환불 여부는 각 예약 서비스의 취소·환불 규정과 이미 발생한 비용에 따라 달라집니다. 결제 전에 관련 조건을 확인해 주세요.", "en": "Whether a refund is possible after a visa refusal depends on the cancellation and refund policy of each booked service and on costs already incurred. Please check the conditions before payment.", "mn": "Виз татгалзсан үед буцаалт хийх эсэх нь захиалсан үйлчилгээ бүрийн цуцлалт, буцаалтын журам болон аль хэдийн гарсан зардлаас хамаарна. Төлбөр төлөхөөс өмнө нөхцөлийг шалгана уу.", "zh": "签证被拒时能否退款，取决于各项预约服务的取消·退款规定及已产生的费用。请在付款前确认相关条件。", "pt": "O reembolso em caso de visto negado depende das regras de cancelamento de cada serviço reservado e dos custos já gerados. Confira as condições antes de pagar."}'::jsonb, '{}'::jsonb, true, false, 'draft', 26),
('FAQ-027', '{"ko": "한국 체류 및 회복 관리", "en": "Stay in Korea & recovery", "mn": "Солонгост байх ба нөхөн сэргээлт", "zh": "在韩停留与恢复管理", "pt": "Estadia na Coreia e recuperação"}'::jsonb, '{"ko": "수술 후 한국에 얼마나 머물러야 하나요?", "en": "How long should I stay in Korea after surgery?", "mn": "Мэс заслын дараа Солонгост хэр удаан байх вэ?", "zh": "术后需要在韩国停留多久？", "pt": "Quanto tempo devo ficar na Coreia após a cirurgia?"}'::jsonb, '{"ko": "수술 종류, 회복 상태, 경과 관찰 일정에 따라 체류기간이 달라집니다. 의료진이 권고하는 기간을 기준으로 여행 일정을 계획해 주세요.", "en": "The length of stay depends on the type of surgery, your recovery and the follow-up schedule. Please plan your trip based on the period recommended by your medical team.", "mn": "Байх хугацаа нь мэс заслын төрөл, сэргэлт, хяналтын үзлэгийн хуваариас хамаарна. Эмчийн зөвлөсөн хугацаанд тулгуурлан аяллаа төлөвлөөрэй.", "zh": "停留时间根据手术种类、恢复情况和复诊安排而不同。请以医生建议的时间为准安排行程。", "pt": "O tempo de estadia depende do tipo de cirurgia, da recuperação e das consultas de acompanhamento. Planeje a viagem com base no período recomendado pela equipe médica."}'::jsonb, '{}'::jsonb, false, false, 'draft', 27),
('FAQ-028', '{"ko": "한국 체류 및 회복 관리", "en": "Stay in Korea & recovery", "mn": "Солонгост байх ба нөхөн сэргээлт", "zh": "在韩停留与恢复管理", "pt": "Estadia na Coreia e recuperação"}'::jsonb, '{"ko": "공항 픽업 서비스를 이용할 수 있나요?", "en": "Is airport pickup available?", "mn": "Нисэх буудлаас тосох үйлчилгээ байдаг уу?", "zh": "可以使用机场接机服务吗？", "pt": "Há serviço de busca no aeroporto?"}'::jsonb, '{"ko": "공항 이동 서비스의 연계 가능 여부를 확인해 드립니다. 이용 가능 차량, 인원 및 비용은 사전 안내를 통해 확인할 수 있습니다.", "en": "We will check whether airport transfer services can be arranged. Available vehicles, number of passengers and costs are explained in advance.", "mn": "Нисэх буудлын тээврийн үйлчилгээ зохион байгуулах боломжийг шалгаж өгнө. Машин, хүний тоо, үнийг урьдчилан мэдэгдэнэ.", "zh": "我们会确认能否安排机场接送服务。可用车辆、人数及费用会事先告知。", "pt": "Verificamos se é possível organizar o transfer do aeroporto. Veículo, número de pessoas e custo são informados com antecedência."}'::jsonb, '{"ko": "공항 픽업 이동 차량", "en": "airport pickup transfer", "mn": "нисэх буудал тосох", "zh": "机场 接机", "pt": "aeroporto transfer busca"}'::jsonb, false, false, 'draft', 28),
('FAQ-029', '{"ko": "한국 체류 및 회복 관리", "en": "Stay in Korea & recovery", "mn": "Солонгост байх ба нөхөн сэргээлт", "zh": "在韩停留与恢复管理", "pt": "Estadia na Coreia e recuperação"}'::jsonb, '{"ko": "숙박시설도 예약할 수 있나요?", "en": "Can you also book accommodation?", "mn": "Байр захиалж болох уу?", "zh": "可以预订住宿吗？", "pt": "Vocês também reservam hospedagem?"}'::jsonb, '{"ko": "고객의 체류기간과 희망 조건에 따라 숙박 연계 가능 여부를 확인합니다. 숙박비와 포함 서비스는 별도 안내합니다.", "en": "We check whether accommodation can be arranged based on your length of stay and preferences. Accommodation costs and included services are explained separately.", "mn": "Таны байх хугацаа, хүсэлтээс хамааран байр зохион байгуулах боломжийг шалгана. Байрны төлбөр, багтсан үйлчилгээг тусад нь мэдэгдэнэ.", "zh": "我们会根据客户的停留时间和需求确认住宿安排的可能性。住宿费和包含的服务另行告知。", "pt": "Verificamos opções de hospedagem conforme o período e suas preferências. O valor e os serviços incluídos são informados à parte."}'::jsonb, '{"ko": "숙소 호텔 숙박", "en": "hotel accommodation stay", "mn": "зочид буудал байр", "zh": "酒店 住宿", "pt": "hotel hospedagem"}'::jsonb, true, false, 'draft', 29),
('FAQ-030', '{"ko": "한국 체류 및 회복 관리", "en": "Stay in Korea & recovery", "mn": "Солонгост байх ба нөхөн сэргээлт", "zh": "在韩停留与恢复管理", "pt": "Estadia na Coreia e recuperação"}'::jsonb, '{"ko": "수술 후 관광이나 쇼핑을 할 수 있나요?", "en": "Can I go sightseeing or shopping after surgery?", "mn": "Мэс заслын дараа аялах, дэлгүүр хэсэж болох уу?", "zh": "术后可以观光或购物吗？", "pt": "Posso passear ou fazer compras depois da cirurgia?"}'::jsonb, '{"ko": "회복 상태와 의료진의 허용 범위에 따라 가능합니다. 수술 직후 무리한 활동은 피하고 의료진의 지침을 우선해 주세요.", "en": "It is possible depending on your recovery and what your doctor allows. Avoid strenuous activity right after surgery and always follow your medical team''s instructions first.", "mn": "Сэргэлт болон эмчийн зөвшөөрлөөс хамааран боломжтой. Мэс заслын дараа шууд хүнд ачаалал авахаас зайлсхийж, эмчийн зааврыг нэн тэргүүнд дагаарай.", "zh": "根据恢复情况和医生允许的范围可以进行。术后请避免过度活动，并优先遵循医生的指示。", "pt": "Depende da recuperação e da liberação do médico. Evite esforço logo após a cirurgia e siga sempre as orientações da equipe médica."}'::jsonb, '{}'::jsonb, false, false, 'draft', 30),
('FAQ-031', '{"ko": "한국 체류 및 회복 관리", "en": "Stay in Korea & recovery", "mn": "Солонгост байх ба нөхөн сэргээлт", "zh": "在韩停留与恢复管理", "pt": "Estadia na Coreia e recuperação"}'::jsonb, '{"ko": "수술 후 언제 비행기를 탈 수 있나요?", "en": "When can I fly after surgery?", "mn": "Мэс заслын дараа хэзээ онгоцоор нисч болох вэ?", "zh": "术后什么时候可以坐飞机？", "pt": "Quando posso viajar de avião após a cirurgia?"}'::jsonb, '{"ko": "비행 가능 시점은 수술 종류와 합병증 위험 등에 따라 달라집니다. 귀국 항공편을 확정하기 전에 담당 의료진과 상의하시기 바랍니다.", "en": "When you can fly depends on the type of surgery and the risk of complications. Please consult your doctor before confirming your return flight.", "mn": "Нисэх боломжтой хугацаа нь мэс заслын төрөл, хүндрэлийн эрсдэлээс хамаарна. Буцах нислэгээ баталгаажуулахаас өмнө эмчтэйгээ зөвлөлдөөрэй.", "zh": "可乘机时间取决于手术种类和并发症风险等。确定回国航班前请与负责医生商量。", "pt": "Depende do tipo de cirurgia e do risco de complicações. Converse com o médico antes de confirmar o voo de volta."}'::jsonb, '{"ko": "비행기 항공 귀국", "en": "flight fly plane", "mn": "онгоц нислэг", "zh": "飞机 航班", "pt": "avião voo voar"}'::jsonb, false, false, 'draft', 31),
('FAQ-032', '{"ko": "한국 체류 및 회복 관리", "en": "Stay in Korea & recovery", "mn": "Солонгост байх ба нөхөн сэргээлт", "zh": "在韩停留与恢复管理", "pt": "Estadia na Coreia e recuperação"}'::jsonb, '{"ko": "귀국 후에도 사후관리를 받을 수 있나요?", "en": "Can I receive aftercare after returning home?", "mn": "Эх орондоо буцсаны дараа хяналт авч болох уу?", "zh": "回国后还能接受术后管理吗？", "pt": "Tenho acompanhamento depois de voltar ao meu país?"}'::jsonb, '{"ko": "귀국 후 경과 확인 및 추가 진료 관련 문의를 접수할 수 있습니다. 실제 사후관리 방식과 비용은 의료기관별 정책에 따라 달라집니다.", "en": "We can receive inquiries about follow-up checks and additional treatment after you return home. Actual aftercare methods and costs depend on each medical institution''s policy.", "mn": "Буцсаны дараах хяналтын үзлэг, нэмэлт эмчилгээний талаарх хүсэлтийг хүлээн авна. Бодит хяналтын арга, төлбөр нь эмнэлэг бүрийн журмаас хамаарна.", "zh": "回国后我们也可受理复查及追加诊疗的咨询。实际的术后管理方式和费用以各医疗机构的政策为准。", "pt": "Recebemos pedidos sobre revisões e tratamentos adicionais após o retorno. A forma e o custo do acompanhamento dependem da política de cada instituição."}'::jsonb, '{}'::jsonb, false, false, 'draft', 32),
('FAQ-033', '{"ko": "결제·예약 변경·환불", "en": "Payment, changes & refunds", "mn": "Төлбөр, цаг өөрчлөх ба буцаалт", "zh": "付款·预约变更·退款", "pt": "Pagamento, alterações e reembolso"}'::jsonb, '{"ko": "어떤 방법으로 결제할 수 있나요?", "en": "What payment methods are available?", "mn": "Ямар аргаар төлбөр төлж болох вэ?", "zh": "可以用哪些方式付款？", "pt": "Quais formas de pagamento são aceitas?"}'::jsonb, '{"ko": "이용 서비스와 결제 주체에 따라 가능한 결제 방법이 다릅니다. 공식 청구서 및 결제 안내를 통해 확인해 주세요.", "en": "Available payment methods differ depending on the service used and who receives the payment. Please check the official invoice and payment instructions.", "mn": "Төлбөрийн арга нь үйлчилгээ болон төлбөр хүлээн авагчаас хамааран өөр байна. Албан ёсны нэхэмжлэх, төлбөрийн зааврыг шалгана уу.", "zh": "可用的付款方式因服务和收款方而异。请通过正式账单和付款说明确认。", "pt": "As formas de pagamento variam conforme o serviço e quem recebe o pagamento. Confira a fatura oficial e as instruções de pagamento."}'::jsonb, '{"ko": "결제 카드 현금 송금", "en": "payment card cash transfer", "mn": "төлбөр карт бэлэн", "zh": "付款 刷卡 现金", "pt": "pagamento cartão dinheiro pix"}'::jsonb, true, false, 'draft', 33),
('FAQ-034', '{"ko": "결제·예약 변경·환불", "en": "Payment, changes & refunds", "mn": "Төлбөр, цаг өөрчлөх ба буцаалт", "zh": "付款·预约变更·退款", "pt": "Pagamento, alterações e reembolso"}'::jsonb, '{"ko": "예약금을 미리 납부해야 하나요?", "en": "Do I need to pay a deposit in advance?", "mn": "Урьдчилгаа төлбөр төлөх шаардлагатай юу?", "zh": "需要提前支付预约金吗？", "pt": "Preciso pagar sinal antecipado?"}'::jsonb, '{"ko": "예약금이나 선납금이 필요한 경우가 있습니다. 금액, 납부 기한 및 환불 조건은 결제 전에 안내합니다.", "en": "A deposit or advance payment may be required. The amount, due date and refund conditions are explained before payment.", "mn": "Урьдчилгаа эсвэл барьцаа төлбөр шаардагдах тохиолдол бий. Дүн, төлөх хугацаа, буцаалтын нөхцөлийг төлбөр төлөхөөс өмнө мэдэгдэнэ.", "zh": "有时需要预约金或预付款。金额、付款期限及退款条件会在付款前告知。", "pt": "Em alguns casos é necessário sinal ou pagamento antecipado. Valor, prazo e condições de reembolso são informados antes do pagamento."}'::jsonb, '{}'::jsonb, true, false, 'draft', 34),
('FAQ-035', '{"ko": "결제·예약 변경·환불", "en": "Payment, changes & refunds", "mn": "Төлбөр, цаг өөрчлөх ба буцаалт", "zh": "付款·预约变更·退款", "pt": "Pagamento, alterações e reembolso"}'::jsonb, '{"ko": "예약 날짜를 변경할 수 있나요?", "en": "Can I change my appointment date?", "mn": "Захиалгын огноогоо өөрчилж болох уу?", "zh": "可以更改预约日期吗？", "pt": "Posso mudar a data do agendamento?"}'::jsonb, '{"ko": "병원 일정과 예약 조건에 따라 변경 가능 여부가 달라집니다. 변경을 원하시면 가능한 한 빨리 담당자에게 문의해 주세요.", "en": "Whether a change is possible depends on the hospital''s schedule and booking conditions. If you wish to change, please contact your coordinator as soon as possible.", "mn": "Өөрчлөх боломж нь эмнэлгийн хуваарь, захиалгын нөхцөлөөс хамаарна. Өөрчлөх бол аль болох эрт хариуцсан ажилтанд хандаарай.", "zh": "能否更改取决于医院日程和预约条件。如需更改，请尽快联系负责人。", "pt": "Depende da agenda do hospital e das condições da reserva. Se quiser mudar, fale com o responsável o quanto antes."}'::jsonb, '{}'::jsonb, true, false, 'draft', 35),
('FAQ-036', '{"ko": "결제·예약 변경·환불", "en": "Payment, changes & refunds", "mn": "Төлбөр, цаг өөрчлөх ба буцаалт", "zh": "付款·预约变更·退款", "pt": "Pagamento, alterações e reembolso"}'::jsonb, '{"ko": "예약을 취소하면 환불받을 수 있나요?", "en": "Can I get a refund if I cancel my booking?", "mn": "Захиалгаа цуцалбал мөнгөө буцааж авах уу?", "zh": "取消预约可以退款吗？", "pt": "Se eu cancelar, recebo reembolso?"}'::jsonb, '{"ko": "취소 시점, 의료기관 및 서비스별 계약 조건에 따라 환불 여부와 금액이 달라집니다. 적용되는 환불 규정을 확인해 주세요.", "en": "Whether you receive a refund, and how much, depends on when you cancel and on the contract terms of the medical institution and each service. Please check the applicable refund policy.", "mn": "Буцаалт болон дүн нь цуцалсан хугацаа, эмнэлэг болон үйлчилгээ бүрийн гэрээний нөхцөлөөс хамаарна. Хамаарах буцаалтын журмыг шалгана уу.", "zh": "能否退款及退款金额取决于取消时间、医疗机构及各项服务的合同条件。请确认适用的退款规定。", "pt": "O reembolso e o valor dependem da data do cancelamento e das condições contratuais da instituição e de cada serviço. Confira a política de reembolso aplicável."}'::jsonb, '{"ko": "취소 환불", "en": "cancel refund", "mn": "цуцлах буцаалт", "zh": "取消 退款", "pt": "cancelar reembolso"}'::jsonb, true, false, 'draft', 36),
('FAQ-037', '{"ko": "결제·예약 변경·환불", "en": "Payment, changes & refunds", "mn": "Төлбөр, цаг өөрчлөх ба буцаалт", "zh": "付款·预约变更·退款", "pt": "Pagamento, alterações e reembolso"}'::jsonb, '{"ko": "병원에 직접 결제하나요?", "en": "Do I pay the hospital directly?", "mn": "Эмнэлэгт шууд төлөх үү?", "zh": "是直接向医院付款吗？", "pt": "Pago diretamente ao hospital?"}'::jsonb, '{"ko": "결제 주체는 서비스 및 계약 구조에 따라 달라질 수 있습니다. 결제 전 공식 청구서에서 수취인과 결제 항목을 확인해 주세요.", "en": "Who receives the payment may differ depending on the service and contract structure. Before paying, please check the recipient and payment items on the official invoice.", "mn": "Төлбөр хүлээн авагч нь үйлчилгээ, гэрээний бүтцээс хамааран өөр байж болно. Төлөхөөс өмнө албан ёсны нэхэмжлэх дээрх хүлээн авагч, төлбөрийн зүйлсийг шалгана уу.", "zh": "收款方可能因服务和合同结构而不同。付款前请在正式账单上确认收款人和付款项目。", "pt": "Quem recebe o pagamento pode variar conforme o serviço e o contrato. Antes de pagar, confira na fatura oficial o beneficiário e os itens cobrados."}'::jsonb, '{}'::jsonb, true, false, 'draft', 37),
('FAQ-038', '{"ko": "K-Beauty 및 고객지원", "en": "K-Beauty & customer support", "mn": "K-Beauty ба үйлчилгээ", "zh": "K-Beauty 与客户服务", "pt": "K-Beauty e atendimento"}'::jsonb, '{"ko": "의료관광과 K-Beauty 체험을 함께 이용할 수 있나요?", "en": "Can I combine medical tourism with K-Beauty experiences?", "mn": "Эмчилгээний аяллыг K-Beauty туршлагатай хослуулж болох уу?", "zh": "医疗旅游可以和 K-Beauty 体验一起安排吗？", "pt": "Posso combinar turismo médico com experiências de K-Beauty?"}'::jsonb, '{"ko": "의료 상담과 뷰티·웰니스 체험을 결합한 일정에 대해 문의하실 수 있습니다. 수술 전후 체험 가능 여부는 의료진의 지침을 우선합니다.", "en": "You can inquire about itineraries combining medical consultation with beauty and wellness experiences. Whether experiences are possible before or after surgery depends first on your medical team''s instructions.", "mn": "Эмчийн зөвлөгөөг гоо сайхан, эрүүл мэндийн туршлагатай хослуулсан хөтөлбөрийн талаар асууж болно. Мэс заслын өмнө, дараа туршлага авах боломжийг эмчийн зааврыг нэн тэргүүнд баримтална.", "zh": "您可以咨询将医疗咨询与美容·健康体验相结合的行程。手术前后能否体验，以医生的指示为优先。", "pt": "Você pode pedir um roteiro que combine consulta médica com experiências de beleza e bem-estar. Antes ou depois da cirurgia, valem primeiro as orientações médicas."}'::jsonb, '{}'::jsonb, false, false, 'draft', 38),
('FAQ-039', '{"ko": "K-Beauty 및 고객지원", "en": "K-Beauty & customer support", "mn": "K-Beauty ба үйлчилгээ", "zh": "K-Beauty 与客户服务", "pt": "K-Beauty e atendimento"}'::jsonb, '{"ko": "K-POP이나 한국 문화체험도 신청할 수 있나요?", "en": "Can I sign up for K-POP or Korean culture experiences?", "mn": "K-POP эсвэл Солонгос соёлын хөтөлбөрт бүртгүүлж болох уу?", "zh": "可以报名 K-POP 或韩国文化体验吗？", "pt": "Posso me inscrever em experiências de K-POP ou cultura coreana?"}'::jsonb, '{"ko": "K-POP 댄스, 한국 문화체험 및 교육 프로그램의 연계 가능 여부를 확인해 드립니다. 인원과 방문 일정에 따라 프로그램을 상담할 수 있습니다.", "en": "We will check whether K-POP dance, Korean culture experiences and educational programs can be arranged. Programs can be discussed according to group size and visit dates.", "mn": "K-POP бүжиг, Солонгос соёлын туршлага, сургалтын хөтөлбөрийг холбох боломжийг шалгаж өгнө. Хүний тоо, ирэх хуваарийн дагуу хөтөлбөрийг зөвлөлдөж болно.", "zh": "我们会确认 K-POP 舞蹈、韩国文化体验及教育项目的对接可能性。可根据人数和访问日程咨询项目。", "pt": "Verificamos a possibilidade de aulas de dança K-POP, experiências culturais e programas educativos. O programa é ajustado conforme o número de pessoas e as datas."}'::jsonb, '{}'::jsonb, false, false, 'draft', 39),
('FAQ-040', '{"ko": "K-Beauty 및 고객지원", "en": "K-Beauty & customer support", "mn": "K-Beauty ба үйлчилгээ", "zh": "K-Beauty 与客户服务", "pt": "K-Beauty e atendimento"}'::jsonb, '{"ko": "기업이나 해외 에이전시도 제휴할 수 있나요?", "en": "Can companies or overseas agencies partner with you?", "mn": "Компани эсвэл гадаадын агентлаг хамтран ажиллаж болох уу?", "zh": "企业或海外中介可以合作吗？", "pt": "Empresas ou agências estrangeiras podem ser parceiras?"}'::jsonb, '{"ko": "해외 의료관광 에이전시, 기업 및 교육기관의 제휴 문의를 접수합니다. 회사명, 국가, 협력 희망 분야와 예상 고객 규모를 알려주세요.", "en": "We welcome partnership inquiries from overseas medical tourism agencies, companies and educational institutions. Please tell us your company name, country, areas of cooperation and expected number of clients.", "mn": "Гадаадын эмчилгээний аялал жуулчлалын агентлаг, компани, боловсролын байгууллагын хамтын ажиллагааны хүсэлтийг хүлээн авна. Компанийн нэр, улс, хамтран ажиллах чиглэл, хүлээгдэж буй үйлчлүүлэгчийн тоог бидэнд мэдэгдээрэй.", "zh": "我们受理海外医疗旅游中介、企业及教育机构的合作咨询。请告知公司名称、国家、希望合作的领域和预计客户规模。", "pt": "Recebemos propostas de agências de turismo médico, empresas e instituições de ensino. Informe nome da empresa, país, área de cooperação e número estimado de clientes."}'::jsonb, '{}'::jsonb, true, false, 'draft', 40)
on conflict (id) do nothing;


-- ---------------------------------------------------------------------
-- [labelle_v23.sql]
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- [labelle_v24.sql]
-- ---------------------------------------------------------------------
-- LA BELLE v3.3 — ETAPA 4: SOFIA com IA (registro de uso + configuracoes)
-- Supabase → SQL Editor → New query → colar TUDO → Run  (pode repetir sem problema)
-- Precisa ter rodado antes o labelle_v23.sql

-- 1) Configuracoes gerais (so ADM altera; equipe le)
create table if not exists public.labelle_settings (
  key text primary key,
  value jsonb,
  updated_at timestamptz default now(),
  updated_by text default lower(auth.jwt() ->> 'email')
);
alter table public.labelle_settings enable row level security;
drop policy if exists "config ler" on public.labelle_settings;
drop policy if exists "config adm" on public.labelle_settings;
create policy "config ler" on public.labelle_settings for select using (public.labelle_is_staff());
create policy "config adm" on public.labelle_settings for all using (public.labelle_is_adm()) with check (public.labelle_is_adm());
insert into public.labelle_settings (key, value) values
  ('ai_bot', 'true'::jsonb),            -- chatbot usa IA quando o FAQ nao tem resposta
  ('ai_month_usd', '20'::jsonb)         -- limite de gasto com IA por mes (US$)
on conflict (key) do nothing;

-- 2) Registro de uso da IA (gravado so pela Edge Function; ADM le)
create table if not exists public.labelle_ai_usage (
  id bigserial primary key,
  at timestamptz default now(),
  email text,
  thread_id uuid,
  action text,
  model text,
  tokens_in int default 0,
  tokens_out int default 0,
  usd numeric(10,6) default 0,
  ok boolean default true
);
create index if not exists labelle_ai_usage_at on public.labelle_ai_usage (at);
alter table public.labelle_ai_usage enable row level security;
drop policy if exists "uso ia ler" on public.labelle_ai_usage;
create policy "uso ia ler" on public.labelle_ai_usage for select using (public.labelle_is_adm());
-- (sem politica de insert: so a Edge Function, com a chave de servico, grava aqui)

-- 3) Resumo de uso do mes para a tela de configuracoes (ADM)
create or replace function public.labelle_ai_month()
returns table (calls bigint, usd numeric, bot_calls bigint)
language sql stable security definer set search_path = public as $$
  select count(*), coalesce(sum(usd), 0), count(*) filter (where action = 'bot')
  from public.labelle_ai_usage
  where public.labelle_is_adm() and at >= date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
$$;
revoke execute on function public.labelle_ai_month() from public, anon;
grant execute on function public.labelle_ai_month() to authenticated;


-- ---------------------------------------------------------------------
-- [labelle_v25.sql]
-- ---------------------------------------------------------------------
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
