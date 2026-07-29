# Book Club Builder

A teacher creates a private account, adds ten books, and shares an unlisted link. Students rank four books, and the teacher sees all choices in one dashboard.

Accounts, data, and cover images all live in a [Supabase](https://supabase.com) project.

## First-time setup

1. Create a project at [supabase.com](https://supabase.com).
2. Go to **Authentication → Sign In / Providers → Email** and turn **Confirm email** off. The app never sends email, so leaving this on would create accounts that can never sign in.
3. Go to **SQL Editor → New query**, paste in everything from `supabase/schema.sql`, and press Run. That creates the tables, permission rules, cover storage, and server logic.
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

Teacher accounts, books, student responses, and saved groups are all visible in the Supabase dashboard — accounts under **Authentication → Users**, everything else under **Table Editor**, and cover images under **Storage → covers**.

Because the app sends no email, there is no "forgot password" link. If a teacher is locked out, reset their password for them from **Authentication → Users**.
