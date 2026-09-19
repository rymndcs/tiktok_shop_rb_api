# frozen_string_literal: true

# Wire-shape tests check several fields of one request, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "unit_helper"

class EndpointsTest < Minitest::Test
  include UnitHelper

  # https://partner.tiktokshop.com/docv2/page/authorization-overview-202407 ("Authorization domains by market") and
  # https://partner.tiktokshop.com/docv2/page/methods-and-endpoints, pulled 2026-09-20.
  DOCUMENTED = {
    row: %w[https://open-api.tiktokglobalshop.com https://services.tiktokshop.com https://auth.tiktok-shops.com],
    us: %w[https://open-api.tiktokglobalshop.com https://services.us.tiktokshop.com https://auth.tiktok-shops.com]
  }.freeze

  def test_the_named_hosts_are_the_documented_ones
    assert_equal DOCUMENTED.keys, TiktokShopRbApi::ENDPOINTS.keys
    DOCUMENTED.each do |name, (api, auth, token)|
      assert_equal({ api:, auth:, token: }, TiktokShopRbApi::ENDPOINTS[name])
    end
  end

  def test_default_endpoint_is_row
    client, = client_with

    assert_equal :row, client.endpoint
    assert_equal "https://auth.tiktok-shops.com", client.token_base_url
  end

  def test_each_named_endpoint_sends_api_calls_consent_links_and_token_calls_to_its_hosts
    DOCUMENTED.each do |name, (api, auth, token)|
      client, transport = client_with(A.read_success_response, Fixtures.response("api_v2_token_get"), endpoint: name)
      A.build_shop(client).info
      client.auth.exchange_code(code: "c")

      assert_equal "#{api}/authorization/202309/shops", transport.requests[0].url.split("?").first, name.to_s
      assert_equal "#{token}/api/v2/token/get", transport.requests[1].url.split("?").first, name.to_s
      assert_equal "#{auth}/open/authorize?service_id=#{A::SERVICE_ID}&state=s", client.auth.authorize_url(state: "s")
    end
  end

  def test_every_host_can_be_replaced_by_any_url
    client, transport = client_with(A.read_success_response, Fixtures.response("api_v2_token_refresh"),
                                    base_url: "https://tts-egress.internal:8443/",
                                    auth_base_url: "https://consent.example.test",
                                    token_base_url: "http://token-proxy.internal/tts")
    A.build_shop(client).info
    client.auth.refresh(refresh_token: "r")

    assert_equal "https://tts-egress.internal:8443/authorization/202309/shops",
                 transport.requests[0].url.split("?").first
    assert_equal "http://token-proxy.internal/tts/api/v2/token/refresh", transport.requests[1].url.split("?").first
    assert client.auth.authorize_url.start_with?("https://consent.example.test/open/authorize?")
    assert_equal :row, client.endpoint
  end

  def test_base_url_alone_keeps_the_endpoints_consent_and_token_hosts
    client, = client_with(base_url: "https://api.example.test", endpoint: :us)

    assert client.auth.authorize_url.start_with?("https://services.us.tiktokshop.com/open/authorize?")
    assert_equal "https://auth.tiktok-shops.com", client.token_base_url
  end

  def test_configuration_errors
    error = assert_raises(TiktokShopRbApi::ConfigurationError) { client_with(endpoint: :sg) }

    assert_includes error.message, ":us"
    assert_raises(TiktokShopRbApi::ConfigurationError) { client_with(token_base_url: "ftp://x.test") }
    assert_raises(TiktokShopRbApi::ConfigurationError) do
      TiktokShopRbApi::Client.new(app_key: "", app_secret: "s", transport: FakeTransport.new)
    end
    assert_raises(TiktokShopRbApi::ConfigurationError) do
      TiktokShopRbApi::Client.new(app_key: "k", app_secret: "", transport: FakeTransport.new)
    end
    assert_raises(TiktokShopRbApi::ConfigurationError) do
      TiktokShopRbApi::Client.new(app_key: "k", app_secret: "s", transport: Object.new)
    end
    assert_equal "12345", TiktokShopRbApi::Client.new(app_key: 12_345, app_secret: "s").app_key
  end
end
# rubocop:enable Minitest/MultipleAssertions
