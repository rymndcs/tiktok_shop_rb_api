# frozen_string_literal: true

module TiktokShopRbApi
  class Orders < Resources::Base
    PAGE_SIZE_MAX = 100
    # Get Order List takes these in the query; every other param is a body filter.
    QUERY_PARAMS = %w[sort_field sort_order].freeze
    private_constant :QUERY_PARAMS

    # POST /order/202309/orders/search, cursor-paged. page_size and page_token go in the query even though the
    # method is POST; sort_field and sort_order do too. Every other param is a body filter (order_status,
    # create_time_ge, update_time_lt, ...). A search, so idempotent. Read-only.
    # https://partner.tiktokshop.com/docv2/page/get-order-list-202309
    def list(page_size: nil, cursor: nil, **params)
      params = stringify(params)
      query = { "page_size" => page_size!(page_size, PAGE_SIZE_MAX) }.merge(params.slice(*QUERY_PARAMS))
      body = params.except(*QUERY_PARAMS)
      Pager.new(cursor:) do |token|
        page(session.post(Endpoints::ORDERS_SEARCH, body, query: query.merge("page_token" => token),
                                                          idempotent: true), "orders")
      end
    end

    # GET /order/202507/orders with ids = order_id. Read-only.
    # https://partner.tiktokshop.com/docv2/page/get-order-detail-202507
    def get(order_id, **params)
      session.get(Endpoints::ORDER_DETAIL, { "ids" => id!(order_id, "order_id") }.merge(stringify(params)))
    end
  end
end
