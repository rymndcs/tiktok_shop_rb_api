# frozen_string_literal: true

# Classification tests walk many documented pairs, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

class ErrorTableTest < Minitest::Test
  include UnitHelper

  def classify(code, message)
    TiktokShopRbApi.const_get(:ErrorTable).classify(code, message)
  end

  # test/fixtures/error_list.json holds every (code, message) pair in the Error Code tables of the endpoint pages the
  # gem calls, plus the common-errors page. Re-pull it to detect drift in the docs.
  def test_every_documented_pair_maps_to_a_documented_class
    pairs = Fixtures.load("error_list")["pairs"]

    assert_operator pairs.size, :>, 350
    unmapped = pairs.select { |pair| classify(pair["code"], pair["message"]) == TiktokShopRbApi::ApiError }

    assert_empty(unmapped.map { |pair| "#{pair["code"]}: #{pair["message"]}" })
  end

  # https://partner.tiktokshop.com/docv2/page/common-errors, "Message keyword index for 36009004".
  def test_the_overloaded_36009004_is_classified_by_message
    {
      "Missing credentials. The request does not include a required signature in the query." =>
        TiktokShopRbApi::SignatureError,
      "Invalid timestamp. The value of the `timestamp` query parameter must not be lesser than 0." =>
        TiktokShopRbApi::SignatureError,
      "Invalid timestamp. The value of the `timestamp` query parameter must not be earlier than 5 minutes before " \
      "the current time." => TiktokShopRbApi::SignatureError,
      "Invalid credentials. The `access_token` header is invalid." => TiktokShopRbApi::AuthenticationError,
      "Invalid credentials. The `x-tts-access-token` header is invalid." => TiktokShopRbApi::AuthenticationError,
      "Invalid credentials. Invalid `app_key` query parameter." => TiktokShopRbApi::AppCredentialsError,
      "Unexpected identifier. The `shop_cipher` query parameter is not required for this request." =>
        TiktokShopRbApi::RequestError,
      "Invalid identifier. The `shop_id` query parameter is invalid." => TiktokShopRbApi::RequestError,
      "Invalid API version. The `version` value is invalid or unsupported." => TiktokShopRbApi::RequestError
    }.each { |message, klass| assert_equal klass, classify("36009004", message), message }
  end

  def test_an_undocumented_36009004_message_is_not_guessed
    assert_equal TiktokShopRbApi::ApiError, classify("36009004", "Something new")
  end

  def test_code_families
    {
      "36009002" => TiktokShopRbApi::RateLimitError, "36009003" => TiktokShopRbApi::ServerError,
      "36009007" => TiktokShopRbApi::ServerError, "12001000" => TiktokShopRbApi::ServerError,
      "105002" => TiktokShopRbApi::AuthenticationError, "36004004" => TiktokShopRbApi::AuthenticationError,
      "101000" => TiktokShopRbApi::AuthenticationError, "106001" => TiktokShopRbApi::SignatureError,
      "105005" => TiktokShopRbApi::PermissionError, "36009033" => TiktokShopRbApi::PermissionError,
      "12052700" => TiktokShopRbApi::PermissionError, "106013" => TiktokShopRbApi::RequestError,
      "36009014" => TiktokShopRbApi::RequestError, "36009022" => TiktokShopRbApi::RequestError,
      "12052201" => TiktokShopRbApi::BusinessError, "12052093" => TiktokShopRbApi::BusinessError,
      "12052109" => TiktokShopRbApi::BusinessError, "12052180" => TiktokShopRbApi::BusinessError
    }.each { |code, klass| assert_equal klass, classify(code, ""), code }
  end

  def test_503_is_a_server_error_not_a_rate_limit
    shop, = shop_with(FakeTransport.json("Service Unavailable", status: 503))
    error = assert_raises(TiktokShopRbApi::ServerError) { shop.info }

    assert_predicate error, :retryable?
    assert_nil error.retry_after
  end

  def test_429_with_an_http_date_retry_after
    retry_at = (A::FIXED_TIME + 30).httpdate
    shop, = shop_with(FakeTransport.json(A.rate_limit_response[:body], status: 429,
                                                                       headers: { "retry-after" => retry_at }))
    error = assert_raises(TiktokShopRbApi::RateLimitError) { shop.info }

    assert_in_delta 30.0, error.retry_after
    assert_equal "36009002", error.code
  end

  def test_an_error_carries_code_message_request_id_and_endpoint
    shop, = shop_with(A.error("12052024", "Category is not final category"))
    error = assert_raises(TiktokShopRbApi::BusinessError) { shop.products.create({}) }

    assert_equal "12052024", error.code
    assert_equal "Category is not final category", error.message
    assert_equal "202203070749000101890810281E8C70B7", error.request_id
    assert_equal "/product/202309/products", error.endpoint
    assert_equal 200, error.http_status
  end

  def test_a_server_error_on_a_create_with_an_idempotency_key_is_retryable
    shop, = shop_with(A.server_error_response)
    error = assert_raises(TiktokShopRbApi::ServerError) { shop.products.create({}, idempotency_key: "k1") }

    assert_predicate error, :retryable?
    shop, = shop_with(A.server_error_response)

    refute_predicate assert_raises(TiktokShopRbApi::ServerError) { shop.products.create({}) }, :retryable?
  end
end
# rubocop:enable Minitest/MultipleAssertions
