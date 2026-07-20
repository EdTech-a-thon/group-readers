# Book Club Builder

A teacher creates a private account, adds ten books, and shares an unlisted link. Students rank four books, and the teacher sees all choices in one dashboard.

## Run

```bash
bun install
bun run build
./pocketbase serve --http=0.0.0.0:8000
```

PocketBase applies the migrations in `pb_migrations` automatically. The website is served from `pb_public`, the API is under `/api`, and PocketBase's administration dashboard is at `/_/`.

## Checks

```bash
bun run check
bun run build
```

PocketBase data and uploaded covers are stored in the ignored `pb_data` directory. Back up that directory separately from the source code.
