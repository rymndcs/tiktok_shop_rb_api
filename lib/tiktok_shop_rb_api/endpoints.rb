# frozen_string_literal: true

module TiktokShopRbApi
  # The named hosts, and the only place in this gem that spells out a host. Hosts are configuration, not code: pick
  # one with Client.new(endpoint:), or pass base_url: / auth_base_url: / token_base_url: for any other host.
  # https://partner.tiktokshop.com/docv2/page/authorization-overview-202407 ("Authorization domains by market")
  #
  # api:   the Open API host. TikTok serves every market from this one host; the shop_cipher picks the shop.
  # auth:  the host of the seller authorization link (services.tiktokshop.com for the rest of the world, a separate
  #        host for the US).
  # token: the host of Get Access Token and Get Refresh Token, the same for every market.
  ENDPOINTS = {
    row: {
      api: "https://open-api.tiktokglobalshop.com", auth: "https://services.tiktokshop.com",
      token: "https://auth.tiktok-shops.com"
    }.freeze,
    us: {
      api: "https://open-api.tiktokglobalshop.com", auth: "https://services.us.tiktokshop.com",
      token: "https://auth.tiktok-shops.com"
    }.freeze
  }.freeze

  # Every endpoint path, with its version pinned. TikTok versions each endpoint separately (202309, 202312, ...) and
  # keeps an old version for at least 2 months after a new one ships
  # (https://partner.tiktokshop.com/docv2/page/api-versioning); bump a version here, deliberately, with its fixture.
  module Endpoints
    # The endpoint used when Client.new gets no endpoint:. Change it here, and only here.
    DEFAULT = :row

    AUTHORIZE_PAGE = "/open/authorize"
    TOKEN_GET = "/api/v2/token/get"
    TOKEN_REFRESH = "/api/v2/token/refresh"

    AUTHORIZED_SHOPS = "/authorization/202309/shops"
    PREREQUISITES = "/product/202312/prerequisites"
    WAREHOUSES = "/logistics/202309/warehouses"

    CATEGORIES = "/product/202309/categories"
    CATEGORY_RECOMMEND = "/product/202309/categories/recommend"
    BRANDS = "/product/202309/brands"
    IMAGE_UPLOAD = "/product/202309/images/upload"

    PRODUCTS = "/product/202309/products"
    LISTING_CHECK = "/product/202309/products/listing_check"
    PRODUCTS_SEARCH = "/product/202502/products/search"
    PRODUCTS_ACTIVATE = "/product/202309/products/activate"
    PRODUCTS_DEACTIVATE = "/product/202309/products/deactivate"
    DIAGNOSES = "/product/202405/products/diagnoses"
    INVENTORY_SEARCH = "/product/202309/inventory/search"

    ORDERS_SEARCH = "/order/202309/orders/search"
    ORDER_DETAIL = "/order/202507/orders"

    module_function

    def category_attributes(id) = "/product/202309/categories/#{id}/attributes"
    def category_rules(id) = "/product/202309/categories/#{id}/rules"
    def product(id) = "/product/202309/products/#{id}"
    def product_replace(id) = "/product/202509/products/#{id}"
    def product_partial_edit(id) = "/product/202509/products/#{id}/partial_edit"
    def inventory_update(id) = "/product/202309/products/#{id}/inventory/update"
    def prices_update(id) = "/product/202309/products/#{id}/prices/update"
  end
  private_constant :Endpoints
end
