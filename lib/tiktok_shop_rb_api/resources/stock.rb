# frozen_string_literal: true

module TiktokShopRbApi
  class Stock < Resources::Base
    # POST /product/202309/inventory/search with product_ids = [product_id]. A read, so idempotent. Native params go
    # in the body.
    # https://partner.tiktokshop.com/docv2/page/inventory-search-202309
    def get(product_id, **params)
      body = { "product_ids" => [id!(product_id, "product_id")] }.merge(stringify(params))
      session.post(Endpoints::INVENTORY_SEARCH, body, idempotent: true)
    end

    # POST /product/202309/products/{product_id}/inventory/update. skus: native entries,
    # e.g. [{ id: "1729...", inventory: [{ warehouse_id: "7068...", quantity: 10 }] }]. Every SKU must belong to the
    # product, and every one of a SKU's warehouses must be listed. Takes effect at once, with no re-audit. Sets
    # absolute stock, so it is idempotent. Per-SKU failures are in #item_errors. TikTok documents no maximum per call.
    # https://partner.tiktokshop.com/docv2/page/update-inventory-202309
    def update(product_id, skus)
      path = Endpoints.inventory_update(id!(product_id, "product_id"))
      session.post(path, { "skus" => list!(skus, "skus") }, idempotent: true)
    end
  end
end
