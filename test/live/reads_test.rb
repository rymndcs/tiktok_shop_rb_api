# frozen_string_literal: true

require_relative "live_helper"

# The phase-0 read checks from the TikTok plan (section 9) that need a real app and shop: our signature, egress IP
# and header-borne token are accepted, and the read endpoints answer in the documented shapes. With
# TIKTOK_SHOP_RECORD=1 each response except the orders' replaces its documentation fixture.
class LiveReadsTest < Minitest::Test
  include LiveHelper::Gate

  def shop
    @shop ||= LiveHelper.shop
  end

  def test_authorized_shops_include_this_shop
    shops = LiveHelper.client.authorized_shops(access_token: LiveHelper.env("ACCESS_TOKEN")).to_a

    assert(shops.any? { |s| s.locator[:shop_cipher] == LiveHelper.env("SHOP_CIPHER") })
    refute_empty shop.info.data
  end

  # One walk down the catalogue, from a leaf category to its attributes, rules and brands.
  def test_catalogue_reads # rubocop:disable Minitest/MultipleAssertions
    categories = shop.categories.list(category_version: "v2", locale: "en-PH").data["categories"]

    assert_kind_of Array, categories
    leaf = categories.find { |c| c["is_leaf"] }
    skip "no leaf category is available to this shop" unless leaf

    assert_kind_of Array, shop.categories.attributes(leaf["id"], category_version: "v2").data["attributes"]
    assert_kind_of Hash, shop.categories.rules(leaf["id"], category_version: "v2").data
    assert_kind_of Array, shop.brands.list(category_id: leaf["id"], page_size: 10).first_page.items
  end

  def test_publish_prerequisites_and_warehouses
    assert_kind_of Array, shop.limits.data["check_results"]
    assert_kind_of Array, shop.warehouses.data["warehouses"]
  end

  def test_products_first_page
    page = shop.products.list(page_size: 10).first_page

    assert_kind_of Array, page.items
    skip "the shop has no products to read" if page.items.empty?

    product_id = page.items.first["id"]

    assert_equal product_id, shop.products.get(product_id).data["id"]
    assert_kind_of Array, shop.stock.get(product_id).data["inventory"]
  end

  def test_orders_first_page_of_the_last_day
    page = shop.orders.list(page_size: 10, update_time_ge: Time.now.to_i - 86_400).first_page

    assert_kind_of Array, page.items
  end
end
