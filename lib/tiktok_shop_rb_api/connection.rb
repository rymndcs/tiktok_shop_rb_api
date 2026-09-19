# frozen_string_literal: true

module TiktokShopRbApi
  # Stamps, signs, sends, parses and classifies one request. Each retry under an opt-in RetryPolicy goes through
  # #perform again, so it is re-stamped from the injected clock and re-signed.
  class Connection
    include Redaction

    HTTP_METHODS = %i[get post put delete].freeze
    NETWORK_ERRORS = Transport::NetHttp::NETWORK_ERRORS
    USER_AGENT = "tiktok_shop_rb_api/#{VERSION} (Ruby #{RUBY_VERSION})".freeze
    JSON_TYPE = "application/json"

    # One request as it goes on the wire.
    Outgoing = Data.define(:http_method, :path, :url, :headers, :body)

    attr_reader :app_key, :base_url, :auth_base_url, :token_base_url, :service_id

    def initialize(app_key:, app_secret:, hosts:, service_id:, transport:, clock:, logger:, retry_policy:)
      @app_key = app_key
      @app_secret = app_secret
      @base_url = hosts.fetch(:api)
      @auth_base_url = hosts.fetch(:auth)
      @token_base_url = hosts.fetch(:token)
      @service_id = service_id
      @transport = transport
      @clock = clock
      @logger = logger
      @retry_policy = retry_policy
      freeze
    end

    # The current Time from the injected clock: the only time source for signing.
    def now
      @clock.call
    end

    # A signed Open API call.
    # query:        native parameters; Arrays are comma-joined (TikTok's GET list format), nil values dropped.
    # body:         a Hash or Array is serialized to JSON ONCE and those exact bytes are signed and sent; a String is
    #               sent verbatim with content_type: (multipart bodies are not signed).
    # access_token: sent in the x-tts-access-token header, never signed; nil for an app-level call.
    def call(http_method, path, query: nil, body: nil, content_type: nil, access_token: nil, idempotent: nil)
      raise ArgumentError, "unknown HTTP method #{http_method.inspect}" unless HTTP_METHODS.include?(http_method)
      raise ArgumentError, "path must start with /" unless path.to_s.start_with?("/")

      idempotent = http_method == :get if idempotent.nil?
      payload, type = encode_body(body, content_type)
      params = normalize(query)
      @retry_policy.run do
        perform(http_method, path.to_s, params:, body: payload, content_type: type, access_token:, idempotent:)
      end
    end

    # Get Access Token / Get Refresh Token on the token host: an UNSIGNED GET that carries the app secret in the
    # query, as TikTok documents. The URL is never logged. Not idempotent: the auth code is single use, and whether
    # a refresh token survives a refresh is undocumented, so a timed-out token call is never retryable.
    def token_call(path, query)
      params = { "app_key" => @app_key, "app_secret" => @app_secret }.merge(normalize(query))
      @retry_policy.run do
        url = "#{@token_base_url}#{path}?#{URI.encode_www_form(params)}"
        headers = { "User-Agent" => USER_AGENT, "Accept" => JSON_TYPE }
        dispatch(Outgoing.new(http_method: :get, path:, url:, headers:, body: nil), idempotent: false, time: now)
      end
    end

    def inspect
      "#<#{self.class.name} app_key=#{@app_key} base_url=#{@base_url} app_secret=#{Redaction::REDACTED}>"
    end

    private

    def perform(http_method, path, params:, body:, content_type:, access_token:, idempotent:)
      time = now
      signed = { "app_key" => @app_key, "timestamp" => time.to_i.to_s }.merge(params)
      base = Signer.base_string(path:, query: signed, body:, content_type:)
      query = signed.merge("sign" => Signer.sign(@app_secret, base))
      headers = { "User-Agent" => USER_AGENT, "Accept" => JSON_TYPE, "Content-Type" => content_type || JSON_TYPE }
      headers["x-tts-access-token"] = access_token if access_token
      url = "#{@base_url}#{path}?#{URI.encode_www_form(query)}"
      dispatch(Outgoing.new(http_method:, path:, url:, headers:, body:), idempotent:, time:)
    end

    def dispatch(outgoing, idempotent:, time:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = send_request(outgoing, idempotent)
      log(outgoing.http_method, outgoing.path, result, started)
      Envelope.build(result, endpoint: outgoing.path, idempotent:, now: time)
    end

    def send_request(outgoing, idempotent)
      @transport.call(method: outgoing.http_method, url: outgoing.url, headers: outgoing.headers, body: outgoing.body)
    rescue TransportError, *NETWORK_ERRORS => e
      raise TransportError.new(e.message, idempotent:)
    end

    def encode_body(body, content_type)
      case body
      when nil then [nil, nil]
      when String then [body, content_type || JSON_TYPE]
      else [JSON.generate(body), JSON_TYPE]
      end
    end

    # { String => String }, in the caller's order. The signer sorts; the URL keeps this order.
    def normalize(query)
      (query || {}).each_with_object({}) do |(key, value), out|
        next if value.nil?

        out[key.to_s] = value.is_a?(Array) ? value.join(",") : value.to_s
      end
    end

    def log(http_method, path, result, started)
      return unless @logger

      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      request_id = Envelope.parse(result[:body])&.fetch("request_id", nil)
      @logger.debug("tiktok_shop_rb_api #{http_method.upcase} #{path} status=#{result[:status]} " \
                    "request_id=#{request_id} duration_ms=#{ms}")
    end
  end
  private_constant :Connection
end
