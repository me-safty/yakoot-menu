# Yakoot Menu

Astro restaurant menu site backed by PocketBase.

## Env

Copy `.env.example` to `.env` and set:

```sh
PUBLIC_POCKETBASE_URL=http://127.0.0.1:8090
```

## PocketBase

PocketBase CMS source is in repo:

- `pb_migrations/`: schema
- `scripts/install-pocketbase.mjs`: local binary installer
- `pb_data/`: local CMS data, ignored
- `.tools/pocketbase`: downloaded binary, ignored

Run:

```sh
pnpm run pb:install
pnpm run pb:serve
```

Admin UI:

```txt
http://127.0.0.1:8090/_/
```

The first launch creates `pb_data/` and applies migrations.

Tracked migration creates collection `categories`:

| Field | Type | Notes |
| --- | --- | --- |
| `name` | text | required |
| `slug` | text | required, unique |
| `menuImage` | file | required, max files 1, jpg/png/webp |
| `sort` | number | optional |
| `isActive` | bool | required |

Public list/view rule:

```txt
isActive = true
```

## Commands

```sh
pnpm dev
pnpm run pb:install
pnpm run pb:serve
pnpm run dev:all
pnpm build
pnpm preview
```
