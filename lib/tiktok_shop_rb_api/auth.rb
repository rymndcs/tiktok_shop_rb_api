# frozen_string_literal: true

module TiktokShopRbApi
  # Seller authorization and tokens (https://partner.tiktokshop.com/docv2/page/authorization-overview-202407).
  #
  # The gem stores no tokens and never refreshes on its own. A refresh returns a NEW refresh token; whether the old
  # one still works is undocumented, so persist both tokens of the returned Grant in one write before anything else.
  class Auth
    include Redaction

    def initialize(connection)
      @connection = connection
      freeze
    end

    # => the seller authorization link on the configured auth host:
    #    <auth host>/open/authorize?service_id=..[&state=..]
    # TikTok fixes the redirect URL in Partner Center, so redirect_uri: raises ArgumentError. Raises
    # ConfigurationError when the client has no service_id:. TikTok redirects back with code and state.
    def authorize_url(redirect_uri: nil, state: nil)
      unless redirect_uri.nil?
        raise ArgumentError, "redirect_uri: is not accepted: TikTok's redirect URL is fixed in Partner Center"
      end
      if @connection.service_id.nil?
        raise ConfigurationError, "authorize_url needs Client.new(service_id:), from the app's page in Partner Center"
      end

      query = { service_id: @connection.service_id }
      query[:state] = state.to_s unless state.nil?
      "#{@connection.auth_base_url}#{Endpoints::AUTHORIZE_PAGE}?#{URI.encode_www_form(query)}"
    end

    # GET /api/v2/token/get on the token host, unsigned. The code lives 30 minutes and is single use. grant_type is
    # TikTok's literal "authorized_code" (not OAuth's "authorization_code"). No locator: one grant can cover several
    # shops; list them with Client#authorized_shops.
    def exchange_code(code:, **locator)
      no_locator!(locator)
      raise ArgumentError, "code: is empty" if code.to_s.empty?

      grant(@connection.token_call(Endpoints::TOKEN_GET, { auth_code: code.to_s, grant_type: "authorized_code" }))
    end

    # GET /api/v2/token/refresh on the token host, unsigned. Returns a new refresh token as well.
    def refresh(refresh_token:, **locator)
      no_locator!(locator)
      raise ArgumentError, "refresh_token: is empty" if refresh_token.to_s.empty?

      grant(@connection.token_call(Endpoints::TOKEN_REFRESH,
                                   { refresh_token: refresh_token.to_s, grant_type: "refresh_token" }))
    end

    def inspect
      "#<#{self.class.name}>"
    end

    private

    def no_locator!(locator)
      return if locator.empty?

      raise ArgumentError, "unknown locator key(s) #{locator.keys.inspect}: TikTok token calls take no locator"
    end

    # access_token_expire_in and refresh_token_expire_in are absolute Unix timestamps despite their names.
    def grant(response)
      data = response.data
      Grant.new(access_token: data["access_token"].to_s, refresh_token: data["refresh_token"].to_s,
                access_token_expires_at: epoch(data["access_token_expire_in"]),
                refresh_token_expires_at: epoch(data["refresh_token_expire_in"]), shop_ids: [].freeze,
                raw: response.raw)
    end

    def epoch(value)
      value.nil? ? nil : Time.at(Integer(value)).utc
    end
  end
end
