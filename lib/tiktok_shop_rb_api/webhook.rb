# frozen_string_literal: true

module TiktokShopRbApi
  # TikTok Shop webhook verification and parsing: pure functions, no HTTP.
  # https://partner.tiktokshop.com/docv2/page/tts-webhooks-overview
  #
  # The Authorization header carries lower-case hex HMAC-SHA256(app_secret, app_key + raw_body), with no "Bearer"
  # prefix. Hash the raw body as received, never re-serialized JSON. TikTok retries an unacknowledged delivery at
  # 2 min, 30 min, 3 h and 12 h, then stops, so store tts_notification_id to drop duplicates.
  module Webhook
    # The payload's numeric `type` (topic pages 5, 6, 7 and 37 under /docv2/page/<n>-<topic>).
    TYPES = {
      "7" => :authorization_expiring, # UPCOMING_AUTHORIZATION_EXPIRATION
      "6" => :deauthorized,           # SELLER_DEAUTHORIZATION
      "5" => :product_status,         # PRODUCT_STATUS_CHANGE
      "37" => :product_status         # PRODUCT_AUDIT_STATUS_CHANGE
    }.freeze

    module_function

    # => true | false. url: is accepted for the shared interface; TikTok does not sign the URL.
    def verify(raw_body:, signature:, app_key:, app_secret:, url: nil)
      _ = url
      return false unless signature.is_a?(String) && raw_body.is_a?(String)

      expected = Signer.hmac(app_secret, Signer.webhook_base_string(app_key, raw_body))
      given = signature.downcase
      given.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(expected, given)
    end

    # => WebhookEvent. code is the payload's numeric type as a String ("7"); shop_id is normalized to a String.
    # Raises ArgumentError when the body is not a JSON object.
    def parse(raw_body)
      raw = JSON.parse(raw_body.to_s)
      raise ArgumentError, "webhook body is not a JSON object" unless raw.is_a?(Hash)

      event(Envelope.deep_freeze(raw))
    rescue JSON::ParserError
      raise ArgumentError, "webhook body is not valid JSON"
    end

    def event(raw)
      code = raw["type"].to_s
      WebhookEvent.new(type: TYPES.fetch(code, :other), code:, shop_id: raw["shop_id"]&.to_s,
                       occurred_at: raw["timestamp"].is_a?(Integer) ? Time.at(raw["timestamp"]).utc : nil,
                       data: raw["data"].is_a?(Hash) ? raw["data"] : {}.freeze, raw:)
    end
    private_class_method :event
  end
end
