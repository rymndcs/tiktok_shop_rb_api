# frozen_string_literal: true

module TiktokShopRbApi
  class Brands < Resources::Base
    PAGE_SIZE_MAX = 100

    # GET /product/202309/brands, cursor-paged (page_token / next_page_token). Brands and their authorized_status
    # are per shop. Native params: is_authorized, brand_name, category_version.
    # https://partner.tiktokshop.com/docv2/page/get-brands-202309
    def list(category_id: nil, page_size: nil, cursor: nil, **params)
      query = { "page_size" => page_size!(page_size, PAGE_SIZE_MAX) }.merge(stringify(params))
      query["category_id"] = id!(category_id, "category_id") unless category_id.nil?
      Pager.new(cursor:) do |token|
        page(session.get(Endpoints::BRANDS, query.merge("page_token" => token)), "brands")
      end
    end
  end
end
