# Aakshi's 19th birthday

A single static page (`index.html`): scrapbook cover, countdown, sticky-note message board, quiz and leaderboard.
The message board and leaderboard are shared between all visitors through a [Supabase](https://supabase.com) Postgres database.
There is no build step and no server; the page talks to Supabase directly with the public publishable key.

| File | What it is |
| --- | --- |
| `index.html` | The whole site (HTML, CSS, JS). |
| `config.js` | Public Supabase settings (project URL + publishable key). |
| `supabase/schema.sql` | Database migration: tables, constraints, permissions, Row Level Security, Realtime. |

## Supabase setup

### 1. Create the project

1. Sign in at <https://supabase.com/dashboard> and click **New project**.
2. Pick any name (e.g. `aakshi-birthday`), set a database password (keep it to yourself, it never goes in this repo), choose a region near your visitors (e.g. Mumbai), and create it. Wait until it says the project is ready.

### 2. Run the migration

1. In the project, open **SQL Editor** → **New query**.
2. Paste the whole of [`supabase/schema.sql`](supabase/schema.sql) and click **Run**. You should see "Success. No rows returned".
3. Check **Table Editor**: `birthday_messages` and `quiz_scores` should be there, both marked RLS enabled.

The file is safe to run again later (for example after you edit it).

It sets up:

- `birthday_messages` (`id`, `name` ≤ 60 chars, `message` ≤ 1000 chars, `created_at`) and `quiz_scores` (`id`, `name` ≤ 60, `score` 0–4, `total_questions` = 4, `created_at`). Blank or whitespace-only text is rejected.
- Row Level Security on both tables with only a SELECT and an INSERT policy for the `anon` role.
- Privileges revoked and re-granted narrowly: anon can read, and can insert only `name`/`message` (or `name`/`score`/`total_questions`). It cannot set `id` or `created_at`, and it cannot UPDATE, DELETE or TRUNCATE.
- Both tables added to the `supabase_realtime` publication so open pages get new notes and scores live.

### 3. Put the URL and publishable key in `config.js`

1. In the dashboard, open **Project Settings** → **API Keys** (or use the **Connect** button at the top of the project).
2. Copy the **Project URL** (`https://<project-ref>.supabase.co`). It's under **Project Settings** → **Data API** if it isn't shown next to the keys.
3. Copy the **Publishable key** (starts with `sb_publishable_`). If your project only shows legacy keys, use the **`anon` `public`** key instead (a long `eyJ...` string).
4. Edit `config.js`:

   ```js
   window.SUPABASE_CONFIG = {
     url: "https://<project-ref>.supabase.co",
     publishableKey: "sb_publishable_..."
   };
   ```

5. Commit and push. GitHub Pages serves `config.js` next to `index.html`; nothing else needs configuring.

**About the key:** the publishable / anon key is meant to be public. Every visitor's browser downloads it, so committing it is fine. It is only safe because the migration limits what that key can do (read, and add rows). Never put the **secret key** (`sb_secret_...`), the legacy **`service_role`** key, or the database password in `config.js`, in `index.html`, or anywhere in this repo. The page refuses to start with a secret key and logs an error if you paste one by mistake. If that ever happens, rotate the key in the dashboard.

If `config.js` still has the placeholders, the board and leaderboard say "isn't connected yet (…reason…)" and the browser console (F12) explains what's missing. The rest of the page keeps working.

### 4. Test it across two browsers or devices

Open the live site in two different browsers (e.g. Chrome on your laptop and your phone), side by side.

1. **Messages:** in browser A, post a note. A shows "Your note is up on the board for everyone" with the WhatsApp button, and the note appears with "(you)" and a timestamp. Browser B shows it within a second or two without refreshing (Realtime). Refresh B: it's still there.
2. **Validation:** try a name or message made only of spaces. The form refuses it with a message and nothing is saved.
3. **HTML is shown as text:** post a note like `<b>hi</b><script>alert(1)</script>`. It should appear literally, not bold, with no alert.
4. **Quiz:** in A, take the quiz and get e.g. 2/4. The result screen says "Saving…" then "Saved!", and the leaderboard updates in A and B. Use **Try again** and get 4/4: that's a second row, ranked above. To cover 0–4, answer the first *k* questions right and the rest wrong.
5. **Ordering:** two people with the same score are ordered by who finished first.
6. **Errors:** turn on airplane mode in A and submit a note. You get a "couldn't reach the server" message, your text stays in the form, and you can submit again once you're back online.
7. **No edits or deletes:** in the SQL Editor, run the check below. Each statement should fail with `permission denied`:

   ```sql
   set role anon;
   update public.birthday_messages set message = 'x';  -- ERROR: permission denied
   ```
   ```sql
   set role anon;
   delete from public.quiz_scores;  -- ERROR: permission denied
   ```
   (Run each block on its own and then `reset role;`, or just open a new query tab.)

### Moderating

Visitors can't edit or delete anything, but you can. Open **Table Editor** → pick the table → select rows → delete. Pages that are already open drop the row on their next refresh.

## How it behaves

- **Message board:** loads the newest 200 notes on page load, newest first. New notes from anyone appear live. Submitting disables the button while saving ("Sticking it up..."), so double clicks don't post twice. The note is then added to the board and the WhatsApp share button is offered as before.
- **Quiz:** questions, answers and scoring are unchanged. The name entered before the quiz is the leaderboard name. When the quiz ends, the actual score from that run is saved once. If saving fails there's a "Try saving again" button.
- **Retakes:** every finished attempt is stored as its own row. That matches the existing "Try again" button and the old leaderboard, which also listed every attempt. The leaderboard shows the top 25 (score high to low, then earliest attempt first).
- **"(you)" tags:** each browser remembers the ids of rows it posted (in localStorage) and tags them "(you)". That tag is cosmetic only.
- **Live updates:** one Realtime channel listens for INSERTs on the two tables. Rows are kept by id, so a row that arrives through both the insert response and Realtime is shown once. The channel is closed on `pagehide` and reopened if the page is restored from the back/forward cache. If Realtime is unavailable, the board still updates after your own posts and when you come back to the tab (after 30s away).
- **Old device-only notes/scores:** before this change, notes and scores were saved only in the visitor's own browser. They are not uploaded automatically. If a browser still has some, the page shows "N notes from before the shared board are saved only on this device" with an **Add to the shared board** button (same for scores). Once uploaded, the local copy is cleared. Old scores keep their score but not their time, since the shared table doesn't store a duration.
- **`DATA_NOTES` / `DATA_SCORES`** at the top of the script still work for adding entries by hand. They're shown alongside the database rows.
- **Limits:** the form keeps its original limits (name 40, message 280 characters) so notes still fit the sticky-note design. The database accepts up to 60 / 1000. To allow longer input, change `NAME_MAX` / `MSG_MAX` in `index.html` along with the `maxlength` attributes and the `/280` counter.

## Known limitations

- **Scores are reported by the browser, not verified by the server.** The quiz runs entirely in the visitor's browser, and the answers ship with the page. Anyone who opens dev tools can submit any score from 0 to 4 under any name, or read the answers. The database only guarantees that a score is a whole number from 0 to 4, out of 4, with a server-set timestamp. Server-side verification would need the answers hidden from the page and checked by a Supabase Edge Function or similar. That's more infrastructure than a casual birthday quiz needs. Treat the leaderboard as for fun, not as cheat-proof.
- **Anyone can post.** There are no accounts, CAPTCHA or rate limits beyond Supabase's defaults, so someone could spam notes or scores. Delete unwanted rows in the Table Editor. If it becomes a problem, options include Supabase's rate limiting, a CAPTCHA, or a moderation flag column.
- **Time per quiz isn't stored.** The table has the fields asked for (no duration), so ties are broken by who finished first rather than fastest time. The result screen and the WhatsApp message still show the time.
- **Third-party script.** `@supabase/supabase-js@2.117.2` loads from jsDelivr, pinned to an exact version and integrity-checked (SRI). If the CDN is blocked, the board/leaderboard show "not connected" and the rest of the page works.
