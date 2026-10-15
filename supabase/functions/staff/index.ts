// LA BELLE LB · Etapa 1 — Supabase Edge Function "staff"
// Login por ID, recuperacao de senha, convite de funcionario, reset de MFA, ativar/desativar.
// Deploy: Supabase → Edge Functions → Deploy new function → nome "staff" → colar este arquivo.
// Settings da funcao: "Verify JWT with legacy secret" = OFF (a funcao confere o usuario sozinha).
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const env = (k: string, d = "") => Deno.env.get(k) || d;
function serviceKey() {
  try { const k = JSON.parse(env("SUPABASE_SECRET_KEYS", "{}")); if (k && k.default) return k.default; } catch (_) { /* chave antiga */ }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}
function anonKey() {
  try { const k = JSON.parse(env("SUPABASE_PUBLISHABLE_KEYS", "{}")); if (k && k.default) return k.default; } catch (_) { /* chave antiga */ }
  return env("SUPABASE_ANON_KEY");
}
const URL_ = env("SUPABASE_URL");
const admin = createClient(URL_, serviceKey(), { auth: { persistSession: false, autoRefreshToken: false } });
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const LEGACY_DOMAIN = "@labelle.app";
const LOCK = { fails: 5, minutes: 15 };
const ROLES = ["ADM", "운영관리자", "코디네이터", "상담 담당자", "의료일정 담당자", "재무 담당자"];

async function resolveEmail(login: string) {
  const l = String(login || "").trim().toLowerCase();
  if (!l) return null;
  if (l.includes("@")) return l;
  const { data } = await admin.from("labelle_staff").select("email,active").ilike("login_id", l).maybeSingle();
  if (data?.email) return String(data.email).toLowerCase();
  return l + LEGACY_DOMAIN; // contas antigas (staff e parceiros) usam id@labelle.app
}
async function logLogin(login: string, email: string | null, ok: boolean, reason = "") {
  try { await admin.from("labelle_login_log").insert({ login, email, ok, reason }); } catch (_) { /* nao bloqueia */ }
}
async function locked(login: string, email: string | null) {
  const since = new Date(Date.now() - LOCK.minutes * 60e3).toISOString();
  let q = admin.from("labelle_login_log").select("id", { count: "exact", head: true }).eq("ok", false).gte("at", since);
  q = email ? q.or(`email.eq."${email}",login.eq."${login}"`) : q.eq("login", login);
  const { count } = await q;
  return (count || 0) >= LOCK.fails;
}
function claims(jwt: string) {
  try { return JSON.parse(atob(jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))); } catch (_) { return {}; }
}
async function setting(k: string, d: unknown) {
  const { data } = await admin.from("labelle_settings").select("value").eq("key", k).maybeSingle();
  return data && data.value !== null && data.value !== undefined ? data.value : d;
}
async function caller(req: Request) {
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt || jwt.split(".").length !== 3) return null;
  const { data, error } = await admin.auth.getUser(jwt);
  const email = data?.user?.email?.toLowerCase();
  if (error || !email) return null;
  const { data: s } = await admin.from("labelle_staff").select("email,name,role,active").eq("email", email).maybeSingle();
  if (!s || s.active === false || s.role !== "ADM") return null;
  if ((await setting("mfa_enforce", true)) !== false && claims(jwt).aal !== "aal2") return { ...s, needMfa: true };
  return s;
}
async function userByEmail(email: string) {
  for (let page = 1; page < 20; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) return null;
    const u = data.users.find((x) => (x.email || "").toLowerCase() === email);
    if (u) return u;
    if (data.users.length < 200) return null;
  }
  return null;
}
async function audit(by: string, action: string, target: string, detail: unknown = null) {
  try { await admin.from("labelle_audit").insert({ email: by, action, target, detail }); } catch (_) { /* nao bloqueia */ }
}

