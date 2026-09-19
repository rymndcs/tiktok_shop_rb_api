# frozen_string_literal: true

module TiktokShopRbApi
  # TikTok Shop request signing (https://partner.tiktokshop.com/docv2/page/sign-your-api-request): lower-case hex
  # HMAC-SHA256 keyed with the app secret over
  #   app_secret + path + {key}{value} for every query parameter except sign and access_token, keys sorted
  #   + the exact body bytes (unless the content type is multipart/form-data) + app_secret
  # Values are signed decoded, as sent after percent-decoding. The access token travels in the x-tts-access-token
  # header and is never signed.
  #
  # Webhook verification is a different algorithm: HMAC-SHA256(app_secret, app_key + raw_body)
  # (https://partner.tiktokshop.com/docv2/page/tts-webhooks-overview).
  module Signer
    EXCLUDED = %w[sign access_token].freeze

    module_function

    # query: { String => String } exactly as sent. body: the String sent, or nil.
    def base_string(path:, query:, body: nil, content_type: nil)
      params = query.except(*EXCLUDED).sort_by(&:first).map { |key, value| "#{key}#{value}" }
      base = "#{path}#{params.join}".b
      base << body.to_s.b unless multipart?(content_type)
      base
    end

    # Wraps the base string in the secret, then HMACs it with the same secret.
    def sign(secret, base_string)
      key = secret.to_s.b
      OpenSSL::HMAC.hexdigest("SHA256", key, key + base_string.b + key)
    end

    # A webhook signature is a plain HMAC with no wrapping.
    def hmac(secret, data)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s.b, data.b)
    end

    # Compares the media type only: the header is always "multipart/form-data; boundary=...".
    def multipart?(content_type)
      content_type.to_s.split(";").first.to_s.strip.casecmp?("multipart/form-data")
    end

    def webhook_base_string(app_key, raw_body)
      "#{app_key.to_s.b}#{raw_body.to_s.b}".b
    end
  end
  private_constant :Signer
end
