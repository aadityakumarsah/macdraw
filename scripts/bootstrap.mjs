import "dotenv/config";
import ws from "ws";
import { createAdminClient } from "@supabase/server/core";
import { resolveEnv } from "@supabase/server/core";

// Node 20 on the laptop has no global WebSocket; supabase-js uses it for the
// realtime transport regardless of whether we subscribe.
if (!globalThis.WebSocket) {
  globalThis.WebSocket = ws;
}

// Server-side bootstrap. Uses the secret key (NEVER ship this to clients).
// Creates/updates a test auth user the Mac app and React Roadmap both sign in as.

const email = process.env.SYNC_TEST_EMAIL ?? "demo@macdraw.app";
const password = process.env.SYNC_TEST_PASSWORD ?? "macdraw-demo-1234";

const { data: env, error } = resolveEnv();
if (error) throw error;

const admin = createAdminClient();

const { data: existing } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
let user = existing.users.find((u) => u.email === email);

if (!user) {
  const { data, error: err } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (err) throw err;
  user = data.user;
}
console.log("auth user:", user.id, user.email);

const { error: userErr } = await admin.from("UserProfile").upsert(
  {
    id: user.id,
    email: user.email,
    name: user.email?.split("@")[0],
    theme: "dark",
    updatedAt: new Date().toISOString(),
  },
  { onConflict: "id" },
);
if (userErr) throw userErr;
console.log("UserProfile row ensured:", user.id);

// Report for .env convenience
console.log("\nPut these in .env for the shared test account:");
console.log(`SYNC_TEST_EMAIL=${email}`);
console.log(`SYNC_TEST_PASSWORD=${password}`);