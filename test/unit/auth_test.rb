# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

# https://partner.tiktokshop.com/docv2/page/authorization-overview-202407, pulled 2026-09-20.
class AuthTest < Minitest::Test
  include UnitHelper

  def test_exchange_code_is_an_unsigned_get_with_the_literal_authorized_code_grant
    client, transport = client_with(Fixtures.response("api_v2_token_get"))
    grant = client.auth.exchange_code(code: A::AUTH_CODE)
    request = transport.requests.first

    assert_equal :get, request.http_method
    assert_equal "/api/v2/token/get", request.path
    assert_equal({ "app_key" => A::APP_KEY, "app_secret" => A::APP_SECRET, "auth_code" => A::AUTH_CODE,
                   "grant_type" => "authorized_code" }, request.query)
    assert_nil request.header("x-tts-access-token")
    assert_nil request.body
    assert_equal Time.at(1_660_556_783).utc, grant.access_token_expires_at
    assert_equal Time.at(1_691_487_031).utc, grant.refresh_token_expires_at
    assert_empty grant.shop_ids
    assert_equal "7010736057180325637", grant.raw.dig("data", "open_id")
  end

  def test_refresh
    client, transport = client_with(Fixtures.response("api_v2_token_refresh"))
    grant = client.auth.refresh(refresh_token: A::REFRESH_TOKEN)

    assert_equal({ "app_key" => A::APP_KEY, "app_secret" => A::APP_SECRET, "refresh_token" => A::REFRESH_TOKEN,
                   "grant_type" => "refresh_token" }, transport.requests.first.query)
    assert_equal "/api/v2/token/refresh", transport.requests.first.path
    assert_equal Fixtures.body("api_v2_token_refresh")["data"]["refresh_token"], grant.refresh_token
  end

  def test_token_calls_take_no_locator_and_no_empty_values
    client, transport = client_with

    assert_raises(ArgumentError) { client.auth.exchange_code(code: "c", shop_cipher: "x") }
    assert_raises(ArgumentError) { client.auth.refresh(refresh_token: "r", shop_id: 1) }
    assert_raises(ArgumentError) { client.auth.exchange_code(code: "") }
    assert_empty transport.requests
  end

  def test_an_invalid_auth_code_is_an_authentication_error_and_not_retryable
    client, = client_with(A.error("36004004", "Invalid auth code."))
    error = assert_raises(TiktokShopRbApi::AuthenticationError) { client.auth.exchange_code(code: "used") }

    refute_predicate error, :retryable?
  end

  def test_a_timed_out_token_call_is_not_retryable
    client, = client_with(TiktokShopRbApi::TransportError.new("read timeout"))

    refute_predicate assert_raises(TiktokShopRbApi::TransportError) { client.auth.exchange_code(code: "c") },
                     :retryable?
  end

  def test_authorize_url
    client, = client_with

    assert_equal "https://services.tiktokshop.com/open/authorize?service_id=#{A::SERVICE_ID}",
                 client.auth.authorize_url
    assert_raises(ArgumentError) { client.auth.authorize_url(redirect_uri: "https://app.test/cb") }
    no_service = TiktokShopRbApi::Client.new(app_key: "k", app_secret: "s", transport: FakeTransport.new)

    assert_nil no_service.service_id
    assert_raises(TiktokShopRbApi::ConfigurationError) { no_service.auth.authorize_url(state: "x") }
  end

  def test_authorized_shops_lists_every_shop_of_the_grant
    body = Fixtures.body("authorization_202309_shops")
    second = body["data"]["shops"][0].merge("id" => "7000714532876273421", "cipher" => "ROW_second", "region" => "ph")
    shops = [*body["data"]["shops"], second]
    client, transport = client_with(FakeTransport.json(body.merge("data" => { "shops" => shops })))
    shops = client.authorized_shops(access_token: "tok").to_a
    request = transport.requests.first

    assert_equal(%w[7000714532876273420 7000714532876273421], shops.map(&:shop_id))
    assert_equal [{ shop_cipher: "GCP_XF90igAAAABh00qsWgtvOiGFNqyubMt3" }, { shop_cipher: "ROW_second" }],
                 shops.map(&:locator)
    assert_equal "PH", shops.last.region
    assert_equal "tok", request.header("x-tts-access-token")
    refute request.query.key?("shop_cipher")
    assert_raises(ArgumentError) { client.authorized_shops }
  end
end
# rubocop:enable Minitest/MultipleAssertions
