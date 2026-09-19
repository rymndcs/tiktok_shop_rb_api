# frozen_string_literal: true

require "test_helper"
require "date"
require "fileutils"
require "logger"

# Opt-in live tests: `rake test:live`. They never run under plain `rake`, and they skip unless credentials are set.
#
#   TIKTOK_SHOP_LIVE_APP_KEY, TIKTOK_SHOP_LIVE_APP_SECRET, TIKTOK_SHOP_LIVE_ACCESS_TOKEN, TIKTOK_SHOP_LIVE_SHOP_CIPHER
#   optional: TIKTOK_SHOP_LIVE_ENDPOINT (a name from TiktokShopRbApi::ENDPOINTS, default :row),
#             TIKTOK_SHOP_LIVE_BASE_URL and TIKTOK_SHOP_LIVE_TOKEN_BASE_URL.
#   TIKTOK_SHOP_RECORD=1 writes every successful response (2xx, code 0), redacted, over
#             test/fixtures/<path>.json with "_source" naming "recorded live <date>", replacing the documentation
#             sample. Error responses are never recorded.
#
# TikTok has no sandbox host: a Partner Center development shop is reached with the same credentials and host.
# The live tests only READ. They never refresh a token and never write.
module LiveHelper
  PREFIX = "TIKTOK_SHOP_LIVE"
  REQUIRED = %w[APP_KEY APP_SECRET ACCESS_TOKEN SHOP_CIPHER].freeze
  SECRET_KEYS = /token|secret|\Asign\z|\Aauth_code\z/i

  module_function

  def configured?
    REQUIRED.all? { |key| !env(key).to_s.empty? }
  end

  def env(key)
    ENV.fetch("#{PREFIX}_#{key}", nil)
  end

  def credentials
    REQUIRED.map { |key| env(key) }
  end

  def client
    options = { endpoint: (env("ENDPOINT") || "row").to_sym }
    options[:base_url] = env("BASE_URL") if env("BASE_URL")
    options[:token_base_url] = env("TOKEN_BASE_URL") if env("TOKEN_BASE_URL")
    logger = Logger.new($stderr, level: ENV["TIKTOK_SHOP_LIVE_DEBUG"] ? Logger::DEBUG : Logger::INFO)
    TiktokShopRbApi::Client.new(app_key: env("APP_KEY"), app_secret: env("APP_SECRET"), transport:, logger:,
                                **options)
  end

  def shop
    client.shop(access_token: env("ACCESS_TOKEN"), shop_cipher: env("SHOP_CIPHER"))
  end

  def transport
    net = TiktokShopRbApi::Transport::NetHttp.new
    ENV["TIKTOK_SHOP_RECORD"] == "1" ? Recorder.new(net, secrets: credentials, label: PREFIX) : net
  end

  # The fixture name for a path, as test/fixtures names the documentation samples: "/" becomes "_" and every
  # numeric id (any all-digit segment but the version after the first one) becomes "id".
  # /product/202309/categories/600001/rules => product_202309_categories_id_rules
  def fixture_name(path)
    path.delete_prefix("/").split("/").each_with_index.map do |segment, index|
      index != 1 && segment.match?(/\A\d+\z/) ? "id" : segment
    end.join("_")
  end

  # Wraps a transport and records each successful response as a redacted fixture.
  class Recorder
    def initialize(inner, secrets:, label:, dir: Fixtures::DIR)
      @inner = inner
      @dir = dir
      @secrets = secrets.compact.reject(&:empty?)
      @label = label.strip
    end

    def call(method:, url:, headers:, body:)
      result = @inner.call(method:, url:, headers:, body:)
      record(method, URI(url).path, result)
      result
    end

    private

    def record(method, path, result)
      parsed = JSON.parse(result[:body])
      return unless recordable?(result[:status], parsed)

      today = Date.today.iso8601
      fixture = { "_source" => { "url" => path, "pulled" => today, "endpoint" => "#{method.upcase} #{path}",
                                 "origin" => "recorded live #{today} (#{@label}), redacted" },
                  "status" => result[:status], "headers" => {}, "body" => redact(parsed) }
      File.write(File.join(@dir, "#{LiveHelper.fixture_name(path)}.json"), "#{JSON.pretty_generate(fixture)}\n")
    rescue JSON::ParserError
      nil
    end

    def recordable?(status, parsed)
      (200..299).cover?(status.to_i) && parsed.is_a?(Hash) && parsed["code"].to_s == "0"
    end

    def redact(value)
      case value
      when Hash then value.to_h { |k, v| [k, redact_member(k, v)] }
      when Array then value.map { |v| redact(v) }
      when String then @secrets.reduce(value) { |text, secret| text.gsub(secret, "[REDACTED]") }
      else value
      end
    end

    def redact_member(key, value)
      key.to_s.match?(SECRET_KEYS) && value.is_a?(String) ? "[REDACTED]" : redact(value)
    end
  end

  # Include in a live test class: every test skips unless the credentials are present.
  module Gate
    def setup
      super
      return if LiveHelper.configured?

      skip "set TIKTOK_SHOP_LIVE_* to run live tests (see test/live/live_helper.rb)"
    end
  end
end
