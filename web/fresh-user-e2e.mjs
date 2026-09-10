import dotenv from "dotenv";
import ws from "ws";
import puppeteer from "puppeteer-core";
import { createServer } from "vite";
import { createAdminClient } from "@supabase/server/core";
dotenv.config({ path: "../.env" });
if (!globalThis.WebSocket) globalThis.WebSocket = ws;

const admin = createAdminClient();
const freshEmail = `fresh-${Date.now().toString(36)}@gmail.com`;
const password = "macdraw-demo-1234";

const { data: created, error: createErr } = await admin.auth.admin.createUser({
  email: freshEmail,
  password,
  email_confirm: true,
});
if (createErr) throw createErr;
const uid = created.user.id;
console.log(`created fresh user: ${freshEmail} (${uid})`);

const server = await createServer({ root: ".", server: { port: 5203 }, logLevel: "error" });
await server.listen();
const url = server.resolvedUrls.local[0];
const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: "new",
  args: ["--no-sandbox", "--disable-gpu"],
});
const page = await browser.newPage();
const consoleMsgs = [];
page.on("console", (m) => consoleMsgs.push(m.text()));
page.on("pageerror", (e) => consoleMsgs.push("PAGEERROR " + e.message));

const results = [];
const check = (name, ok, extra = "") => results.push(`${ok ? "PASS" : "FAIL"} ${name}${extra ? ` (${extra})` : ""}`);

await page.goto(url, { waitUntil: "networkidle0" });

// Use the browser session directly (bypasses sign-up in the UI, same end state).
await page.evaluate(async ({ email, password }) => {
  const { supabase } = await import("/src/lib/supabase.ts");
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
}, { email: freshEmail, password });

let ok = false;
for (let i = 0; i < 30; i++) {
  await new Promise((r) => setTimeout(r, 500));
  const t = await page.evaluate(() => document.body.innerText);
  if (t.includes("Something went wrong")) break;
  if (t.includes("react roadmap")) { ok = true; break; }
}
const finalText = await page.evaluate(() => document.body.innerText);
check("fresh user dashboard loads (no error)", ok && !finalText.includes("Something went wrong"), finalText.slice(0, 150).replace(/\n/g, " "));
check("seed page created for fresh user", finalText.includes("react roadmap"), "");

// Confirm the profile row + defaultWorkspaceId persisted (the old bug: never).
const { data: prof } = await admin.from("UserProfile").select("id,defaultWorkspaceId,email").eq("id", uid).maybeSingle();
check("profile row created", !!prof?.defaultWorkspaceId, JSON.stringify(prof));

await browser.close();
await server.close();

// Cleanup: remove the fresh user's data + auth user.
if (prof?.defaultWorkspaceId) {
  await admin.from("Page").delete().eq("workspaceId", prof.defaultWorkspaceId);
  await admin.from("WorkspaceMember").delete().eq("workspaceId", prof.defaultWorkspaceId);
  await admin.from("Workspace").delete().eq("id", prof.defaultWorkspaceId);
}
await admin.from("UserProfile").delete().eq("id", uid);
await admin.auth.admin.deleteUser(uid);
console.log("cleaned up fresh user");

console.log(results.join("\n"));
console.log("FRESH-USER " + (results.every((r) => r.startsWith("PASS")) ? "PASS" : "FAIL"));