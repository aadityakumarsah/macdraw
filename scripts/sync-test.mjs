import "dotenv/config";
import ws from "ws";
import { createClient } from "@supabase/supabase-js";

const URL = process.env.SUPABASE_URL ?? "https://fabdvbwvuohznuhlsgqj.supabase.co";
const KEY = process.env.SUPABASE_PUBLISHABLE_KEY ?? "sb_publishable_N4gaQKtPRNi85x5V8kQl0Q_gjLit033";
const EMAIL = "demo@macdraw.app";
const PASSWORD = "macdraw-demo-1234";

if (!globalThis.WebSocket) globalThis.WebSocket = ws;

const results = [];
const check = (name, ok, extra = "") =>
  results.push(`${ok ? "PASS" : "FAIL"} ${name}${extra ? ` (${extra})` : ""}`);

function makeClient() {
  return createClient(URL, KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { transport: ws },
  });
}

const c1 = makeClient();
const c2 = makeClient();

// ---- Test 1: sign in (shared test account) ----
const { data: s1, error: e1 } = await c1.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
check("web client sign-in", !e1 && !!s1.session, e1?.message ?? "");

// ---- Test 2: workspace bootstrap (RLS insert workspace + own membership) ----
const uid = s1.session.user.id;
let wsRow = null;
{
  const { data: prof } = await c1.from("UserProfile").select("defaultWorkspaceId").eq("id", uid).maybeSingle();
  if (prof?.defaultWorkspaceId) {
    const { data: w } = await c1.from("Workspace").select("*").eq("id", prof.defaultWorkspaceId).maybeSingle();
    wsRow = w;
  }
  if (!wsRow) {
    const now = new Date().toISOString();
    const wsid = `workspace_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
    const { error: werr } = await c1.from("Workspace").insert({ id: wsid, name: "Aaditya's Team", createdBy: uid, createdAt: now, updatedAt: now });
    check("workspace insert (RLS)", !werr, werr?.message ?? "");
    const { error: merr } = await c1.from("WorkspaceMember").insert({ id: `member_${Date.now()}`, workspaceId: wsid, userId: uid, role: "owner", createdAt: now });
    check("member insert (RLS)", !merr, merr?.message ?? "");
    await c1.from("UserProfile").update({ defaultWorkspaceId: wsid }).eq("id", uid);
    wsRow = { id: wsid };
  }
}
check("workspace resolves", !!wsRow?.id, wsRow?.id ?? "none");
const WID = wsRow.id;

// Repair: if an earlier run left a workspace without membership, re-join it
// (the member_insert_self policy only needs the workspace's creator == us).
{
  const { data: member } = await c1.from("WorkspaceMember").select("id").eq("workspaceId", WID).eq("userId", uid).maybeSingle();
  if (!member) {
    const { error: merr } = await c1.from("WorkspaceMember").insert({
      id: `member_${Date.now()}`,
      workspaceId: WID,
      userId: uid,
      role: "owner",
      createdAt: new Date().toISOString(),
    });
    check("rejoin existing workspace", !merr, merr?.message ?? "");
  }
}

// ---- Test 3: seed page ("react roadmap") ----
{
  const { count } = await c1.from("Page").select("id", { count: "exact", head: true }).eq("workspaceId", WID).is("deletedAt", null);
  if (!count) {
    const now = new Date().toISOString();
    const { error } = await c1.from("Page").insert({
      id: `page_seed_${Date.now().toString(36)}`,
      workspaceId: WID,
      parentId: null,
      name: "react roadmap",
      description: "",
      icon: null,
      orderIndex: 0,
      contentJson: "{}",
      createdBy: uid,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
    });
    check("seed page insert (RLS)", !error, error?.message ?? "");
  }
  const { data } = await c1.from("Page").select("id,name").eq("workspaceId", WID).is("deletedAt", null);
  check("seed page readable via RLS", data?.some((p) => p.name === "react roadmap"), JSON.stringify(data?.map((p) => p.name)));
}

// ---- Tests 4-7: realtime cross-client ----
const { data: s2, error: e2 } = await c2.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
check("second client signs in", !e2 && !!s2.session, e2?.message ?? "");

const received = [];
let resolveOne;
const oneSeen = new Promise((r) => (resolveOne = r));
const channel = c2.channel(`live-test-${Date.now()}`)
  .on("postgres_changes", { event: "*", schema: "public", table: "Page", filter: `workspaceId=eq.${WID}` }, (payload) => {
    received.push(payload);
    resolveOne();
  })
  .subscribe();

await new Promise((r) => setTimeout(r, 1200));

const now = new Date().toISOString();
const newPage = {
  id: `page_node_${Date.now().toString(36)}`,
  workspaceId: WID,
  parentId: null,
  name: "live sync test",
  description: null,
  icon: null,
  orderIndex: 5,
  contentJson: "{}",
  createdBy: uid,
  createdAt: now,
  updatedAt: now,
  deletedAt: null,
  version: 1,
};
const { error: insErr } = await c1.from("Page").insert(newPage);
check("insert page", !insErr, insErr?.message ?? "");

await Promise.race([oneSeen, new Promise((r) => setTimeout(r, 6000))]);
const seenIns = received.some((p) => p.eventType === "INSERT" && p.new?.id === newPage.id);
check("realtime INSERT reaches second client", seenIns, JSON.stringify(received.map((r) => r.eventType)));

// Rename via c1, watch update on c2
const renamed = { ...newPage, name: "renamed live page", updatedAt: new Date().toISOString(), version: 2 };
const { error: updErr } = await c1.from("Page").update(renamed).eq("id", newPage.id);
check("update page", !updErr, updErr?.message ?? "");
await new Promise((r) => setTimeout(r, 1500));
const seenUpd = received.some((p) => p.eventType === "UPDATE" && p.new?.id === newPage.id && p.new?.name === "renamed live page");
check("realtime UPDATE reaches second client", seenUpd);

// Soft delete
const { error: delErr } = await c1.from("Page").update({ deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() }).eq("id", newPage.id);
check("soft-delete page", !delErr, delErr?.message ?? "");
await new Promise((r) => setTimeout(r, 1000));
const visible = received.filter((p) => p.new?.id === newPage.id && (!p.new?.deletedAt ? true : false)).length > 0;
const { data: afterDelete, error: afterDelErr } = await c1.from("Page").select("id").eq("workspaceId", WID).is("deletedAt", null);
check("deleted page hidden from list", !afterDelErr && !afterDelete.some((p) => p.id === newPage.id), afterDelErr?.message ?? "");

// ---- Tests 8-10: Mac-style raw REST (as SyncService does it) ----
let token = null;
{
  const res = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { "apikey": KEY, "Content-Type": "application/json", "Accept": "application/json" },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
  });
  const body = await res.json();
  token = body.access_token;
  check("mac-style REST sign-in", res.ok && !!token, String(res.status));
}
{
  const res = await fetch(`${URL}/rest/v1/Page?workspaceId=eq.${WID}&deletedAt=is.null&order=orderIndex.asc`, {
    headers: { "apikey": KEY, "Authorization": `Bearer ${token}`, "Accept": "application/json" },
  });
  const rows = await res.json();
  check("mac-style REST fetch pages", res.ok && Array.isArray(rows) && rows.length > 0, `${res.status} rows=${Array.isArray(rows) ? rows.length : "?"}`);
}

// Clean up the test page entirely so handoff state stays tidy.
await c1.from("Page").delete().eq("id", newPage.id).maybeSingle();
await c1.auth.signOut();
await c2.removeChannel(channel);
await c2.auth.signOut();

const allOk = results.every((r) => r.startsWith("PASS"));
process.stdout.write(results.join("\n") + "\n");
process.stdout.write(`LIVE-SYNC ${allOk ? "PASS" : "FAIL"}\n`);
process.exit(allOk ? 0 : 1);