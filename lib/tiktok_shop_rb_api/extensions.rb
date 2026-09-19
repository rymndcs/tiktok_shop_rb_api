# frozen_string_literal: true

module TiktokShopRbApi
  # This gem's declared platform extensions (CONTRACT.md "Declared platform extensions" and "Declared constructor
  # keywords"): public surface beyond the shared contract. "Class#member" => what it is. The conformance suite fails
  # on any public method, constant or Client.new keyword that is neither in the contract nor declared here.
  EXTENSIONS = {
    "Client#token_base_url" => "Client.new keyword and reader: the token host (Get Access Token / Refresh Token)",
    "Client#service_id" => "Client.new keyword and reader: the app's service id, keying the seller authorization link",
    "Shop#warehouses" => "GET /logistics/202309/warehouses",
    "Categories#rules" => "GET /product/202309/categories/{category_id}/rules",
    "Products#replace" => "PUT /product/202509/products/{product_id}",
    "Products#check_listing" => "POST /product/202309/products/listing_check",
    "Products#diagnoses" => "GET /product/202405/products/diagnoses"
  }.freeze
end
