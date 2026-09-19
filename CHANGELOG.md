# Changelog

All notable changes to this gem are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the gem follows Semantic Versioning. Versions stay
`0.x` until the opt-in live tests have recorded real TikTok Shop responses over the documentation fixtures.

## [Unreleased]

### Added

- The first release surface of the shared interface (`CONTRACT.md`, `CONTRACT_VERSION = "2"`): `Client`, `Auth`,
  `Shop`, categories, brands, media, products (including `relist`, which is TikTok's re-audited activate), stock,
  prices, read-only orders, webhooks, `request`, `Response`, `Pager`, the error tree, `RetryPolicy` and
  `Transport::NetHttp` (RAC-277).
- TikTok extensions: the `Client.new` keywords `service_id:` and `token_base_url:`, `warehouses`,
  `categories.rules`, `products.replace`, `products.check_listing` and `products.diagnoses` (RAC-277).
- Every TikTok host as configuration: the `ENDPOINTS` table (`:row` default, `:us`), each naming the API, consent
  and token hosts, plus `base_url:` / `auth_base_url:` / `token_base_url:` for any other host (RAC-277).
- Per-endpoint version constants, the header-borne access token, signing over the exact body bytes, and
  `idempotency_key` making a create idempotent (RAC-277).
- Opt-in live tests (`rake test:live`) that can record redacted responses into `test/fixtures/`, never orders and with
  personal-data keys redacted (RAC-277).
