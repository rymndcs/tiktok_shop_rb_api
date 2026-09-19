# frozen_string_literal: true

module TiktokShopRbApi
  # One Client per TikTok Shop app (app_key + app_secret). Immutable and safe to share across threads. There is no
  # global configuration, and nothing here assumes one shop per token or one token per app.
  class Client
    include Redaction

    attr_reader :app_key, :endpoint, :auth

    # app_key:        the app key from Partner Center (String or Integer).
    # app_secret:     the app secret.
    # endpoint:       a Symbol from TiktokShopRbApi::ENDPOINTS: :row (default) or :us. It names the API, consent-link
    #                 and token hosts.
    # base_url:       any API host URL; overrides the endpoint's API host.
    # auth_base_url:  any consent-link host URL; overrides the endpoint's auth host.
    # transport:      any object with #call(method:, url:, headers:, body:) -> { status:, headers:, body: }.
    # clock:          returns a Time; the only time source for signing. TikTok accepts [now - 5 min, now + 30 s].
    # logger:         any Logger; debug lines only, and never a secret.
    # retry_policy:   RetryPolicy.none (default) or an opt-in RetryPolicy.new(...).
    # token_base_url: extension; any token host URL; overrides the endpoint's token host.
    # service_id:     extension; the app's service id from Partner Center. Only authorize_url needs it.
    def initialize(app_key:, app_secret:, endpoint: Endpoints::DEFAULT, base_url: nil, auth_base_url: nil,
                   transport: Transport::NetHttp.new, clock: -> { Time.now }, logger: nil,
                   retry_policy: RetryPolicy.none, token_base_url: nil, service_id: nil)
      @app_key = app_key!(app_key)
      @endpoint = endpoint
      @connection = Connection.new(
        app_key: @app_key, app_secret: secret!(app_secret),
        hosts: hosts!(endpoint, api: base_url, auth: auth_base_url, token: token_base_url),
        service_id: service_id&.to_s, transport: callable!(transport, "transport"),
        clock: callable!(clock, "clock"), logger:, retry_policy: retry_policy || RetryPolicy.none
      )
      @auth = Auth.new(@connection)
      freeze
    end

    # Extension: the token host in use.
    def token_base_url
      @connection.token_base_url
    end

    # Extension: the service id authorize_url uses, or nil.
    def service_id
      @connection.service_id
    end

    # A shop session. TikTok's locator is { shop_cipher: }, from AuthorizedShop#locator.
    def shop(access_token:, **locator)
      missing = Shop::LOCATOR_KEYS - locator.keys
      unknown = locator.keys - Shop::LOCATOR_KEYS
      raise ArgumentError, "missing locator key(s) #{missing.inspect}" if missing.any?
      raise ArgumentError, "unknown locator key(s) #{unknown.inspect}" if unknown.any?

      Shop.new(@connection, access_token:, **locator)
    end

    # GET /authorization/202309/shops with the token: every shop this authorization covers (one grant can cover
    # several). Not paged, so the Pager has one page. => Pager of AuthorizedShop
    # https://partner.tiktokshop.com/docv2/page/get-authorized-shops-202309
    def authorized_shops(access_token: nil)
      raise ArgumentError, "access_token: is required: TikTok lists the shops of one authorization" if access_token.nil?

      Pager.new do |_cursor|
        response = @connection.call(:get, Endpoints::AUTHORIZED_SHOPS, access_token: access_token.to_s)
        shops = Array(response.data["shops"]).grep(Hash).map { |raw| authorized_shop(raw) }
        Page.new(items: shops.freeze, next_cursor: nil, total: shops.size, response:)
      end
    end

    # Verifies a webhook with this client's app key and secret, then parses it. url: is ignored (TikTok does not
    # sign it). Raises WebhookSignatureError when verification fails.
    def verify_webhook(raw_body:, signature:, url: nil)
      valid = Webhook.verify(raw_body:, signature:, app_key: @app_key, app_secret: @app_secret, url:)
      raise WebhookSignatureError, "TikTok Shop webhook signature did not verify" unless valid

      Webhook.parse(raw_body)
    end

    # The escape hatch for app-level paths: signed with the app credentials, with no token and no shop_cipher.
    # One call, one request.
    def request(http_method, path, query: nil, body: nil, idempotent: nil)
      @connection.call(http_method, path, query:, body:, idempotent:)
    end

    def inspect
      "#<#{self.class.name} app_key=#{@app_key.inspect} endpoint=#{@endpoint.inspect} " \
        "app_secret=#{Redaction::REDACTED}>"
    end

    private

    def authorized_shop(raw)
      AuthorizedShop.new(shop_id: raw["id"].to_s, name: raw["name"], region: raw["region"]&.to_s&.upcase,
                         authorization_expires_at: nil, locator: { shop_cipher: raw["cipher"].to_s }.freeze, raw:)
    end

    def app_key!(value)
      key = value.to_s
      raise ConfigurationError, "app_key must be a non-empty String or Integer" if key.empty?

      key
    end

    def secret!(value)
      raise ConfigurationError, "app_secret must be a non-empty String" unless value.is_a?(String) && !value.empty?

      @app_secret = value
    end

    def hosts!(endpoint, **overrides)
      named = ENDPOINTS.fetch(endpoint) do
        raise ConfigurationError, "unknown endpoint #{endpoint.inspect}; expected one of #{ENDPOINTS.keys.inspect} " \
                                  "(or pass base_url: / auth_base_url: / token_base_url:)"
      end
      named.to_h { |role, url| [role, url!(overrides[role] || url, role)] }
    end

    def url!(value, role)
      name = role == :api ? "base_url" : "#{role}_base_url"
      uri = URI.parse(value.to_s)
      raise ConfigurationError, "#{name} must be an http(s) URL" unless %w[http https].include?(uri.scheme) && uri.host

      value.to_s.chomp("/")
    rescue URI::InvalidURIError
      raise ConfigurationError, "#{name} must be an http(s) URL"
    end

    def callable!(value, name)
      raise ConfigurationError, "#{name} must respond to #call" unless value.respond_to?(:call)

      value
    end
  end
end
