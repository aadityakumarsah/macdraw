import puppeteer from "puppeteer-core";
import { createServer } from "vite";

const server = await createServer({ root: ".", server: { port: 5201 }, logLevel: "error" });
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

// --- Sign in as the shared demo account ---
await page.type('input[type="email"]', "demo@macdraw.app");
await page.type('input[type="password"]', "macdraw-demo-1234");
await page.click('button[type="submit"]');

// Wait for the dashboard to replace the auth screen with real workspace data.
let dashboardText = "";
for (let i = 0; i < 30; i++) {
  await new Promise((r) => setTimeout(r, 500));
  dashboardText = await page.evaluate(() => document.body.innerText);
  if (dashboardText.includes("react roadmap")) break;
}
check("dashboard loads with seeded page", dashboardText.includes("react roadmap"), dashboardText.slice(0, 120).replace(/\n/g, " "));

// --- Back to the dashboard (Files list) ---
await page.evaluate(() => {
  const btn = [...document.querySelectorAll("button")].find((b) => b.innerText.trim() === "Files");
  if (btn) btn.click();
});
await new Promise((r) => setTimeout(r, 1200));
dashboardText = await page.evaluate(() => document.body.innerText);
check("dashboard (files list) view", /Aaditya's Team/.test(dashboardText) && /Generate an AI Diagram/.test(dashboardText), dashboardText.slice(0, 150).replace(/\n/g, " "));

// --- Connection badge should report live sync ---
const liveBadge = /live|synced|connected/i;
check("connection status shown", liveBadge.test(dashboardText), dashboardText.slice(0, 120).replace(/\n/g, " "));

// --- Real-time: an external client changes a page; the open web app must
// show the change without reloading (proves the realtime subscription). ---
import { createClient } from "@supabase/supabase-js";
import ws from "ws";
const EXT = createClient("https://fabdvbwvuohznuhlsgqj.supabase.co", "sb_publishable_N4gaQKtPRNi85x5V8kQl0Q_gjLit033", {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});
if (typeof WebSocket === "undefined") globalThis.WebSocket = ws;
const { data: sess } = await EXT.auth.signInWithPassword({ email: "demo@macdraw.app", password: "macdraw-demo-1234" });
const { data: prof } = await EXT.from("UserProfile").select("defaultWorkspaceId").eq("id", sess.session.user.id).single();
const extNow = new Date().toISOString();
const rtId = "page_rtcheck_" + Date.now().toString(36);
await EXT.from("Page").insert({
  id: rtId,
  workspaceId: prof.defaultWorkspaceId,
  parentId: null,
  name: "realtime-check",
  description: null,
  icon: null,
  orderIndex: 50,
  contentJson: "{}",
  createdBy: sess.session.user.id,
  createdAt: extNow,
  updatedAt: extNow,
  deletedAt: null,
  version: 1,
});

let rtSeen = false;
let htmlDump = "";
for (let i = 0; i < 12; i++) {
  await new Promise((r) => setTimeout(r, 500));
  htmlDump = await page.evaluate(() => document.body.innerHTML);
  if (htmlDump.includes("realtime-check")) { rtSeen = true; break; }
}
check("web shows external realtime insert", rtSeen, rtSeen ? "" : htmlDump.slice(0, 300));
await EXT.from("Page").delete().eq("id", rtId).maybeSingle();

// --- Create a page: the New File button itself creates a blank file (its
// dropdown also offers AI/template flows) and opens it in the editor. ---
const created = await page.evaluate(async () => {
  const buttons = [...document.querySelectorAll("button")];
  const newBtn = buttons.find((b) => b.innerText.includes("New File"));
  if (!newBtn) return "no-new-file-button";
  newBtn.click();
  await new Promise((r) => setTimeout(r, 1500));
  return "clicked";
});
check("create flow triggered", created === "clicked", created);

dashboardText = await page.evaluate(() => document.body.innerText);
check("web-created page listed", dashboardText.includes("Untitled file"), dashboardText.slice(0, 200).replace(/\n/g, " "));

check("no console/page errors", !consoleMsgs.some((m) => m.includes("PAGEERROR")), consoleMsgs.join(" | ").slice(0, 160));

await browser.close();
await server.close();
console.log(results.join("\n"));
console.log("WEB-E2E " + (results.every((r) => r.startsWith("PASS")) ? "PASS" : "FAIL"));