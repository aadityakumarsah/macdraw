import "dotenv/config";
import ws from "ws";
import { createAdminClient } from "@supabase/server/core";

if (!globalThis.WebSocket) globalThis.WebSocket = ws;

const admin = createAdminClient();

// Drop leftover test pages the E2E/scripts created in active workspaces.
const { data: untitled } = await admin.from("Page").select("id,name,workspaceId").filter("name", "eq", "Untitled file");
if (untitled?.length) {
  await admin.from("Page").delete().in("id", untitled.map((r) => r.id));
  console.log("cleaned:", untitled.map((r) => `${r.name} (${r.id})`).join(", "));
} else {
  console.log("no leftover 'Untitled file' pages");
}

const { data: bareUntitled } = await admin.from("Page").select("id,name").filter("name", "eq", "Untitled");
if (bareUntitled?.length) {
  await admin.from("Page").delete().in("id", bareUntitled.map((r) => r.id));
  console.log(`cleaned ${bareUntitled.length} 'Untitled' pages (selftest artifacts)`);
}

const { count } = await admin.from("Page").select("id", { count: "exact", head: true }).filter("deletedAt", "is", null);
console.log(`live pages remaining: ${count}`);