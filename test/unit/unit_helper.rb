# frozen_string_literal: true

require "test_helper"
require "conformance_adapter"

# TikTok unit-test helpers on top of the conformance adapter's fixed credentials and clock.
module UnitHelper
  A = ConformanceAdapter

  def client_with(*responses, **)
    transport = FakeTransport.new(*responses)
    [A.build_client(transport:, **), transport]
  end

  def shop_with(*responses, **)
    client, transport = client_with(*responses, **)
    [A.build_shop(client), transport]
  end

  def ok(data = {})
    FakeTransport.json({ "code" => 0, "message" => "Success", "request_id" => "r1", "data" => data })
  end

  # Runs the block against a shop answering `response` and returns the one request it made.
  def request_for(response = ok, &)
    shop, transport = shop_with(response)
    yield(shop)

    assert_equal 1, transport.requests.size
    transport.requests.first
  end

  def signer
    TiktokShopRbApi.const_get(:Signer)
  end
end
