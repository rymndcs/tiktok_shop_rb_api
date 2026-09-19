# frozen_string_literal: true

module TiktokShopRbApi
  class Prices < Resources::Base
    # POST /product/202309/products/{product_id}/prices/update. skus: native entries,
    # e.g. [{ id: "1729...", price: { amount: "189.00", currency: "PHP" } }]; amounts are decimal strings in major
    # units. The product must be ACTIVATE and not in a promotion (12052038). No re-audit. Sets absolute prices, so it
    # is idempotent. TikTok documents no maximum per call.
    # https://partner.tiktokshop.com/docv2/page/update-price-202309
    def update(product_id, skus)
      path = Endpoints.prices_update(id!(product_id, "product_id"))
      session.post(path, { "skus" => list!(skus, "skus") }, idempotent: true)
    end
  end
end
