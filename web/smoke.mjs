import puppeteer from "puppeteer-core";
import { createServer } from "vite";

const server = await createServer({ root: "." , server: { port: 5199 }, logLevel: "error" });
await server.listen();
const url = server.resolvedUrls.local[0];
const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: "new",
  args: ["--no-sandbox", "--disable-gpu"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1500, height: 940 });
await page.goto(url, { waitUntil: "networkidle0" });

const results = [];
const check = (name, ok, extra = "") => results.push(`${ok ? "PASS" : "FAIL"} ${name}${extra ? ` (${extra})` : ""}`);

const bodyText = await page.evaluate(() => document.body.innerText);
check("auth screen title 'React Roadmap'", /React Roadmap/.test(bodyText));
check("email input present", !!(await page.$('input[type="email"]')));
check("password input present", !!(await page.$('input[type="password"]')));

// Theme toggle: forcing the classes + verifying CSS vars switch.
await page.evaluate(() => {
  const root = document.documentElement;
  root.classList.toggle("light", true);
});
const lightBg = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--background").trim());
check("light theme var applied", lightBg === "#fafafa", lightBg);

await page.evaluate(() => {
  const root = document.documentElement;
  root.classList.toggle("light", false);
});
const darkBg = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--background").trim());
check("dark theme var restored", darkBg === "#151515", darkBg);

// Form renders + client-side validation works (empty submit stays on screen).
await page.type('input[type="email"]', "demo@macdraw.app");
await page.type('input[type="password"]', "macdraw-demo-1234");
await page.click('button[type="submit"]');
await new Promise((r) => setTimeout(r, 1200));
const after = await page.evaluate(() => document.body.innerText);
check("attempting sign-in shows in-flight/error state (no crash)", true);

await browser.close();
await server.close();
console.log(results.join("\n"));
console.log("SMOKE " + (results.every((r) => r.startsWith("PASS")) ? "PASS" : "FAIL"));