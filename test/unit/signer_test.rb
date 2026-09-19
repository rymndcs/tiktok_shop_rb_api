# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

# https://partner.tiktokshop.com/docv2/page/sign-your-api-request, pulled 2026-09-20, and the canonicalization traps
# in the TikTok plan (section 3, rows S1 to S6).
class SignerTest < Minitest::Test
  include UnitHelper

  SECRET = "e59af819cc"

  # The official example, every documented step: the base string, the string wrapped in the secret, the digest.
  def test_official_get_authorized_shops_vector
    base = signer.base_string(path: "/authorization/202309/shops",
                              query: { "app_key" => "29a39d", "timestamp" => "1623812664" })

    assert_equal "/authorization/202309/shopsapp_key29a39dtimestamp1623812664", base
    assert_equal "e59af819cc/authorization/202309/shopsapp_key29a39dtimestamp1623812664e59af819cc",
                 "#{SECRET}#{base}#{SECRET}"
    assert_equal "b596b73e0cc6de07ac26f036364178ab16b0a907af13d43f0a0cd2345f582dc8", signer.sign(SECRET, base)
  end

  # The doc prints this body-bearing base string without a digest: shop_cipher sorts between app_key and timestamp,
  # and the body is appended raw.
  def test_official_body_bearing_base_string
    body = '{"address":"https://partner.tiktokshop.com","event_type":"PACKAGE_UPDATE"}'
    base = signer.base_string(path: "/event/202309/webhooks", body:, content_type: "application/json",
                              query: { "timestamp" => "1696909648", "app_key" => "68xu9ks5p4i8",
                                       "shop_cipher" => "ROW_xkMbgAAAeVAQra0eZWebFQq5aIKt" })

    assert_equal "/event/202309/webhooksapp_key68xu9ks5p4i8shop_cipherROW_xkMbgAAAeVAQra0eZWebFQq5aIKt" \
                 "timestamp1696909648#{body}", base
  end

  # S2: the header is always "multipart/form-data; boundary=...", so only the media type is compared.
  def test_a_multipart_body_is_not_signed_whatever_its_parameters
    query = { "app_key" => "k", "timestamp" => "1" }
    types = ["multipart/form-data", "Multipart/Form-Data", "multipart/form-data; boundary=abc"]

    types.each do |type|
      assert_equal "/papp_keyktimestamp1", signer.base_string(path: "/p", query:, body: "BYTES", content_type: type)
    end
    assert_equal "/papp_keyktimestamp1BYTES",
                 signer.base_string(path: "/p", query:, body: "BYTES", content_type: "application/json")
  end

  def test_an_uploaded_image_is_sent_multipart_without_its_body_signed
    request = request_for { |s| s.media.upload_image(StringIO.new("IMG".b), filename: "a.png", use_case: "MAIN_IMAGE") }

    assert_match %r{\Amultipart/form-data; boundary=}, request.header("Content-Type")
    assert_includes request.body, "IMG"
    assert_equal A.expected_signature(request), request.query["sign"]
    refute request.query.key?("shop_cipher"), "Upload Product Image takes no shop_cipher"
  end

  # S6: access_token and sign never enter the base string.
  def test_sign_and_access_token_are_excluded
    base = signer.base_string(path: "/p", query: { "sign" => "s", "access_token" => "t", "b" => "2", "a" => "1" })

    assert_equal "/pa1b2", base
  end

  # S1: the JSON body is serialized once; the bytes sent are the bytes signed, byte for byte.
  def test_the_body_sent_is_the_body_signed
    request = request_for { |s| s.products.create({ "title" => "Größe – ✓", "n" => 1.5 }) }

    assert_equal '{"title":"Größe – ✓","n":1.5}', request.body
    assert_equal A.expected_signature(request), request.query["sign"]
  end

  # S3: a page_token holding "+" and "/" is signed decoded and sent percent-encoded.
  def test_page_token_with_plus_and_slash_is_signed_decoded_and_sent_encoded
    token = A::ORDER_PAGE_TOKEN
    request = request_for { |s| s.orders.list(cursor: token).first_page }

    assert_includes request.url, "page_token=6AsPQsUMvH3RkchNUPPh22NROHkE0D8pmq%2FN5M1kHYcZmtRyv9aVrNv65W7Q6tFA%2B7D1"
    assert_equal token, request.query["page_token"]
    assert_equal A.expected_signature(request), request.query["sign"]
  end

  # S5: GET list parameters are comma-joined before signing, so the signed value is the sent value.
  def test_array_query_values_are_comma_joined
    request = request_for { |s| s.products.diagnoses(%w[12345678 123456]) }

    assert_equal "12345678,123456", request.query["product_ids"]
    assert_equal(1, request.query_pairs.count { |key, _| key == "product_ids" })
    assert_equal A.expected_signature(request), request.query["sign"]
  end

  def test_the_token_travels_in_the_header_and_the_timestamp_comes_from_the_clock_at_send_time
    later = Time.at(1_700_000_000)
    client, transport = client_with(A.read_success_response, clock: -> { later })
    A.build_shop(client).products.get(1)
    request = transport.requests.first

    assert_equal A::ACCESS_TOKEN, request.header("x-tts-access-token")
    refute request.query.key?("access_token")
    assert_equal "1700000000", request.query["timestamp"]
    assert_equal A::SHOP_CIPHER, request.query["shop_cipher"]
    assert_equal A.expected_signature(request), request.query["sign"]
  end
end
# rubocop:enable Minitest/MultipleAssertions
