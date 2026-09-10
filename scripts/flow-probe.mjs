import "dotenv/config";
import ws from "ws";
import { createClient } from "@supabase/supabase-js";

const URL = process.env.SUPABASE_URL ?? "https://fabdvbwvuohznuhlsgqj.supabase.co";
const KEY = process.env.SUPABASE_PUBLISHABLE_KEY ?? "sb_publishable_N4gaQKtPRNi85x5V8kQl0Q_gjLit033";
if (!globalThis.WebSocket) globalThis.WebSocket = ws;

function makeClient() {
  return createClient(URL, KEY, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
}

async function flow(label, email, password) {
  const c = makeClient();
  const { data: s, error: e } = await c.auth.signInWithPassword({ email, password });
  if (e) return console.log(`[${label}] sign-in FAIL:`, e.status, e.code, e.message);
  const uid = s.session.user.id;
  const step = async (name, fn) => {
    try {
      const r = await fn();
      console.log(`[${label}] ${name} OK`);
      return r;
    } catch (err) {
      console.log(`[${label}] ${name} FAIL:`, JSON.stringify({ status: err?.status, code: err?.code, message: err?.message, details: err?.details, hint: err?.hint }));
      throw err;
    }
  };
  const profile = await step("profile", async () => {
    const { data } = await c.from("UserProfile").select("defaultWorkspaceId").eq("id", uid).maybeSingle();
    return data;
  });
  let wsRow;
  if (profile?.defaultWorkspaceId) {
    wsRow = await step("workspace", async () => {
      const { data } = await c.from("Workspace").select("*").eq("id", profile.defaultWorkspaceId).maybeSingle();
      return data;
    });
  }
  if (wsRow) {
    const { count } = await step("count pages", async () => {
      const { count } = await c.from("Page").select("id", { count: "exact", head: true }).eq("workspaceId", wsRow.id).is("deletedAt", null);
      return count;
    });
    await step("fetch pages", async () => {
      const { data } = await c.from("Page").select("*").eq("workspaceId", wsRow.id).is("deletedAt", null).order("orderIndex", { ascending: true });
      return data;
    });
  } else {
    console.log(`[${label}] no workspace -> would create (insert+member+profile patch)`);
  }
  await c.auth.signOut();
}

// 1. demo account, repeated rapid loads to catch rate-limit/transient errors.
for (let i = 1; i <= 5; i++) {
  await flow(`demo-run${i}`, "demo@macdraw.app", "macdraw-demo-1234");
  await new Promise((r) => setTimeout(r, 300));
}

// 2. a brand-new throwaway account (the exact case a fresh visitor hits).
const fresh = `fresh-${Date.now()}@macdraw.app`;
{
  const c = makeClient();
  const { data, error } = await c.auth.signUp({ email: fresh, password: "macdraw-demo-1234" });
  if (error) console.log("[signup] FAIL:", error.status, error.code, error.message);
  else console.log("[signup] OK:", data.user?.id);
  await c.auth.signOut();
}
await flow("fresh-account", fresh, "macdraw-demo-1234");