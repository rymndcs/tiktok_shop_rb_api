# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

# The method, path, query and body each wrapped endpoint sends, per its official reference page
# (https://partner.tiktokshop.com/docv2/page/<slug>, pulled 2026-09-20).
class ResourcesTest < Minitest::Test
  include UnitHelper

  PID = A::PRODUCT_ID

  def assert_get(request, path, query, cipher: true)
    assert_equal :get, request.http_method
    assert_equal path, request.path
    assert_nil request.body
    query.each { |key, value| assert_equal value, request.query[key], key }
    if cipher
      assert_equal A::SHOP_CIPHER, request.query["shop_cipher"]
    else
      refute request.query.key?("shop_cipher"), "#{path} takes no shop_cipher"
    end
  end

  def assert_post(request, path, body, query: {}, method: :post)
    assert_equal method, request.http_method
    assert_equal path, request.path
    assert_equal "application/json", request.header("Content-Type")
    assert_equal body, request.json
    assert_equal A::SHOP_CIPHER, request.query["shop_cipher"]
    query.each { |key, value| assert_equal value, request.query[key], key }
  end

  def test_info_picks_the_shop_by_cipher_without_sending_the_cipher
    shop, transport = shop_with(A.read_success_response)
    info = shop.info

    assert_get(transport.requests.first, "/authorization/202309/shops", {}, cipher: false)
    assert_equal "7000714532876273420", info.data["id"]
    assert_equal 1, info.raw.dig("data", "shops").size
    client = A.build_client(transport: FakeTransport.new(A.read_success_response))

    assert_empty client.shop(access_token: "t", shop_cipher: "ROW_other").info.data
  end

  def test_limits_and_warehouses
    assert_get(request_for(&:limits), "/product/202312/prerequisites", {})
    assert_get(request_for(&:warehouses), "/logistics/202309/warehouses", {})
  end

  def test_categories
    assert_get(request_for { |s| s.categories.list(category_version: "v2", locale: "en-PH") },
               "/product/202309/categories", { "category_version" => "v2", "locale" => "en-PH" })
    assert_get(request_for { |s| s.categories.attributes(600_001, locale: "en-PH") },
               "/product/202309/categories/600001/attributes", { "locale" => "en-PH" })
    assert_get(request_for { |s| s.categories.rules("600001", category_version: "v2") },
               "/product/202309/categories/600001/rules", { "category_version" => "v2" })
    assert_post(request_for { |s| s.categories.recommend(title: "Bosch H4 bulb", category_version: "v2") },
                "/product/202309/categories/recommend",
                { "product_title" => "Bosch H4 bulb", "category_version" => "v2" })
    assert_raises(ArgumentError) { request_for { |s| s.categories.attributes("../x") } }
  end

  def test_brands_query
    request = request_for { |s| s.brands.list(category_id: 600_006, is_authorized: true).first_page }

    assert_get(request, "/product/202309/brands",
               { "page_size" => "100", "category_id" => "600006", "is_authorized" => "true" })
    refute request.query.key?("page_token")
  end

  def test_products_writes
    assert_post(request_for { |s| s.products.create({ title: "T" }, idempotency_key: "k1") },
                "/product/202309/products", { "title" => "T", "idempotency_key" => "k1" })
    assert_post(request_for { |s| s.products.update(PID, { "product_attributes" => [] }) },
                "/product/202509/products/#{PID}/partial_edit", { "product_attributes" => [] })
    assert_post(request_for { |s| s.products.replace(PID, { title: "T", skus: [] }) },
                "/product/202509/products/#{PID}", { "title" => "T", "skus" => [] }, method: :put)
    assert_post(request_for { |s| s.products.check_listing({ title: "T" }) },
                "/product/202309/products/listing_check", { "title" => "T" })
  end

  def test_products_reads
    assert_get(request_for { |s| s.products.get(PID, return_under_review_version: true) },
               "/product/202309/products/#{PID}", { "return_under_review_version" => "true" })
    assert_get(request_for { |s| s.products.diagnoses([PID, 1]) }, "/product/202405/products/diagnoses",
               { "product_ids" => "#{PID},1" })
    assert_post(request_for { |s| s.products.list(page_size: 50, status: "ACTIVATE").first_page },
                "/product/202502/products/search", { "status" => "ACTIVATE" }, query: { "page_size" => "50" })
  end

  def test_find_by_seller_sku
    shop, transport = shop_with(Fixtures.response("product_202502_products_search"))

    assert_equal [PID], shop.products.find_by_seller_sku("Color-Red-XM01")
    assert_post(transport.requests.first, "/product/202502/products/search", { "seller_skus" => ["Color-Red-XM01"] },
                query: { "page_size" => "100" })
  end

  def test_unlist_and_relist
    assert_post(request_for { |s| s.products.unlist([PID, 42]) }, "/product/202309/products/deactivate",
                { "product_ids" => [PID, "42"] })
    assert_post(request_for { |s| s.products.relist([PID]) }, "/product/202309/products/activate",
                { "product_ids" => [PID] })
    assert_equal 20, TiktokShopRbApi::Products::UNLIST_BATCH_MAX
    assert_equal 20, TiktokShopRbApi::Products::RELIST_BATCH_MAX
    shop, transport = shop_with

    assert_raises(ArgumentError) { shop.products.diagnoses((1..201).to_a) }
    assert_empty transport.requests
  end

  def test_stock_and_prices
    assert_post(request_for { |s| s.stock.get(PID) }, "/product/202309/inventory/search", { "product_ids" => [PID] })
    assert_post(request_for { |s| s.stock.update(PID, A.sku_stock) },
                "/product/202309/products/#{PID}/inventory/update", { "skus" => A.sku_stock })
    assert_post(request_for { |s| s.prices.update(PID, A.sku_prices) },
                "/product/202309/products/#{PID}/prices/update", { "skus" => A.sku_prices })
    shop, = shop_with

    assert_raises(ArgumentError) { shop.stock.update(PID, []) }
  end

  def test_orders_put_sort_params_in_the_query_and_filters_in_the_body
    request = request_for do |s|
      s.orders.list(page_size: 20, sort_field: "create_time", sort_order: "ASC", order_status: "UNPAID",
                    update_time_ge: 1_700_000_000).first_page
    end

    assert_post(request, "/order/202309/orders/search",
                { "order_status" => "UNPAID", "update_time_ge" => 1_700_000_000 },
                query: { "page_size" => "20", "sort_field" => "create_time", "sort_order" => "ASC" })
    assert_get(request_for { |s| s.orders.get("576461413038785752") }, "/order/202507/orders",
               { "ids" => "576461413038785752" })
  end

  def test_upload_image
    request = request_for do |s|
      s.media.upload_image(StringIO.new("PNG".b), filename: "bulb.png", use_case: "MAIN_IMAGE")
    end

    assert_equal "/product/202309/images/upload", request.path
    assert_includes request.body, "name=\"data\"; filename=\"bulb.png\"\r\nContent-Type: image/png"
    assert_includes request.body, "name=\"use_case\"\r\n\r\nMAIN_IMAGE"
    assert_equal A::ACCESS_TOKEN, request.header("x-tts-access-token")
    refute request.query.key?("shop_cipher")
  end

  def test_the_search_cap_raises_pagination_limit_error
    shop, = shop_with(A.error("12052180", "The total number of search results can not exceed 10000."))

    assert_raises(TiktokShopRbApi::PaginationLimitError) { shop.products.list.to_a }
  end

  def test_shop_request_sends_the_cipher_unless_told_not_to
    assert_get(request_for { |s| s.request(:get, "/product/202309/brands", query: { page_size: 1 }) },
               "/product/202309/brands", { "page_size" => "1" })
    assert_get(request_for { |s| s.request(:get, "/authorization/202309/shops", query: { shop_cipher: nil }) },
               "/authorization/202309/shops", {}, cipher: false)
    request = request_for do |s|
      s.request(:post, "/product/202309/products/recover", body: { product_ids: [PID] }, idempotent: true)
    end

    assert_post(request, "/product/202309/products/recover", { "product_ids" => [PID] })
  end

  def test_client_request_is_app_signed_without_a_token
    client, transport = client_with(ok)
    client.request(:get, "/seller/202309/shops")
    request = transport.requests.first

    assert_nil request.header("x-tts-access-token")
    refute request.query.key?("shop_cipher")
    assert_equal A.expected_signature(request), request.query["sign"]
  end
end
# rubocop:enable Minitest/MultipleAssertions
