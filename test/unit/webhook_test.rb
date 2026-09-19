# frozen_string_literal: true

# One event, several normalized fields.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

# https://partner.tiktokshop.com/docv2/page/tts-webhooks-overview and the topic pages, pulled 2026-09-20.
class WebhookTest < Minitest::Test
  include UnitHelper

  # The official vector: app key "abcdef", app secret "123", the documented body and digest.
  OFFICIAL = { raw_body: A::OFFICIAL_WEBHOOK_BODY,
               signature: "5dec0f11ec2f6783b8deee53c9ffbf8d024302f7c7e7fa55a35d17629031ac05" }.freeze

  def test_the_official_vector_is_hmac_of_app_key_plus_raw_body
    assert_equal OFFICIAL[:signature], OpenSSL::HMAC.hexdigest("SHA256", "123", "abcdef#{OFFICIAL[:raw_body]}")
    assert TiktokShopRbApi::Webhook.verify(raw_body: OFFICIAL[:raw_body], signature: OFFICIAL[:signature],
                                           app_key: "abcdef", app_secret: "123")
    assert TiktokShopRbApi::Webhook.verify(raw_body: OFFICIAL[:raw_body], signature: OFFICIAL[:signature].upcase,
                                           app_key: "abcdef", app_secret: "123")
  end

  def test_client_verify_webhook_with_the_official_vector
    client = TiktokShopRbApi::Client.new(app_key: "abcdef", app_secret: "123", transport: FakeTransport.new)
    event = client.verify_webhook(raw_body: OFFICIAL[:raw_body], signature: OFFICIAL[:signature])

    assert_equal "1", event.code
    assert_equal :other, event.type
    assert_raises(TiktokShopRbApi::WebhookSignatureError) do
      client.verify_webhook(raw_body: "#{OFFICIAL[:raw_body]} ", signature: OFFICIAL[:signature])
    end
    refute TiktokShopRbApi::Webhook.verify(raw_body: OFFICIAL[:raw_body], signature: "Bearer #{OFFICIAL[:signature]}",
                                           app_key: "abcdef", app_secret: "123")
  end

  def test_re_serialized_json_does_not_verify
    reserialized = JSON.generate(JSON.parse(A.webhook_vectors.last[:raw_body]))

    refute TiktokShopRbApi::Webhook.verify(raw_body: reserialized, signature: A.webhook_vectors.last[:signature],
                                           **A.webhook_credentials)
  end

  def test_the_wrong_app_key_does_not_verify
    refute TiktokShopRbApi::Webhook.verify(raw_body: OFFICIAL[:raw_body], signature: OFFICIAL[:signature],
                                           app_key: "abcdeg", app_secret: "123")
  end

  def test_the_url_is_ignored
    assert TiktokShopRbApi::Webhook.verify(raw_body: OFFICIAL[:raw_body], signature: OFFICIAL[:signature],
                                           app_key: "abcdef", app_secret: "123", url: "https://anything.test")
  end

  # Q4 in the plan: some payloads send product_id as a JSON integer. data stays verbatim; only shop_id is normalized.
  def test_parse_keeps_data_verbatim_and_normalizes_shop_id
    event = TiktokShopRbApi::Webhook.parse(A.webhook_parse_samples.find { |s| s[:expect][:code] == "5" }[:raw_body])

    assert_equal :product_status, event.type
    assert_equal 576_486_316_948_490_000, event.data["product_id"]
    assert_equal "7494049642642441621", event.shop_id
    assert_equal "7327112393057371910", event.raw["tts_notification_id"]
  end

  def test_expiring_event_carries_expiration_time
    event = TiktokShopRbApi::Webhook.parse(A.webhook_parse_samples.first[:raw_body])

    assert_equal :authorization_expiring, event.type
    assert_equal "1627587506", event.data["expiration_time"]
  end

  def test_bad_bodies
    assert_raises(ArgumentError) { TiktokShopRbApi::Webhook.parse("not json") }
    assert_raises(ArgumentError) { TiktokShopRbApi::Webhook.parse("[1]") }
  end
end
# rubocop:enable Minitest/MultipleAssertions
