// Checks config.js against the live Supabase project using only the public key.
//   node scripts/check-supabase.mjs           read-only checks
//   node scripts/check-supabase.mjs --write   also posts one test note and one 4/4 quiz attempt
// Needs Node 18+ (built-in fetch). Never put a secret key in config.js.
import fs from "node:fs";
import vm from "node:vm";

const write = process.argv.includes("--write");
const sandbox = { window: {} };
vm.runInNewContext(fs.readFileSync(new URL("../config.js", import.meta.url), "utf8"), sandbox);
const cfg = sandbox.window.SUPABASE_CONFIG || {};
const url = String(cfg.url || "").trim().replace(/\/+$/, "");
const key = String(cfg.publishableKey || "").trim();

let failed = 0;
const ok = (name, cond, extra = "") => { if (!cond) failed++; console.log((cond ? "PASS " : "FAIL ") + name + (extra ? "  " + extra : "")); };

ok("config.js has a project URL", /^https:\/\/[^\s/]+$/.test(url), url || "(empty)");
ok("config.js has a publishable key", !!key && !/^YOUR_/.test(key), key ? key.slice(0, 16) + "..." : "(empty)");
const isSecret = /^sb_secret_/.test(key) || (() => { try { return JSON.parse(Buffer.from(key.split(".")[1], "base64url")).role === "service_role"; } catch { return false; } })();
ok("key is NOT a secret/service_role key", !isSecret, isSecret ? "REMOVE IT and rotate it in the dashboard" : "");
if (failed) { console.log("\nFix config.js first (see README > Supabase setup)."); process.exit(1); }

const H = { apikey: key, "Content-Type": "application/json" };
if (!key.startsWith("sb_")) H.Authorization = "Bearer " + key; // legacy anon JWT
async function call(method, path, body, extra = {}) {
  try {
    const r = await fetch(url + "/rest/v1/" + path, { method, headers: { ...H, ...extra }, body: body && JSON.stringify(body) });
    const text = await r.text(); let json = null; try { json = JSON.parse(text); } catch {}
    return { status: r.status, json, text };
  } catch (e) { return { status: 0, text: String(e.cause?.code || e.message) }; }
}
const brief = r => `HTTP ${r.status} ${(r.text || "").slice(0, 140)}`;

let r = await call("GET", "birthday_messages?select=id,name,message,created_at&order=created_at.desc&limit=3");
ok("read birthday_messages", r.status === 200 && Array.isArray(r.json), r.status === 200 ? r.json.length + " row(s) visible" : brief(r));
r = await call("GET", "quiz_scores?select=id,name,score,total_questions,created_at&order=score.desc,created_at.asc,id.asc&limit=5");
ok("read quiz_scores (leaderboard order)", r.status === 200 && Array.isArray(r.json), r.status === 200 ? r.json.map(x => `${x.name} ${x.score}/4`).join(", ") || "empty" : brief(r));
r = await call("GET", "quiz_answer_key?select=*");
ok("answer key is hidden from the public", r.status >= 400 || (Array.isArray(r.json) && r.json.length === 0), brief(r));
r = await call("POST", "quiz_scores", { name: "check-script cheat", score: 4, total_questions: 4 }, { Prefer: "return=minimal" });
ok("direct score insert is refused", r.status === 401 || r.status === 403, brief(r));
r = await call("PATCH", "birthday_messages?id=gt.0", { message: "x" }, { Prefer: "return=representation" });
ok("updating messages is refused", r.status === 401 || r.status === 403 || (Array.isArray(r.json) && r.json.length === 0), brief(r));
r = await call("DELETE", "quiz_scores?id=gt.0", null, { Prefer: "return=representation" });
ok("deleting scores is refused", r.status === 401 || r.status === 403 || (Array.isArray(r.json) && r.json.length === 0), brief(r));
r = await call("POST", "rpc/submit_quiz_attempt", { p_name: "check", p_answers: [3, 0, 1] });
ok("grader rejects 3 answers", r.status === 400 && /4 answers/.test(r.text), brief(r));

if (write) {
  r = await call("POST", "birthday_messages?select=id,name,message,created_at", { name: "Setup check", message: "Test note from scripts/check-supabase.mjs (safe to delete)" }, { Prefer: "return=representation" });
  ok("insert a test note", r.status === 201 && r.json?.[0]?.id, brief(r));
  r = await call("POST", "rpc/submit_quiz_attempt", { p_name: "Setup check", p_answers: [3, 0, 1, 0] });
  ok("grader stores all-correct answers as 4/4", r.status === 200 && r.json?.score === 4 && r.json?.total_questions === 4, brief(r));
  r = await call("POST", "rpc/submit_quiz_attempt", { p_name: "Setup check", p_answers: [0, 1, 2, 3] });
  ok("grader stores all-wrong answers as 0/4", r.status === 200 && r.json?.score === 0, brief(r));
  console.log("Test rows are named 'Setup check'; delete them in Table Editor when done.");
} else console.log("(read-only run; add --write to also test inserts)");

console.log(failed ? `\n${failed} check(s) failed.` : "\nAll checks passed.");
process.exit(failed ? 1 : 0);
