# frozen_string_literal: true

module TiktokShopRbApi
  # Every product write is audited asynchronously: create and edit return a product id while the product is still
  # PENDING or AUDITING, and it may fail audit later. Read the outcome from products.get (audit.status) or from
  # webhook types 5 and 37. Price and inventory edits skip audit.
  class Products < Resources::Base
    UNLIST_BATCH_MAX = 20
    RELIST_BATCH_MAX = 20
    PAGE_SIZE_MAX = 100
    DIAGNOSES_BATCH_MAX = 200
    # Search Products refuses to go past this many results (12052180).
    SEARCH_RESULTS_MAX = 10_000
    SEARCH_CAP_CODE = "12052180"
    private_constant :PAGE_SIZE_MAX, :DIAGNOSES_BATCH_MAX, :SEARCH_RESULTS_MAX, :SEARCH_CAP_CODE

    # POST /product/202309/products. payload is TikTok's own JSON: title, description, category_id,
    # category_version ("v2" for SEA and US), main_images[].uri, skus[] with sales_attributes, price and
    # inventory[].warehouse_id, ... Pass idempotency_key: in params (a body field, unique within the shop) and the
    # call becomes idempotent, so a ServerError or TransportError on it is retryable. A successful create can still
    # have dropped a field: read #warnings.
    # https://partner.tiktokshop.com/docv2/page/create-product-202309
    def create(payload, **params)
      body = stringify(payload).merge(stringify(params))
      session.post(Endpoints::PRODUCTS, body, idempotent: !body["idempotency_key"].to_s.empty?)
    end

    # GET /product/202309/products/{product_id}: status, audit.status, audit_failed_reasons, skus with
    # inventory[].warehouse_id. Products in FREEZE or DELETED are not returned. Native params:
    # return_under_review_version, return_draft_version, locale.
    # https://partner.tiktokshop.com/docv2/page/get-product-202309
    def get(product_id, **params)
      session.get(Endpoints.product(id!(product_id, "product_id")), params)
    end

    # POST /product/202509/products/{product_id}/partial_edit: TikTok's PARTIAL edit. Each top-level property you
    # send REPLACES that whole property (omitted nested fields are blanked; sending skus deletes any SKU you leave
    # out); properties you do not send are untouched. The gem sends exactly what it is given and never merges: read
    # the product first when you change part of an array. Content edits are re-audited. Not idempotent.
    # https://partner.tiktokshop.com/docv2/page/partial-edit-product-202509
    def update(product_id, payload, **params)
      body = stringify(payload).merge(stringify(params))
      session.post(Endpoints.product_partial_edit(id!(product_id, "product_id")), body)
    end

    # Extension. PUT /product/202509/products/{product_id}: a FULL replace. Every field is overwritten, blanks
    # included (price and inventory excepted), and SKU ids you omit are DELETED. Re-audited; the live version stays
    # up until the new one passes. Not idempotent.
    # https://partner.tiktokshop.com/docv2/page/edit-product-202509
    def replace(product_id, payload)
      session.put(Endpoints.product_replace(id!(product_id, "product_id")), stringify(payload))
    end

    # Extension. POST /product/202309/products/listing_check: the same body as create, checked without creating
    # anything (check_result PASS or FAILED, fail_reasons). A dry run, so idempotent.
    # https://partner.tiktokshop.com/docv2/page/check-product-listing-202309
    def check_listing(payload)
      session.post(Endpoints::LISTING_CHECK, stringify(payload), idempotent: true)
    end

    # POST /product/202502/products/search, cursor-paged; page_size and page_token go in the query and every other
    # param is a body filter (status, seller_skus, create_time_ge, update_time_le, ...). TikTok stops at 10,000
    # results; the pager then raises PaginationLimitError, and splitting by update_time windows is up to you.
    # https://partner.tiktokshop.com/docv2/page/search-products-202502
    def list(page_size: nil, cursor: nil, **params)
      query = { "page_size" => page_size!(page_size, PAGE_SIZE_MAX) }
      body = stringify(params)
      Pager.new(cursor:) do |token|
        page(search(body, query.merge("page_token" => token)), "products")
      end
    end

    # One Search Products request with seller_skus = [seller_sku] (matched on SKU level). => Array<String>
    # https://partner.tiktokshop.com/docv2/page/search-products-202502
    def find_by_seller_sku(seller_sku)
      raise ArgumentError, "seller_sku is empty" if seller_sku.to_s.empty?

      response = search({ "seller_skus" => [seller_sku.to_s] }, { "page_size" => PAGE_SIZE_MAX })
      Array(response.data["products"]).map { |product| product["id"].to_s }
    end

    # POST /product/202309/products/deactivate (at most 20 ids). Per-item failures come back inside a success, in
    # #item_errors. Idempotent: repeating it converges.
    # https://partner.tiktokshop.com/docv2/page/deactivate-products-202309
    def unlist(product_ids)
      batch(Endpoints::PRODUCTS_DEACTIVATE, product_ids, UNLIST_BATCH_MAX)
    end

    # POST /product/202309/products/activate (at most 20 ids): reactivates deactivated products. Activation is
    # RE-AUDITED, so a relisted product is not live until it passes audit again. Per-item failures are in
    # #item_errors. Idempotent: repeating it converges.
    # https://partner.tiktokshop.com/docv2/page/activate-product-202309
    def relist(product_ids)
      batch(Endpoints::PRODUCTS_ACTIVATE, product_ids, RELIST_BATCH_MAX)
    end

    # Extension. GET /product/202405/products/diagnoses (at most 200 ids, ACTIVATE products only).
    # https://partner.tiktokshop.com/docv2/page/product-information-issue-diagnosis-202405
    def diagnoses(product_ids)
      session.get(Endpoints::DIAGNOSES, { "product_ids" => ids!(product_ids, "product_ids", DIAGNOSES_BATCH_MAX) })
    end

    private

    def batch(path, product_ids, max)
      session.post(path, { "product_ids" => ids!(product_ids, "product_ids", max) }, idempotent: true)
    end

    def search(body, query)
      session.post(Endpoints::PRODUCTS_SEARCH, body, query:, idempotent: true)
    rescue BusinessError => e
      raise unless e.code == SEARCH_CAP_CODE

      raise PaginationLimitError, "Search Products stops at #{SEARCH_RESULTS_MAX} results (#{e.code}); narrow the " \
                                  "search with create_time or update_time windows"
    end
  end
end
