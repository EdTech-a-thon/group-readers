# Group Readers

Instantly generate reading groups based on your students' book preferences. A teacher creates a private account, adds their books, and shares an unlisted link. Students rank their favourites, and the teacher sees all choices in one dashboard and builds groups from them.

Each book list says how many books its students rank — anywhere from 2 to 10, four by default. That number is also the point at which the list's student link opens: a list holding fewer books than its students are asked to rank is not ready yet. Beyond it, a list is as long as its teacher wants, up to thirty books. Both the number ranked and the books themselves stay put once the first student has answered, so every ranking keeps meaning the same thing.

Teachers keep a separate **book list** for each group of students they teach — one for 1st Period, one for 2nd Period, and so on. Every book list has its own unlisted student link, its own responses, and its own saved groups, so classes never see each other's answers. **Duplicate** copies a finished list's books into a new list, so the covers, titles, and descriptions only get set up once however many classes there are.

Signing in lands on the teacher dashboard, a card for each book list showing its description, how many books it holds, how many of them each student ranks, and how many students have answered. Opening a card goes to that one list at `/list/<id>`, where its books, student choices, and groups live. Deep links work only because unknown paths fall back to `index.html` — the same rewrite the student links at `/student/<token>` already need.

Accounts, data, and cover images all live in a [Supabase](https://supabase.com) project.

## First-time setup

1. Create a project at [supabase.com](https://supabase.com).
2. Go to **Authentication → Sign In / Providers → Email** and turn **Confirm email** off. The app never sends email, so leaving this on would create accounts that can never sign in.
3. Go to **SQL Editor → New query**, paste in everything from `supabase/schema.sql`, and press Run. That creates the tables, permission rules, cover storage, and server logic. It expects an empty project; if you have run an earlier version of the file, uncomment the "Starting over" block at the top first, which throws away all existing books and responses.
4. Copy `.env.example` to `.env`, then fill in the Project URL and the `anon` public key from **Project Settings → API**.

## Run

```bash
bun install
bun run build
bun run start
```

`bun run dev` starts the same site with live reloading while you are making changes.

## Checks

```bash
bun run check
bun run build
```

## Looking after the data

Teacher accounts, book lists, books, student responses, and saved groups are all visible in the Supabase dashboard — accounts under **Authentication → Users**, everything else under **Table Editor**, and cover images under **Storage → covers**. The `share_token` on a row in `book_lists` is the secret in that list's student link.

Because the app sends no email, there is no "forgot password" link. If a teacher is locked out, reset their password for them from **Authentication → Users**.
