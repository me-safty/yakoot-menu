# Yakoot Menu

Astro restaurant menu site backed by PocketBase.

## Env

Copy `.env.example` to `.env` and set:

```sh
PUBLIC_POCKETBASE_URL=http://0.0.0.0:8090
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
http://0.0.0.0:8090/_/
```

The first launch creates `pb_data/` and applies migrations.

Tracked migration creates collection `categories`:

| Field | Type | Notes |
| --- | --- | --- |
| `name` | text | required |
| `menuImage` | file | required, max files 10, jpg/png/webp |
| `sort` | number | optional |
| `isActive` | bool | required |

Public list/view rule:

```txt
isActive = true
```

Tracked migration also creates collection `site_settings` for footer and social links:

| Field | Type | Notes |
| --- | --- | --- |
| `logo` | file | optional, jpg/png/webp/svg |
| `footerLogo` | file | optional, jpg/png/webp/svg |
| `hours` | text | required |
| `facebookUrl` | url | optional |
| `instagramUrl` | url | optional |

Only one `site_settings` record can exist.

Public list/view rule:

```txt
public
```

Tracked migration creates collection `footer_addresses`:

| Field | Type | Notes |
| --- | --- | --- |
| `address` | text | required |
| `description` | text | optional |
| `phoneNumber` | text | required |
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
