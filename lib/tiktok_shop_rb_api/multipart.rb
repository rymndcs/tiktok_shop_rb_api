# frozen_string_literal: true

module TiktokShopRbApi
  # Builds a multipart/form-data body, so the bytes the gem hands the transport are exactly the bytes it built.
  module Multipart
    # The formats TikTok's Upload Product Image accepts: JPG, JPEG, PNG, WEBP, HEIC, BMP.
    CONTENT_TYPES = {
      ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png", ".webp" => "image/webp",
      ".heic" => "image/heic", ".bmp" => "image/bmp"
    }.freeze

    module_function

    # fields: { name => String }; file: { name:, filename:, io: }. => [content_type, body]
    def build(fields:, file:, boundary: "tiktok-shop-rb-api-#{SecureRandom.hex(16)}")
      body = +"".b
      fields.each do |name, value|
        body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n".b
      end
      body << file_part(boundary, file)
      body << "--#{boundary}--\r\n".b
      ["multipart/form-data; boundary=#{boundary}", body]
    end

    def file_part(boundary, file)
      filename = file.fetch(:filename).to_s.tr("\"\r\n", "")
      type = CONTENT_TYPES.fetch(File.extname(filename).downcase, "application/octet-stream")
      content = file.fetch(:io).read.to_s.b
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{file.fetch(:name)}\"; filename=\"#{filename}\"\r\n" \
      "Content-Type: #{type}\r\n\r\n".b + content + "\r\n".b
    end
  end
  private_constant :Multipart
end
