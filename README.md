# tiktok_shop_rb_api

A Ruby client for the [TikTok Shop Partner API](https://partner.tiktokshop.com/docv2/page/tts-api-concepts-overview)
(the "TTS API"): signed requests, seller authorization and tokens, catalogue, products, stock, prices, read-only
orders, and webhook verification. No runtime dependencies: `net/http`, `openssl` and `json` from the standard library.

It is a library. It implements TikTok Shop faithfully and configurably and leaves every deployment decision to you:
which host, which app type (a partner app or a seller in-house app), when to refresh or ask a seller to re-consent,
and how to store tokens. It is multi-shop from the start: one authorization can cover several shops, and nothing
assumes one shop per token or one token per app.

It is one of three sibling gems (`shopee_rb_api`, `lazada_rb_api`, `tiktok_shop_rb_api`) that share one interface,
written down in [CONTRACT.md](CONTRACT.md). Code written against one of them reads the same against the others.

Status: `0.x`. The response fixtures come from TikTok's documentation samples; the version stays below 1.0 until the
opt-in live tests (see Testing) have recorded real responses over them.

## Installation

The gem is not published to RubyGems. Pin it by git tag:

```ruby
# Gemfile
gem "tiktok_shop_rb_api", git: "https://github.com/rymndcs/tiktok_shop_rb_api.git", tag: "v0.1.0"
```

Ruby 3.3 or newer.

## Configuration

One `Client` per TikTok Shop app. There is no global configuration; the client is immutable and thread-safe.

```ruby
require "tiktok_shop_rb_api"

client = TiktokShopRbApi::Client.new(
  app_key: ENV.fetch("TTS_APP_KEY"),
  app_secret: ENV.fetch("TTS_APP_SECRET"),
  service_id: ENV.fetch("TTS_SERVICE_ID"),        # only authorize_url needs it
  endpoint: :row,                                  # default; see the table below
  transport: TiktokShopRbApi::Transport::NetHttp.new(open_timeout: 5, read_timeout: 30),
  clock: -> { Time.now },
  logger: Rails.logger,                            # debug lines only; never a secret
  retry_policy: TiktokShopRbApi::RetryPolicy.none  # the default: the gem never retries on its own
)
```

Hosts are configuration, not code. `endpoint:` picks all three TikTok hosts from `TiktokShopRbApi::ENDPOINTS`
([Authorization domains by market](https://partner.tiktokshop.com/docv2/page/authorization-overview-202407)):

| `endpoint:` | API host | Seller authorization host | Token host |
|---|---|---|---|
| `:row` (default) | `https://open-api.tiktokglobalshop.com` | `https://services.tiktokshop.com` | `https://auth.tiktok-shops.com` |
| `:us` | `https://open-api.tiktokglobalshop.com` | `https://services.us.tiktokshop.com` | `https://auth.tiktok-shops.com` |

TikTok serves every market from one API host; the `shop_cipher` picks the shop, and the name only picks the seller
authorization host (the Philippines and the rest of Southeast Asia are `:row`). For any other host (a proxy, a host
TikTok adds later) pass a URL:

```ruby
TiktokShopRbApi::Client.new(app_key: key, app_secret: secret,
                            base_url: "https://tts-egress.internal",          # API host
                            auth_base_url: "https://services.tiktokshop.com", # seller authorization host
                            token_base_url: "https://tts-token.internal")     # token host
```

Before the first call, add your server's IP addresses to the app's allow list in Partner Center; TikTok refuses
others (`36009033`, a `PermissionError`). Keep the server clock right: TikTok accepts a request timestamp only within
**five minutes behind to thirty seconds ahead** of its own clock, so a clock running 31 seconds fast fails every call.

## Authorization

The gem stores no tokens and never refreshes on its own. An access token lives 7 days by default; the refresh token
lives as long as the authorization the seller granted. A refresh returns a new refresh token too, so persist both
tokens of every `Grant` in one write before doing anything else.

```ruby
# 1. Send the seller to the authorization link. The redirect URL is fixed in Partner Center, so there is no
#    redirect_uri: (passing one raises ArgumentError).
url = client.auth.authorize_url(state: csrf_token)

# 2. TikTok redirects back with code (valid 30 minutes, single use) and state.
grant = client.auth.exchange_code(code: params[:code])
grant.access_token; grant.refresh_token
grant.access_token_expires_at   # absolute UTC Time: TikTok's *_expire_in fields are Unix timestamps
grant.refresh_token_expires_at  # the end of the seller's authorization: a hard re-consent deadline
grant.raw["data"]               # open_id, seller_name, seller_base_region, user_type, granted_scopes

# 3. Refresh before the access token expires.
grant = client.auth.refresh(refresh_token: stored.refresh_token)

# One authorization can cover several shops: list them.
client.authorized_shops(access_token: grant.access_token).each do |ref|
  ref.shop_id; ref.name; ref.region; ref.locator  # => { shop_cipher: "ROW_..." }
end
```

The token endpoints are unsigned GETs that carry the app secret in the query, exactly as TikTok documents them. The
gem never logs a URL, so the secret stays out of your logs.

## Shop session (locator)

```ruby
shop = client.shop(access_token: stored.access_token, shop_cipher: "ROW_...")
shop.locator  # => { shop_cipher: "ROW_..." }; TiktokShopRbApi::Shop::LOCATOR_KEYS == [:shop_cipher]
```

The access token travels in the `x-tts-access-token` header and is never signed. The `shop_cipher` goes in the
query of every shop-scoped endpoint, and is left out of the two that refuse it (Get Authorized Shops and image
upload). `AuthorizedShop#locator` gives you the Hash to splat in.

## Capabilities

Every method makes exactly one request (iterating a `Pager` makes one per page). Identity arguments (`product_id`,
`category_id`, `order_id`, `seller_sku`, `title`) accept a String or an Integer; everything else is TikTok's own
field names, passed through untouched. Non-paged methods return a `TiktokShopRbApi::Response`. Each endpoint's version
is pinned in the gem, and bumped deliberately.

| Capability | Example | TikTok endpoint |
|---|---|---|
| Shop info | `shop.info.data["region"]` (this shop's entry) | [`GET /authorization/202309/shops`](https://partner.tiktokshop.com/docv2/page/get-authorized-shops-202309) |
| Listing prerequisites | `shop.limits.data["check_results"]` (pass or fail; TikTok publishes no number) | [`GET /product/202312/prerequisites`](https://partner.tiktokshop.com/docv2/page/check-listing-prerequisites-202312) |
| Category tree | `shop.categories.list(category_version: "v2", locale: "en-PH").data["categories"]` | [`GET /product/202309/categories`](https://partner.tiktokshop.com/docv2/page/get-categories-202309) |
| Category attributes | `shop.categories.attributes(600001, category_version: "v2").data["attributes"]` | [`GET /product/202309/categories/{id}/attributes`](https://partner.tiktokshop.com/docv2/page/get-attributes-202309) |
| Category suggestion | `shop.categories.recommend(title: "Bosch H4 bulb").data["leaf_category_id"]` | [`POST /product/202309/categories/recommend`](https://partner.tiktokshop.com/docv2/page/recommend-category-202309) |
| Brands | `shop.brands.list(category_id: 600001).each { \|b\| b["authorized_status"] }` | [`GET /product/202309/brands`](https://partner.tiktokshop.com/docv2/page/get-brands-202309) |
| Image upload | `shop.media.upload_image(File.open("bulb.jpg"), use_case: "MAIN_IMAGE").data["uri"]` | [`POST /product/202309/images/upload`](https://partner.tiktokshop.com/docv2/page/upload-product-image-202309) |
| Create product | `shop.products.create(payload, idempotency_key: key).data["product_id"]` | [`POST /product/202309/products`](https://partner.tiktokshop.com/docv2/page/create-product-202309) |
| Get product | `shop.products.get(id).data.dig("audit", "status")` | [`GET /product/202309/products/{id}`](https://partner.tiktokshop.com/docv2/page/get-product-202309) |
| Update product (partial) | `shop.products.update(id, { "product_attributes" => full_array })` | [`POST /product/202509/products/{id}/partial_edit`](https://partner.tiktokshop.com/docv2/page/partial-edit-product-202509) |
| List products | `shop.products.list(status: "ACTIVATE").each { \|p\| p["id"] }` | [`POST /product/202502/products/search`](https://partner.tiktokshop.com/docv2/page/search-products-202502) |
| Find by seller SKU | `shop.products.find_by_seller_sku("OT405") # => ["1729592969712207008"]` | [`POST /product/202502/products/search`](https://partner.tiktokshop.com/docv2/page/search-products-202502) (`seller_skus`) |
| Unlist | `shop.products.unlist(ids).item_errors` (≤ `Products::UNLIST_BATCH_MAX` = 20) | [`POST /product/202309/products/deactivate`](https://partner.tiktokshop.com/docv2/page/deactivate-products-202309) |
| Relist | `shop.products.relist(ids).item_errors` (≤ `Products::RELIST_BATCH_MAX` = 20; **re-audited**) | [`POST /product/202309/products/activate`](https://partner.tiktokshop.com/docv2/page/activate-product-202309) |
| Get stock | `shop.stock.get(id).data["inventory"]` | [`POST /product/202309/inventory/search`](https://partner.tiktokshop.com/docv2/page/inventory-search-202309) |
| Update stock | `shop.stock.update(id, [{ id: sku_id, inventory: [{ warehouse_id: wh, quantity: 10 }] }])` | [`POST .../products/{id}/inventory/update`](https://partner.tiktokshop.com/docv2/page/update-inventory-202309) |
| Update prices | `shop.prices.update(id, [{ id: sku_id, price: { amount: "189.00", currency: "PHP" } }])` | [`POST .../products/{id}/prices/update`](https://partner.tiktokshop.com/docv2/page/update-price-202309) |
| List orders (read-only) | `shop.orders.list(order_status: "UNPAID", sort_field: "create_time").each { \|o\| o["id"] }` | [`POST /order/202309/orders/search`](https://partner.tiktokshop.com/docv2/page/get-order-list-202309) |
| Get order (read-only) | `shop.orders.get("576461413038785752").data["orders"]` | [`GET /order/202507/orders`](https://partner.tiktokshop.com/docv2/page/get-order-detail-202507) |

**TikTok extensions** (declared in `TiktokShopRbApi::EXTENSIONS`; of these, `token_base_url:` also exists in Lazada's gem and `products.diagnoses` in Shopee's):

| Extension | Example | TikTok endpoint |
|---|---|---|
| Consent link key | `Client.new(..., service_id: "7310...")`, `client.service_id` | the seller authorization link |
| Token host | `Client.new(..., token_base_url: "https://...")`, `client.token_base_url` | Get Access Token / Refresh Token |
| Warehouses | `shop.warehouses.data["warehouses"].map { \|w\| w["id"] }` | [`GET /logistics/202309/warehouses`](https://partner.tiktokshop.com/docv2/page/get-warehouse-list-202309) |
| Category rules | `shop.categories.rules(600001, category_version: "v2").data["product_certifications"]` | [`GET /product/202309/categories/{id}/rules`](https://partner.tiktokshop.com/docv2/page/get-category-rules-202309) |
| Full replace | `shop.products.replace(id, full_payload)` | [`PUT /product/202509/products/{id}`](https://partner.tiktokshop.com/docv2/page/edit-product-202509) |
| Remote dry run | `shop.products.check_listing(payload).data["check_result"]  # "PASS" \| "FAILED"` | [`POST /product/202309/products/listing_check`](https://partner.tiktokshop.com/docv2/page/check-product-listing-202309) |
| Diagnoses | `shop.products.diagnoses(ids).data["products"]` (≤ 200 ids, ACTIVATE only) | [`GET /product/202405/products/diagnoses`](https://partner.tiktokshop.com/docv2/page/product-information-issue-diagnosis-202405) |

TikTok facts worth knowing before you publish:

- **Every product write is audited asynchronously.** Create, edit and relist return while the product is `PENDING`
  or `AUDITING`; read the outcome from `products.get` (`audit.status`) or from webhook types 5 and 37. Price and
  inventory updates skip audit.
- **`products.update` is TikTok's partial edit, per top-level property:** a property you send replaces the whole
  property (send `product_attributes` and the whole array is replaced; send `skus` and any SKU you leave out is
  deleted). The gem never merges; read the product first. `products.replace` overwrites every field, blanks
  included, and deletes omitted SKUs.
- **A successful create can drop a field:** read `response.warnings` (for example a `brand_id` "automatically
  cleared by the system").
- Southeast Asian and US shops must send `category_version: "v2"` (the 7-level tree). Category data is per shop
  (`permission_statuses`, brand `authorized_status`); TikTok advises against caching it, and the gem never caches.
- `warehouse_id` is required on every SKU inventory entry; list them with `shop.warehouses`.
- Money is a decimal string in major units (`"199.00"`); ids are strings. The gem passes both through untouched.
- `media.upload_image` takes `use_case:` as a form field (TikTok documents it as optional); the response `uri` goes
  into product payloads.

### Response

```ruby
res = shop.products.unlist(ids)
res.data         # the payload with TikTok's envelope removed, frozen, never coerced
res.request_id   # TikTok's request_id
res.warnings     # ["..."] from data.warnings[].message
res.item_errors  # [#<data ItemError id="1729382588639839583", code="12052048", message="You can't edit ...">]
res.http_status; res.endpoint; res.raw
```

TikTok's batch endpoints fail per item inside a successful response (`code` 0, `data.errors[]`); those failures are
`item_errors`, never exceptions.

## Pagination

```ruby
pager = shop.products.list(status: "ACTIVATE", page_size: 50)
pager.each { |product| ... }            # every item, fetching pages lazily
pager.lazy.first(10)                    # only as many requests as needed
pager.each_page { |page| page.items; page.next_cursor; page.total }
page = pager.first_page
shop.products.list(status: "ACTIVATE", cursor: page.next_cursor)  # resume later
```

`next_cursor` is TikTok's opaque `next_page_token` (it may hold `+` and `/`): store it, pass it back, never parse
it. `page_size:` defaults to TikTok's maximum (100) and raises `ArgumentError` above it. Product search stops at
10,000 results; the pager then raises `PaginationLimitError`, and splitting the search by `update_time_ge` /
`update_time_le` windows is up to you.

## Errors and retries

Every failure raises a subclass of `TiktokShopRbApi::Error`; see [CONTRACT.md §8](CONTRACT.md) for the tree. TikTok
signals errors with a non-zero `code`, whatever the HTTP status. The class comes from TikTok's `(code, message)` pair,
because TikTok reuses `36009004` for about a dozen failures (a bad signature, a stale timestamp, an invalid token, an
unexpected `shop_cipher`, ...). A code the table does not know raises plain `ApiError`.

```ruby
begin
  shop.products.update(id, payload)
rescue TiktokShopRbApi::AuthenticationError
  # 105002: refresh (once, persisting both tokens) or ask the seller to re-authorize
rescue TiktokShopRbApi::PermissionError => e
  # 105005 missing scope, 36009033 IP not allow-listed: a human has to act
rescue TiktokShopRbApi::ApiError => e
  e.code; e.message; e.request_id; e.retryable?
end
```

Retries are off by default. Opt in with a policy; it follows TikTok's published protocol
(`max(retry_after, min(base * 2**n + jitter, cap))`), retries only `retryable?` errors (rate limits, and server or
network errors on idempotent calls) and re-signs every attempt:

```ruby
TiktokShopRbApi::Client.new(..., retry_policy: TiktokShopRbApi::RetryPolicy.new(max_retries: 5))
```

An HTTP 503 is a `ServerError`, not a rate limit. A create is idempotent, and so retryable, only when you pass
`idempotency_key:`; `products.update`, `products.replace` and `media.upload_image` never are. Token calls are never
retried: the auth code is single use.

## Webhooks

TikTok signs each webhook with `HMAC-SHA256(app_secret, app_key + raw_body)`, lower-case hex, in the `Authorization`
header (no `Bearer` prefix).

```ruby
event = client.verify_webhook(raw_body: request.raw_post, signature: request.headers["Authorization"])
event.type         # :authorization_expiring (type 7) | :deauthorized (type 6) | :product_status (5, 37) | :other
event.code         # the payload's numeric type as a String: "7", "6", "1", ...
event.shop_id; event.occurred_at; event.data
```

- Verify the raw body as received; never re-serialize parsed JSON.
- Reply with any 2xx. TikTok retries an unacknowledged delivery at 2 minutes, 30 minutes, 3 hours and 12 hours, then
  stops; keep `event.raw["tts_notification_id"]` to drop duplicates.
- `UPCOMING_AUTHORIZATION_EXPIRATION` (type 7) arrives 30 days before the authorization ends and daily after that;
  `data["expiration_time"]` is the deadline.
- `TiktokShopRbApi::Webhook.verify(...)` and `.parse(raw_body)` are the pure functions underneath. Subscribing to
  topics is out of this release; use `shop.request(:put, "/event/202309/webhooks", body: {...})`.

## Raw requests

Any endpoint the gem does not wrap, signed, parsed and classified the same way:

```ruby
shop.request(:post, "/product/202309/products/recover", body: { product_ids: [id] }, idempotent: true)
shop.request(:get, "/authorization/202309/shops", query: { shop_cipher: nil })  # an endpoint that refuses the cipher
client.request(:get, "/some/app/level/path")                                     # app-signed, no token
```

## Testing

```sh
bundle install
bundle exec rake          # unit tests, the conformance suite, RuboCop and conformance:verify
```

The default suite makes no network call. It runs every request through `FakeTransport` against fixtures in
`test/fixtures/`; each fixture names its source in `_source` (the documentation page and pull date, or
"recorded live <date>"). The official signing vector (`b596b73e…`) and webhook vector (`5dec0f11…`) are tests.

The opt-in live tests only read, never refresh a token and never write:

```sh
TIKTOK_SHOP_LIVE_APP_KEY=... TIKTOK_SHOP_LIVE_APP_SECRET=... \
TIKTOK_SHOP_LIVE_ACCESS_TOKEN=... TIKTOK_SHOP_LIVE_SHOP_CIPHER=... bundle exec rake test:live
```

TikTok has no sandbox host: use a Partner Center development shop with the same variables. Add
`TIKTOK_SHOP_RECORD=1` to replace the documentation fixtures with redacted recordings of successful responses. Error
responses and order responses are never recorded, so buyers' personal data never reaches a fixture; personal-data keys
(email, phone, name, nickname, address) are redacted wherever else they appear.

## Contract version

`TiktokShopRbApi::CONTRACT_VERSION` is `"2"`. The shared interface lives in [CONTRACT.md](CONTRACT.md), which is
identical in all three sibling gems; `test/conformance/` enforces it and `rake conformance:verify` proves the shared
files match `test/conformance/MANIFEST`. Change the contract only in all three gems at once, as CONTRACT.md describes.
