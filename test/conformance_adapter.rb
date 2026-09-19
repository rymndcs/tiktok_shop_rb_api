# frozen_string_literal: true

require "openssl"
require "stringio"

# The TikTok Shop half of the conformance suite: everything platform-specific the shared tests in test/conformance/
# need. See test/conformance/helper.rb for the interface.
module ConformanceAdapter
  DOC = "https://partner.tiktokshop.com/docv2/page"
  # The app key, secret and timestamp of the official signing example in DOC/sign-your-api-request. The official
  # webhook example's credentials ("abcdef" / "123") are too short to stand in for a secret in the redaction tests,
  # which look for it as a substring of every log line, so that vector is checked in test/unit/webhook_test.rb.
  APP_KEY = "29a39d"
  APP_SECRET = "e59af819cc"
  FIXED_TIME = Time.at(1_623_812_664).utc
  # The access token of the same example's curl command, and the auth code and refresh token of
  # DOC/authorization-overview-202407.
  ACCESS_TOKEN = "TTP_pwSm2AAAAABmmtFz1xlyKMnwg74T2GJ5s0uQbS8jPjb_GkdFVCxPqzQXSyuyfXdQa0AqyDsea2tYFNVf4X" \
                 "eqgZHFfPyv0Vs659QqyLYfsGzanZ5XZAin3_ZkcIxxS0_In6u6XDeU96k"
  AUTH_CODE = "TTP_FeBoANmHP3yqdoUI9fZOCw"
  REFRESH_TOKEN = "TTP_C2XWDN63ON-FOHJSMR0WSG"
  # The cipher of the shop in the Get Authorized Shops response sample, so shop.info finds it.
  SHOP_CIPHER = "GCP_XF90igAAAABh00qsWgtvOiGFNqyubMt3"
  # Made up: TikTok publishes no sample service id.
  SERVICE_ID = "7310000000000000001"
  PRODUCT_ID = "1729592969712207008"
  # The page_token of the Get Order List documentation sample: it holds "/" and "+".
  ORDER_PAGE_TOKEN = "6AsPQsUMvH3RkchNUPPh22NROHkE0D8pmq/N5M1kHYcZmtRyv9aVrNv65W7Q6tFA+7D1ud64MPNz5OaT"

  UNSIGNED = %w[sign access_token].freeze

  module_function

  def gem_module
    TiktokShopRbApi
  end

  def gem_name
    "tiktok_shop_rb_api"
  end

  def fixed_time
    FIXED_TIME
  end

  def build_client(transport:, clock: nil, logger: nil, retry_policy: nil, **)
    TiktokShopRbApi::Client.new(app_key: APP_KEY, app_secret: APP_SECRET, transport:, clock: clock || -> { FIXED_TIME },
                                logger:, retry_policy: retry_policy || TiktokShopRbApi::RetryPolicy.none,
                                service_id: SERVICE_ID, **)
  end

  def locator
    { shop_cipher: SHOP_CIPHER }
  end

  def build_shop(client)
    client.shop(access_token: ACCESS_TOKEN, **locator)
  end

  def secrets
    tokens = %w[api_v2_token_get api_v2_token_refresh].flat_map do |name|
      Fixtures.body(name)["data"].values_at("access_token", "refresh_token")
    end
    [APP_SECRET, ACCESS_TOKEN, AUTH_CODE, REFRESH_TOKEN, *tokens]
  end

  def authorize(client)
    client.auth.authorize_url(state: "csrf-token")
  end

  def read_call
    ->(_client, shop) { shop.info }
  end

  def read_success_response
    Fixtures.response("authorization_202309_shops")
  end

  def error(code, message, status: 200, request_id: "202203070749000101890810281E8C70B7")
    FakeTransport.json({ "code" => Integer(code), "message" => message, "request_id" => request_id, "data" => nil },
                       status:)
  end

  def server_error_response
    error("36009003", "Internal error. Please try again. If the issue persists after multiple attempts, please " \
                      "contact platform support.")
  end

  def rate_limit_response
    error("36009002", "Too many requests. You've made too many requests in a short period of time.", status: 429)
  end

  def unmapped_error_response
    error("99999999", "A code the error table has never seen.")
  end

  # Verbatim pairs from DOC/common-errors and the endpoint Error Code tables.
  def error_samples
    [
      ["AuthenticationError", "105002", "Expired credentials. The `access_token` or `x-tts-access-token` header has " \
                                        "expired.", false],
      ["AuthenticationError", "36009004", "Invalid credentials. The `x-tts-access-token` header is invalid.", false],
      ["AuthenticationError", "101000", "Invalid query or header. The `category_asset_cipher` query parameter or " \
                                        "`x-tts-access-token` header is invalid.", false],
      ["AppCredentialsError", "36009004", "Invalid credentials. Invalid `app_key` query parameter.", false],
      ["PermissionError", "105005", "Access denied. The app is not authorized to access the endpoint because the " \
                                    "access scopes granted for the app or the access token do not contain the " \
                                    "required access scope for the endpoint.", false],
      ["PermissionError", "36009033", "Access denied. Your IP address is not in the IP allow list configured for " \
                                      "this app.", false],
      ["SignatureError", "106001", "Invalid credentials. The `sign` query parameter is invalid.", false],
      ["SignatureError", "36009004", "Invalid timestamp. The value of the `timestamp` query parameter must not " \
                                     "exceed the current time by more than 30 seconds.", false],
      ["RateLimitError", "36009002", "Too many requests. You've made too many requests in a short period of time.",
       true],
      ["ServerError", "36009003", "Internal error. Please try again. If the issue persists after multiple attempts, " \
                                  "please contact platform support.", true],
      ["RequestError", "106013", "Missing identifier. The `shop_cipher` query parameter is required to identify " \
                                 "the target shop.", false],
      ["RequestError", "36009004", "Unexpected identifier. The `shop_cipher` query parameter is not required for " \
                                   "this request.", false],
      ["BusinessError", "12052024", "Category is not final category", false]
    ].map do |class_name, code, message, retryable|
      { class_name:, response: error(code, message), code:, request_id: "202203070749000101890810281E8C70B7",
        retryable:, retry_after: nil }
    end
  end

  def error_classes_without_platform_code
    %w[QuotaExceededError ConcurrencyError]
  end

  def product_payload
    { "title" => "Bosch H4 halogen headlight bulb 12V 60/55W", "description" => "<p>Halogen headlight bulb.</p>",
      "category_id" => "600001", "category_version" => "v2", "main_images" => [{ "uri" => "tos-maliva-i-o3syd03w52" }],
      "skus" => [{ "seller_sku" => "OT405", "price" => { "amount" => "199.00", "currency" => "PHP" },
                   "inventory" => [{ "warehouse_id" => "7068517275539719942", "quantity" => 10 }] }] }
  end

  def shared_calls
    image = -> { StringIO.new("\xFF\xD8\xFFjpeg".b) }
    {
      "auth.exchange_code" => [->(c, _) { c.auth.exchange_code(code: AUTH_CODE) }, "api_v2_token_get"],
      "auth.refresh" => [->(c, _) { c.auth.refresh(refresh_token: REFRESH_TOKEN) }, "api_v2_token_refresh"],
      "client.authorized_shops" => [->(c, _) { c.authorized_shops(access_token: ACCESS_TOKEN) },
                                    "authorization_202309_shops"],
      "client.request" => [->(c, _) { c.request(:get, "/authorization/202309/shops") }, "authorization_202309_shops"],
      "shop.info" => [->(_, s) { s.info }, "authorization_202309_shops"],
      "shop.limits" => [->(_, s) { s.limits }, "product_202312_prerequisites"],
      "shop.request" => [->(_, s) { s.request(:get, "/product/202309/categories/600001/rules") },
                         "product_202309_categories_id_rules"],
      "categories.list" => [->(_, s) { s.categories.list(category_version: "v2", locale: "en-PH") },
                            "product_202309_categories"],
      "categories.attributes" => [->(_, s) { s.categories.attributes(600_001, category_version: "v2") },
                                  "product_202309_categories_id_attributes"],
      "categories.recommend" => [->(_, s) { s.categories.recommend(title: "Bosch H4 halogen headlight bulb 12V") },
                                 "product_202309_categories_recommend"],
      "brands.list" => [->(_, s) { s.brands.list(category_id: 600_006) }, "product_202309_brands"],
      "media.upload_image" => [lambda { |_, s|
        s.media.upload_image(image.call, filename: "a.jpg", use_case: "MAIN_IMAGE")
      }, "product_202309_images_upload"],
      "products.create" => [->(_, s) { s.products.create(product_payload) }, "product_202309_products"],
      "products.get" => [->(_, s) { s.products.get(PRODUCT_ID) }, "product_202309_products_id"],
      "products.update" => [->(_, s) { s.products.update(PRODUCT_ID, { "brand_id" => "7082427311584347905" }) },
                            "product_202509_products_id_partial_edit"],
      "products.list" => [->(_, s) { s.products.list(status: "ACTIVATE") }, "product_202502_products_search"],
      "products.find_by_seller_sku" => [->(_, s) { s.products.find_by_seller_sku("Color-Red-XM01") },
                                        "product_202502_products_search"],
      "products.unlist" => [->(_, s) { s.products.unlist([PRODUCT_ID]) }, "product_202309_products_deactivate"],
      "products.relist" => [->(_, s) { s.products.relist([PRODUCT_ID]) }, "product_202309_products_activate"],
      "stock.get" => [->(_, s) { s.stock.get(PRODUCT_ID) }, "product_202309_inventory_search"],
      "stock.update" => [->(_, s) { s.stock.update(PRODUCT_ID, sku_stock) },
                         "product_202309_products_id_inventory_update"],
      "prices.update" => [->(_, s) { s.prices.update(PRODUCT_ID, sku_prices) },
                          "product_202309_products_id_prices_update"],
      "orders.list" => [->(_, s) { s.orders.list(order_status: "UNPAID") }, "order_202309_orders_search"],
      "orders.get" => [->(_, s) { s.orders.get("576461413038785752") }, "order_202507_orders"]
    }.map { |name, (call, fixture)| { name:, call:, response: Fixtures.response(fixture) } }
  end

  def sku_stock
    [{ "id" => "1729592969712207013", "inventory" => [{ "warehouse_id" => "7068517275539719942", "quantity" => 5 }] }]
  end

  def sku_prices
    [{ "id" => "1729592969712207013", "price" => { "amount" => "189.00", "currency" => "PHP" } }]
  end

  def write_calls
    names = Conformance::CONTRACT[:write_idempotency].keys
    shared_calls.select { |c| names.include?(c[:name]) }
                .map { |c| c.merge(call: ->(shop) { c[:call].call(nil, shop) }) }
  end

  def batch_calls
    [
      { name: "products.unlist", call: ->(shop, ids) { shop.products.unlist(ids) } },
      { name: "products.relist", call: ->(shop, ids) { shop.products.relist(ids) } }
    ]
  end

  def envelope_samples
    deactivate = Fixtures.body("product_202309_products_deactivate")
    create = Fixtures.body("product_202309_products")
    shops = Fixtures.body("authorization_202309_shops")
    inventory = Fixtures.body("product_202309_products_id_inventory_update")
    check = Fixtures.body("product_202309_products_listing_check")
    [
      { name: "per-item failures inside code 0", call: ->(_, s) { s.products.unlist([PRODUCT_ID]) },
        response: Fixtures.response("product_202309_products_deactivate"),
        expect: { data: deactivate["data"], request_id: deactivate["request_id"], warnings: [],
                  item_errors: [["1729382588639839583", "12052048", "You can't edit other sellers' products"]] } },
      { name: "a create that dropped a field", call: ->(_, s) { s.products.create(product_payload) },
        response: Fixtures.response("product_202309_products"),
        expect: { data: create["data"], request_id: create["request_id"], item_errors: [],
                  warnings: [create["data"]["warnings"][0]["message"]] } },
      { name: "per-SKU failures keyed by sku_id", call: ->(_, s) { s.stock.update(PRODUCT_ID, sku_stock) },
        response: Fixtures.response("product_202309_products_id_inventory_update"),
        expect: { data: inventory["data"], request_id: inventory["request_id"], warnings: [],
                  item_errors: [["1729592969712207013", "12052990", "Check failed"]] } },
      { name: "an empty data object", call: ->(_, s) { s.prices.update(PRODUCT_ID, sku_prices) },
        response: Fixtures.response("product_202309_products_id_prices_update"),
        expect: { data: {}, request_id: "202203070749000101890810281E8C70B7", warnings: [], item_errors: [] } },
      { name: "a single warnings object", call: ->(_, s) { s.products.check_listing(product_payload) },
        response: Fixtures.response("product_202309_products_listing_check"),
        expect: { data: check["data"], request_id: check["request_id"], item_errors: [],
                  warnings: [check["data"]["warnings"]["message"]] } },
      { name: "info picks this shop's element", call: ->(_, s) { s.info },
        response: Fixtures.response("authorization_202309_shops"),
        expect: { data: shops["data"]["shops"][0], request_id: shops["request_id"], warnings: [], item_errors: [] } }
    ]
  end

  def uncoerced_sample
    { call: ->(_, s) { s.products.create(product_payload) }, response: Fixtures.response("product_202309_products"),
      checks: [[%w[product_id], PRODUCT_ID], [["skus", 0, "fees", 0, "amount"], "1.01"],
               [["skus", 0, "sales_attributes", 0, "value_id"], "1729592969712207123"]] }
  end

  # One page of a cursor-paged TikTok response built from a fixture. token: :absent drops next_page_token.
  def page_of(fixture, key, items, token)
    body = Fixtures.body(fixture)
    data = body["data"].merge(key => items)
    token == :absent ? data.delete("next_page_token") : data["next_page_token"] = token
    FakeTransport.json(body.merge("data" => data))
  end

  def cursor_pager(name, fixture, key, call, tokens: %w[cGFnZTI= cGFnZTM=], cap: nil)
    item = ->(n) { { "id" => n.to_s } }
    { name:, call:, page_size_key: :page_size, max_page_size: 100, cap:,
      pages: [page_of(fixture, key, [item[1], item[2]], tokens[0]), page_of(fixture, key, [item[3]], tokens[1]),
              page_of(fixture, key, [item[4]], "")],
      final_variants: [page_of(fixture, key, [item[3]], ""), page_of(fixture, key, [item[3]], :absent)] }
  end

  def pagers
    search = "product_202502_products_search"
    capped = { responses: [page_of(search, "products", [{ "id" => "1" }], "cGFnZTI="),
                           error("12052180", "The total number of search results can not exceed 10000.")] }
    [cursor_pager("brands.list", "product_202309_brands", "brands", ->(_, s, **o) { s.brands.list(**o) }),
     cursor_pager("products.list", search, "products", ->(_, s, **o) { s.products.list(status: "ACTIVATE", **o) },
                  cap: capped),
     cursor_pager("orders.list", "order_202309_orders_search", "orders",
                  ->(_, s, **o) { s.orders.list(order_status: "UNPAID", **o) },
                  tokens: [ORDER_PAGE_TOKEN, "#{ORDER_PAGE_TOKEN}+/2"])]
  end

  # The same request, whatever its timestamp and signature.
  def request_identity(request)
    [request.http_method, request.path, request.query.except("sign", "timestamp"), request.body]
  end

  def signer
    TiktokShopRbApi.const_get(:Signer)
  end

  # The documented wrapped HMAC, computed here with OpenSSL rather than through the gem's Signer.
  def hmac(base_string)
    OpenSSL::HMAC.hexdigest("SHA256", APP_SECRET, "#{APP_SECRET}#{base_string}#{APP_SECRET}".b)
  end

  def signing_vectors
    webhook_body = '{"address":"https://partner.tiktokshop.com","event_type":"PACKAGE_UPDATE"}'
    order_body = '{"order_status":"UNPAID"}'
    [
      { name: "official Get Authorized Shops example (DOC/sign-your-api-request)",
        expected_base_string: "/authorization/202309/shopsapp_key29a39dtimestamp1623812664",
        expected_signature: "b596b73e0cc6de07ac26f036364178ab16b0a907af13d43f0a0cd2345f582dc8",
        parts: { path: "/authorization/202309/shops", query: { "timestamp" => "1623812664", "app_key" => "29a39d" } } },
      # The doc prints this base string but no digest for it: the digest is self-generated with OpenSSL over the
      # documented string and the example's secret. The base string is the official part.
      { name: "official body-bearing base string, Update Shop Webhook (self-generated digest)",
        expected_base_string: "/event/202309/webhooksapp_key68xu9ks5p4i8shop_cipherROW_xkMbgAAAeVAQra0eZWebFQq5aIKt" \
                              "timestamp1696909648#{webhook_body}",
        expected_signature: hmac("/event/202309/webhooksapp_key68xu9ks5p4i8shop_cipherROW_xkMbgAAAeVAQra0eZWebFQq5a" \
                                 "IKttimestamp1696909648#{webhook_body}"),
        parts: { path: "/event/202309/webhooks", body: webhook_body,
                 query: { "timestamp" => "1696909648", "shop_cipher" => "ROW_xkMbgAAAeVAQra0eZWebFQq5aIKt",
                          "app_key" => "68xu9ks5p4i8" } } },
      # Self-generated: a page_token holding "+" and "/" is signed decoded, and access_token and sign are ignored.
      { name: "page_token with + and / (self-generated)",
        expected_base_string: "/order/202309/orders/searchapp_key29a39dpage_size100page_token#{ORDER_PAGE_TOKEN}" \
                              "shop_cipher#{SHOP_CIPHER}timestamp1623812664#{order_body}",
        expected_signature: hmac("/order/202309/orders/searchapp_key29a39dpage_size100page_token#{ORDER_PAGE_TOKEN}" \
                                 "shop_cipher#{SHOP_CIPHER}timestamp1623812664#{order_body}"),
        parts: { path: "/order/202309/orders/search", body: order_body,
                 query: { "shop_cipher" => SHOP_CIPHER, "page_token" => ORDER_PAGE_TOKEN, "sign" => "x",
                          "access_token" => "y", "page_size" => "100", "timestamp" => "1623812664",
                          "app_key" => "29a39d" } } }
    ].map do |v|
      string = signer.base_string(**v[:parts])
      v.merge(base_string: string, signature: signer.sign(APP_SECRET, string))
    end
  end

  def signed_calls
    names = %w[shop.info client.authorized_shops client.request products.create media.upload_image orders.list
               stock.update products.get]
    shared_calls.select { |c| names.include?(c[:name]) }.map do |c|
      c.merge(token: c[:name] == "client.request" ? nil : ACCESS_TOKEN)
    end
  end

  def signature_parts(request)
    query = request.query
    { signature: query["sign"], timestamp: query["timestamp"] && Integer(query["timestamp"]),
      access_token: request.header("x-tts-access-token") }
  end

  def multipart?(request)
    request.header("Content-Type").to_s.split(";").first.to_s.strip.casecmp?("multipart/form-data")
  end

  # Recomputed from the request as sent, following DOC/sign-your-api-request directly rather than the gem's Signer.
  def expected_signature(request)
    raise "app_key missing from the query" unless request.query["app_key"] == APP_KEY

    params = request.query.except(*UNSIGNED).sort_by(&:first)
    base = "#{request.path}#{params.map { |k, v| "#{k}#{v}" }.join}".b
    base << request.body.to_s.b unless multipart?(request)
    hmac(base)
  end

  def timestamp_for(time)
    time.to_i
  end

  # TikTok signs the exact body bytes, except a multipart/form-data body.
  def signed_body(request)
    multipart?(request) ? nil : request.body.to_s
  end

  def webhook_credentials
    { app_key: APP_KEY, app_secret: APP_SECRET }
  end

  def webhook_url_required?
    false
  end

  # The official body of DOC/tts-webhooks-overview, whose official digest (app_key "abcdef", secret "123") is
  # checked in test/unit/webhook_test.rb.
  OFFICIAL_WEBHOOK_BODY = '{"type":1,"tts_notification_id":"7380066284010030890","shop_id":"7495540735365777507",' \
                          '"timestamp":1718305585,"data":{"is_on_hold_order":true,"order_id":"576653688135258178",' \
                          '"order_status":"UNPAID","update_time":1718305585}}'

  # Self-generated: HMAC-SHA256(app_secret, app_key + raw_body) computed here with OpenSSL, with this adapter's
  # credentials, over the official example body and over the documented type 7 event example (whitespace and all).
  def webhook_vectors
    expiring = webhook_parse_samples.find { |s| s[:expect][:code] == "7" }[:raw_body]
    [["official example body (self-generated digest)", OFFICIAL_WEBHOOK_BODY],
     ["type 7 example body (self-generated digest)", expiring]].map do |name, raw_body|
      { name:, url: nil, raw_body:, signature: OpenSSL::HMAC.hexdigest("SHA256", APP_SECRET, "#{APP_KEY}#{raw_body}") }
    end
  end

  # The event examples on the topic pages DOC/5-product-status-change, 6-seller-deauthorization,
  # 7-upcoming-authorization-expiration and 37-product-audit-status-change, verbatim.
  def webhook_parse_samples
    at = Time.at(1_644_412_885).utc
    [
      { raw_body: "{\n  \"type\": 7,\n  \"tts_notification_id\": \"7327112393057371910\",\n  \"shop_id\": " \
                  "\"7494049642642441621\",\n  \"timestamp\": 1644412885,\n  \"data\": {\n    \"message\": " \
                  "\"Authorization of shop_id {xxx} is expiring in {x} days. Please direct the merchant to " \
                  "re-authorize.\",\n    \"expiration_time\": \"1627587506\"\n  }\n}",
        expect: { type: :authorization_expiring, code: "7", shop_id: "7494049642642441621", occurred_at: at } },
      { raw_body: '{"type": 6, "tts_notification_id": "7327112393057371910", "shop_id": "7494049642642441621", ' \
                  '"timestamp": 1644412885, "data": {"message": "Shop_id {xxx} is deauthorized from your APP by ' \
                  'merchant."}}',
        expect: { type: :deauthorized, code: "6", shop_id: "7494049642642441621", occurred_at: at } },
      { raw_body: '{"type": 5, "tts_notification_id": "7327112393057371910", "shop_id": "7494049642642441621", ' \
                  '"timestamp": 1644412885, "data": {"product_id": 576486316948490000, "status": ' \
                  '"PRODUCT_FIRST_PASS_REVIEW", "suspended_reason": "", "update_time": 1644412885}}',
        expect: { type: :product_status, code: "5", shop_id: "7494049642642441621", occurred_at: at } },
      { raw_body: '{"type": 37, "shop_id": "7494049642642441621", "tts_notification_id" : "7327112393057371910", ' \
                  '"timestamp": 1644412885, "data": {"product_id": 789078671231, "audit": {"status": ' \
                  '"PRE_APPROVED", "pre_approved_reason": "KYC_PENDING"}, "update_time": 1644412885}}',
        expect: { type: :product_status, code: "37", shop_id: "7494049642642441621", occurred_at: at } },
      { raw_body: '{"type":1,"tts_notification_id":"7380066284010030890","shop_id":"7495540735365777507",' \
                  '"timestamp":1718305585,"data":{"order_id":"576653688135258178","order_status":"UNPAID"}}',
        expect: { type: :other, code: "1", shop_id: "7495540735365777507", occurred_at: Time.at(1_718_305_585).utc } }
    ]
  end

  def token_samples
    %w[api_v2_token_get api_v2_token_refresh].zip(
      [->(c) { c.auth.exchange_code(code: AUTH_CODE) }, ->(c) { c.auth.refresh(refresh_token: REFRESH_TOKEN) }]
    ).map do |fixture, call|
      data = Fixtures.body(fixture)["data"]
      { name: fixture, call:, response: Fixtures.response(fixture),
        expect: { access_token: data["access_token"], refresh_token: data["refresh_token"],
                  access_expires_in: data["access_token_expire_in"] - FIXED_TIME.to_i,
                  refresh_expires_in: data["refresh_token_expire_in"] - FIXED_TIME.to_i, shop_ids: [] } }
    end
  end

  def extension_files
    []
  end
end
