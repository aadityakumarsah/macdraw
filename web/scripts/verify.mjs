import puppeteer from "puppeteer-core";

const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const browser = await puppeteer.launch({ executablePath: chrome, headless: "new" });
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });
await page.goto("http://localhost:4173", { waitUntil: "networkidle0" });

const checks = await page.evaluate(() => {
  const out = {};
  const $ = (sel) => document.querySelector(sel);
  const g = (sel) => getComputedStyle(t0(sel));
  const t0 = (sel) => document.querySelector(sel);
  const css = (el) => (el ? getComputedStyle(el) : null);

  out.font = css(document.body).fontFamily;
  out.bodyBg = css(document.body).backgroundColor;

  const sidebar = document.querySelector("aside");
  const sRow = sidebar?.getBoundingClientRect();
  out.sidebar = sRow ? { w: Math.round(sRow.width) } : null;

  const nav = [...document.querySelectorAll("aside nav button")].map((b) => b.textContent?.trim());
  out.sidebarNav = nav;

  out.workspaceName = document.body.innerText.includes("Aaditya's Team");
  out.trialCard = document.body.innerText.includes("Fraser Free Trial");
  out.upgradeBtn = !!t0('[role="button"]') || document.body.innerText.includes("Upgrade plan");
  out.newFileBtn = [...document.querySelectorAll("button")].filter((b) => b.textContent?.includes("New File")).length;
  out.beta = document.body.innerText.includes("BETA");

  const tabs = [...document.querySelectorAll("header button")].map((b) => b.textContent?.trim());
  out.tabs = tabs;

  // action cards
  const cards = [...document.querySelectorAll("main button")].filter((b) => {
    const r = b.getBoundingClientRect();
    return r.height === 125 || (r.height > 110 && r.height < 140);
  });
  out.cardCount = cards.length;
  out.cardHeights = [...new Set(cards.map((c) => Math.round(c.getBoundingClientRect().height)))];
  out.cardW = cards[0] ? Math.round(cards[0].getBoundingClientRect().width) : 0;
  out.cardBg = cards[0] ? css(cards[0]).backgroundColor : null;

  // table headers
  const th = [...document.querySelectorAll("main span")].map((s) => s.textContent?.trim());
  out.hasColumns = ["NAME", "LOCATION", "CREATED", "EDITED", "COMMENTS", "AUTHOR"].every((c) => th.includes(c) || document.body.innerText.includes(c));

  const rows = [...document.querySelectorAll('[role="button"]')].filter((b) => b.textContent?.includes("react roadmap"));
  out.fileRowsWithName = rows.length;
  const rowRect = rows[0];
  out.rowShown = rowRect ? Math.round(rowRect.getBoundingClientRect().height) : null;

  out.search = !!document.querySelector('input[placeholder="Search"]');
  out.invite = document.body.innerText.includes("Invite");
  out.cmdK = document.body.innerText.includes("⌘K");
  return out;
});

console.log(JSON.stringify(checks, null, 2));

await page.screenshot({ path: "/tmp/macdraw-web-shot.png", fullPage: true });
console.log("screenshot: /tmp/macdraw-web-shot.png");

// tab interaction: click Recents
await page.evaluate(() => {
  [...document.querySelectorAll("header button")].find((b) => b.textContent?.trim() === "Recents")?.click();
});
await new Promise((r) => setTimeout(r, 300));
const rowsAfter = await page.evaluate(() =>
  [...document.querySelectorAll('[role="button"]')].filter((b) => b.textContent?.includes(" ago") || b.textContent?.includes("yesterday")).length,
);
console.log("rows after switching to Recents + search:", rowsAfter);

// search filters
await page.evaluate(() => {
  const i = document.querySelector('input[placeholder="Search"]');
  i.value = "budget";
  i.dispatchEvent(new Event("input", { bubbles: true }));
});
await new Promise((r) => setTimeout(r, 200));
const filterResult = await page.evaluate(() => document.body.innerText.includes("budget flowchart"));
console.log("search 'budget' shows only budget flowchart:", !document.body.innerText.includes("canvas ideas"));

await browser.close();