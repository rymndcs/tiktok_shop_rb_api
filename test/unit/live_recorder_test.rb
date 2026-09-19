# frozen_string_literal: true

# One recording, several properties of the written fixture.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"
require_relative "../live/live_helper"
require "tmpdir"

# The live recorder, offline: it must write a redacted fixture that names its source, under the name of the
# documentation fixture it replaces.
class LiveRecorderTest < Minitest::Test
  def test_records_a_redacted_fixture_naming_its_source
    Dir.mktmpdir do |dir|
      body = { "code" => 0, "request_id" => "r", "data" => { "access_token" => "tok-123", "note" => "k=sekret" } }
      inner = FakeTransport.new(FakeTransport.json(body))
      recorder = LiveHelper::Recorder.new(inner, secrets: %w[sekret], label: "TIKTOK_SHOP_LIVE", dir:)
      recorder.call(method: :get, url: "https://h.test/product/202309/categories/600001/rules?sign=abc&app_key=k",
                    headers: {}, body: nil)
      path = File.join(dir, "product_202309_categories_id_rules.json")
      fixture = JSON.parse(File.read(path))

      assert_match(/\Arecorded live \d{4}-\d{2}-\d{2} \(TIKTOK_SHOP_LIVE\), redacted\z/, fixture["_source"]["origin"])
      assert_equal "/product/202309/categories/600001/rules", fixture["_source"]["url"]
      assert_equal "[REDACTED]", fixture["body"]["data"]["access_token"]
      assert_equal "k=[REDACTED]", fixture["body"]["data"]["note"]
      refute_includes File.read(path), "abc"
    end
  end

  def test_recorded_names_match_the_documentation_fixtures
    {
      "/product/202309/products/1729592969712207008" => "product_202309_products_id",
      "/product/202309/products/1729592969712207008/inventory/update" => "product_202309_products_id_inventory_update",
      "/api/v2/token/get" => "api_v2_token_get",
      "/authorization/202309/shops" => "authorization_202309_shops"
    }.each do |path, name|
      assert_equal name, LiveHelper.fixture_name(path)
      assert_path_exists File.join(Fixtures::DIR, "#{name}.json"), name
    end
  end

  def test_error_responses_never_replace_a_fixture
    Dir.mktmpdir do |dir|
      refusal = { "code" => 36_009_033, "message" => "Access denied.", "request_id" => "r" }
      inner = FakeTransport.new(FakeTransport.json(refusal), FakeTransport.json({ "code" => 0 }, status: 500))
      recorder = LiveHelper::Recorder.new(inner, secrets: [], label: "TIKTOK_SHOP_LIVE", dir:)
      2.times { recorder.call(method: :get, url: "https://h.test/logistics/202309/warehouses", headers: {}, body: nil) }

      assert_empty Dir.children(dir)
    end
  end

  def test_order_responses_are_never_recorded
    Dir.mktmpdir do |dir|
      order = { "code" => 0, "request_id" => "r",
                "data" => { "orders" => [{ "id" => "576461413038785752", "buyer_email" => "b@example.com" }] } }
      inner = FakeTransport.new(FakeTransport.json(order), FakeTransport.json(order))
      recorder = LiveHelper::Recorder.new(inner, secrets: [], label: "TIKTOK_SHOP_LIVE", dir:)
      recorder.call(method: :post, url: "https://h.test/order/202309/orders/search?page_size=10", headers: {},
                    body: "{}")
      recorder.call(method: :get, url: "https://h.test/order/202507/orders?ids=576461413038785752", headers: {},
                    body: nil)

      assert_empty Dir.children(dir)
    end
  end

  def test_personal_data_keys_are_redacted_outside_orders
    Dir.mktmpdir do |dir|
      address = { "full_address" => "1 Main St", "postal_code" => "10001" }
      data = { "id" => "7", "Buyer_Email" => "b@example.com", "PHONE_NUMBER" => 5_551_234, "name" => "Ana Cruz",
               "buyer_nickname" => "ana", "recipient_address" => address, "Buyer_Address" => address,
               "note" => nil, "status" => "ACTIVE" }
      inner = FakeTransport.new(FakeTransport.json({ "code" => 0, "request_id" => "r", "data" => data }))
      recorder = LiveHelper::Recorder.new(inner, secrets: [], label: "TIKTOK_SHOP_LIVE", dir:)
      recorder.call(method: :get, url: "https://h.test/logistics/202309/warehouses", headers: {}, body: nil)
      text = File.read(File.join(dir, "logistics_202309_warehouses.json"))
      recorded = JSON.parse(text)["body"]["data"]

      %w[Buyer_Email PHONE_NUMBER name buyer_nickname recipient_address Buyer_Address].each do |key|
        assert_equal "[REDACTED]", recorded[key], key
      end
      assert_equal({ "id" => "7", "note" => nil, "status" => "ACTIVE" }, recorded.slice("id", "note", "status"))
      ["b@example.com", "Ana Cruz", "1 Main St", "5551234"].each { |value| refute_includes text, value }
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
