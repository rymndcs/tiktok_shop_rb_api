# frozen_string_literal: true

module TiktokShopRbApi
  # One shop session: the app client plus the seller's access token and this shop's cipher. Immutable.
  # One access token can cover several shops; the cipher picks one.
  class Shop
    include Redaction

    LOCATOR_KEYS = %i[shop_cipher].freeze

    attr_reader :locator, :categories, :brands, :media, :products, :stock, :prices, :orders

    def initialize(connection, access_token:, shop_cipher:)
      raise ArgumentError, "access_token: is empty" if access_token.to_s.empty?
      raise ArgumentError, "shop_cipher: is empty" if shop_cipher.to_s.empty?

      @session = Resources::Session.new(connection, access_token: access_token.to_s, shop_cipher: shop_cipher.to_s)
      @locator = { shop_cipher: shop_cipher.to_s }.freeze
      build_resources
      freeze
    end

    # GET /authorization/202309/shops (sent without shop_cipher, which it refuses). #data is the element of
    # shops[] whose cipher is this shop's, or {} when the token does not cover it; #raw keeps every shop.
    # https://partner.tiktokshop.com/docv2/page/get-authorized-shops-202309
    def info
      response = @session.get(Endpoints::AUTHORIZED_SHOPS, cipher: false)
      cipher = @locator[:shop_cipher]
      shop = Array(response.data["shops"]).find { |entry| entry.is_a?(Hash) && entry["cipher"] == cipher }
      response.with(data: shop || {}.freeze)
    end

    # GET /product/202312/prerequisites: pass or fail per check_item (SHOP_STATUS, PRODUCT_QUANTITY_LIMIT,
    # RETURN_WAREHOUSE, ...). TikTok publishes no numeric listing limit.
    # https://partner.tiktokshop.com/docv2/page/check-listing-prerequisites-202312
    def limits(**params)
      @session.get(Endpoints::PREREQUISITES, params)
    end

    # Extension. GET /logistics/202309/warehouses: warehouse_id is required on every SKU inventory entry.
    # https://partner.tiktokshop.com/docv2/page/get-warehouse-list-202309
    def warehouses(**params)
      @session.get(Endpoints::WAREHOUSES, params)
    end

    # The escape hatch: any path, signed, with this shop's token and cipher. Pass query: { shop_cipher: nil } for an
    # endpoint that refuses the cipher. One call, one request.
    def request(http_method, path, query: nil, body: nil, idempotent: nil)
      @session.request(http_method, path, query:, body:, idempotent:)
    end

    def inspect
      "#<#{self.class.name} shop_cipher=#{@locator[:shop_cipher]} access_token=#{Redaction::REDACTED}>"
    end

    private

    def build_resources
      @categories = Categories.new(@session)
      @brands = Brands.new(@session)
      @media = Media.new(@session)
      @products = Products.new(@session)
      @stock = Stock.new(@session)
      @prices = Prices.new(@session)
      @orders = Orders.new(@session)
    end
  end
end
