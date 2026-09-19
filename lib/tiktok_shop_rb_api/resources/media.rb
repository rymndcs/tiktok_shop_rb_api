# frozen_string_literal: true

module TiktokShopRbApi
  class Media < Resources::Base
    # POST /product/202309/images/upload, multipart, one image (JPG, JPEG, PNG, WEBP, HEIC or BMP, at most 10 MB) in
    # the "data" part. params are form fields: use_case (MAIN_IMAGE, ATTRIBUTE_IMAGE, DESCRIPTION_IMAGE,
    # CERTIFICATION_IMAGE, SIZE_CHART_IMAGE). The endpoint takes no shop_cipher, and TikTok does not sign a multipart
    # body. data["uri"] goes into product payloads. Not idempotent: every upload makes a new URI.
    # https://partner.tiktokshop.com/docv2/page/upload-product-image-202309
    def upload_image(io, filename: nil, **params)
      raise ArgumentError, "io must respond to #read" unless io.respond_to?(:read)

      filename ||= io.respond_to?(:path) && io.path ? File.basename(io.path) : "image"
      fields = params.transform_keys(&:to_s).transform_values(&:to_s)
      content_type, body = Multipart.build(fields:, file: { name: "data", filename:, io: })
      session.multipart(Endpoints::IMAGE_UPLOAD, body, content_type:)
    end
  end
end