/* ---------- publico ---------- */
async function login(b: Record<string, string>) {
  const lg = String(b.login || "").trim().toLowerCase();
  const pw = String(b.password || "");
  if (!lg || !pw) return json({ error: "empty" }, 400);
  const email = await resolveEmail(lg);
  if (await locked(lg, email)) { await logLogin(lg, email, false, "locked"); return json({ error: "locked", minutes: LOCK.minutes }, 429); }
  const { data: st } = await admin.from("labelle_staff").select("active").eq("email", email).maybeSingle();
  if (st && st.active === false) { await logLogin(lg, email, false, "inactive"); return json({ error: "inactive" }, 403); }
  const pub = createClient(URL_, anonKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await pub.auth.signInWithPassword({ email: email!, password: pw });
  if (error || !data.session) { await logLogin(lg, email, false, error?.message?.slice(0, 80) || "fail"); return json({ error: "invalid" }, 401); }
  await logLogin(lg, email, true);
  return json({ session: { access_token: data.session.access_token, refresh_token: data.session.refresh_token } });
}
async function recover(b: Record<string, string>) {
  const email = await resolveEmail(b.login);
  if (email && !email.endsWith(LEGACY_DOMAIN)) {
    const pub = createClient(URL_, anonKey(), { auth: { persistSession: false } });
    await pub.auth.resetPasswordForEmail(email, { redirectTo: b.redirect || undefined });
  }
  return json({ ok: true }); // sempre ok: nao revela se a conta existe
}

/* ---------- so 최고관리자 (ADM) ---------- */
async function invite(b: Record<string, unknown>, me: Record<string, string>) {
  const email = String(b.email || "").trim().toLowerCase();
  const login_id = String(b.login_id || "").trim().toLowerCase() || null;
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "email" }, 400);
  if (login_id && !/^[a-z0-9._-]{3,30}$/.test(login_id)) return json({ error: "login_id" }, 400);
  const role = ROLES.includes(String(b.role)) ? String(b.role) : "코디네이터";
  const row: Record<string, unknown> = {
    email, login_id, name: String(b.name || login_id || email).slice(0, 40), real_name: b.real_name || null, dept: b.dept || null,
    role, is_test: b.is_test !== false, active: true, invited_at: new Date().toISOString(),
  };
  // conta pre-cadastrada (ex.: staff_ari@pending.labellelb) → troca pelo e-mail real
  let prev = null;
  if (login_id) ({ data: prev } = await admin.from("labelle_staff").select("email").ilike("login_id", login_id).maybeSingle());
  if (prev && prev.email !== email) {
    const { error } = await admin.from("labelle_staff").update(row).eq("email", prev.email);
    if (error) return json({ error: error.message }, 400);
  } else {
    const { error } = await admin.from("labelle_staff").upsert(row, { onConflict: "email" });
    if (error) return json({ error: error.message }, 400);
  }
  const redirect = String(b.redirect || "") || undefined;
  const exists = await userByEmail(email);
  if (exists) {
    const pub = createClient(URL_, anonKey(), { auth: { persistSession: false } });
    await pub.auth.resetPasswordForEmail(email, { redirectTo: redirect });
  } else {
    const { error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo: redirect });
    if (error) return json({ error: "invite: " + error.message }, 400);
  }
  await audit(me.email, "직원 초대 메일 발송", email, { login_id, role });
  return json({ ok: true, existing: !!exists });
}
async function mfaReset(b: Record<string, string>, me: Record<string, string>) {
  const email = String(b.email || "").toLowerCase();
  const u = await userByEmail(email);
  if (!u) return json({ error: "user" }, 404);
  const { data } = await admin.auth.admin.mfa.listFactors({ userId: u.id });
  for (const f of data?.factors || []) await admin.auth.admin.mfa.deleteFactor({ id: f.id, userId: u.id });
  await audit(me.email, "MFA 초기화", email);
  return json({ ok: true, removed: (data?.factors || []).length });
}
async function setActive(b: Record<string, unknown>, me: Record<string, string>) {
  const email = String(b.email || "").toLowerCase();
  const active = b.active !== false;
  if (email === me.email && !active) return json({ error: "self" }, 400);
  const { error } = await admin.from("labelle_staff").update({ active }).eq("email", email);
  if (error) return json({ error: error.message }, 400);
  const u = await userByEmail(email);
  if (u) {
    await admin.auth.admin.updateUserById(u.id, { ban_duration: active ? "none" : "876000h" });
  }
  return json({ ok: true });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  let b: Record<string, unknown>;
  try { b = await req.json(); } catch (_) { return json({ error: "bad json" }, 400); }
  try {
    if (b.action === "login") return await login(b as Record<string, string>);
    if (b.action === "recover") return await recover(b as Record<string, string>);
    const me = await caller(req);
    if (!me) return json({ error: "auth" }, 401);
    if ((me as { needMfa?: boolean }).needMfa) return json({ error: "mfa" }, 403);
    if (b.action === "invite") return await invite(b, me);
    if (b.action === "mfa_reset") return await mfaReset(b as Record<string, string>, me);
    if (b.action === "set_active") return await setActive(b, me);
    return json({ error: "action" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error)?.message || e).slice(0, 300) }, 500);
  }
});
