# frozen_string_literal: true

module TiktokShopRbApi
  # Category data is per shop (permission_statuses) and changes often; TikTok advises against caching it, and the
  # gem never caches. SEA and US shops must send category_version: "v2" (the 7-level tree); pass it in params.
  class Categories < Resources::Base
    # GET /product/202309/categories: the whole tree as a flat list (not paged). Native params: category_version,
    # locale, keyword, listing_platform, include_prohibited_categories.
    # https://partner.tiktokshop.com/docv2/page/get-categories-202309
    def list(**params)
      session.get(Endpoints::CATEGORIES, params)
    end

    # GET /product/202309/categories/{category_id}/attributes. Note TikTok's own spelling "is_requried", passed
    # through untouched.
    # https://partner.tiktokshop.com/docv2/page/get-attributes-202309
    def attributes(category_id, **params)
      session.get(Endpoints.category_attributes(id!(category_id, "category_id")), params)
    end

    # POST /product/202309/categories/recommend; title is sent as product_title. A read, so idempotent.
    # https://partner.tiktokshop.com/docv2/page/recommend-category-202309
    def recommend(title:, **params)
      raise ArgumentError, "title is empty" if title.to_s.empty?

      session.post(Endpoints::CATEGORY_RECOMMEND, { "product_title" => title.to_s }.merge(stringify(params)),
                   idempotent: true)
    end

    # Extension. GET /product/202309/categories/{category_id}/rules: certifications, size chart, COD, package
    # dimensions and similar per-category requirements.
    # https://partner.tiktokshop.com/docv2/page/get-category-rules-202309
    def rules(category_id, **params)
      session.get(Endpoints.category_rules(id!(category_id, "category_id")), params)
    end
  end
end
