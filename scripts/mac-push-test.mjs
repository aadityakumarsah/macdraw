import "dotenv/config";
import ws from "ws";
import { createClient } from "@supabase/supabase-js";

const URL = process.env.SUPABASE_URL ?? "https://fabdvbwvuohznuhlsgqj.supabase.co";
const KEY = process.env.SUPABASE_PUBLISHABLE_KEY ?? "sb_publishable_N4gaQKtPRNi85x5V8kQl0Q_gjLit033";
if (!globalThis.WebSocket) globalThis.WebSocket = ws;

const client = createClient(URL, KEY, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  global: { transport: ws },
});

const { data: s } = await client.auth.signInWithPassword({ email: "demo@macdraw.app", password: "macdraw-demo-1234" });
if (!s?.session) { console.log("MAC-PUSH FAIL (sign-in)"); process.exit(1); }

const { data: prof } = await client.from("UserProfile").select("defaultWorkspaceId").eq("id", s.session.user.id).single();
if (!prof?.defaultWorkspaceId) { console.log("MAC-PUSH FAIL (no workspace)"); process.exit(1); }
const WID = prof.defaultWorkspaceId;

let found = null;
const tag = "mac-sync-check-";
const seen = new Promise((resolve) => {
  const poll = async () => {
    const { data } = await client.from("Page").select("id,name").eq("workspaceId", WID).is("deletedAt", null);
    const hit = data?.find((p) => p.name?.startsWith(tag));
    if (hit) return resolve(hit);
    setTimeout(poll, 1000);
  };
  poll();
});
const timed = new Promise((r) => setTimeout(() => r(null), 30000));
const hit = await Promise.race([seen, timed]);
if (!hit) {
  console.log("MAC-PUSH FAIL (page never reached server in 30s)");
  process.exit(1);
}
console.log(`MAC-PUSH PASS ${hit.name} (id=${hit.id})`);
await client.from("Page").delete().eq("id", hit.id);
process.exit(0);