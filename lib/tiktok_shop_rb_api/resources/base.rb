# frozen_string_literal: true

module TiktokShopRbApi
  # Shared plumbing for the resource classes. Not part of the public contract.
  module Resources
    # Identity arguments accept a String or an Integer. TikTok ids are numeric strings on the wire; they also land in
    # URL paths, so anything but digits is refused.
    def self.id(value, name)
      string = value.to_s
      raise ArgumentError, "#{name} must be a numeric id, got #{value.inspect}" unless string.match?(/\A\d+\z/)

      string
    end

    # One shop session's signed calls, handed to every resource so the resources never see the token directly.
    # Every shop-scoped endpoint this gem wraps marks shop_cipher "Required: Y", so it is sent unless a call says
    # otherwise (image upload and Get Authorized Shops refuse it).
    class Session
      include Redaction

      attr_reader :connection

      def initialize(connection, access_token:, shop_cipher:)
        @connection = connection
        @access_token = access_token
        @shop_cipher = shop_cipher
        freeze
      end

      def get(path, query = {}, cipher: true)
        call(:get, path, query:, cipher:)
      end

      def post(path, body, query: {}, idempotent: false, cipher: true)
        call(:post, path, query:, body:, idempotent:, cipher:)
      end

      def put(path, body, idempotent: false)
        call(:put, path, body:, idempotent:)
      end

      def multipart(path, body, content_type:)
        @connection.call(:post, path, body:, content_type:, access_token: @access_token, idempotent: false)
      end

      # The escape hatch. A shop_cipher key in query: overrides the session's cipher; nil leaves it out.
      def request(http_method, path, query:, body:, idempotent:)
        query = (query || {}).to_h
        cipher = query.none? { |key, _| key.to_s == "shop_cipher" }
        call(http_method, path, query:, body:, idempotent:, cipher:)
      end

      def inspect
        "#<#{self.class.name} shop_cipher=#{@shop_cipher} access_token=#{Redaction::REDACTED}>"
      end

      private

      def call(http_method, path, query: {}, body: nil, idempotent: nil, cipher: true)
        query = { "shop_cipher" => @shop_cipher }.merge(query) if cipher
        @connection.call(http_method, path, query:, body:, access_token: @access_token, idempotent:)
      end
    end

    class Base
      def initialize(session)
        @session = session
        freeze
      end

      def inspect
        "#<#{self.class.name}>"
      end

      private

      attr_reader :session

      def id!(value, name)
        Resources.id(value, name)
      end

      def ids!(values, name, max)
        list = Array(values).map { |v| id!(v, name) }
        raise ArgumentError, "#{name} is empty" if list.empty?
        raise ArgumentError, "#{name} has #{list.size} ids; the maximum per call is #{max}" if list.size > max

        list
      end

      def page_size!(value, max)
        size = value.nil? ? max : Integer(value)
        raise ArgumentError, "page_size must be between 1 and #{max}, got #{size}" unless size.between?(1, max)

        size
      end

      def list!(list, name)
        list = Array(list)
        raise ArgumentError, "#{name} is empty" if list.empty?

        list
      end

      def stringify(hash)
        (hash || {}).to_h.transform_keys(&:to_s)
      end

      # A Page from one cursor-paged TikTok response: `items_key` names the list inside `data`, and an empty or
      # missing next_page_token both end the walk.
      def page(response, items_key)
        token = response.data["next_page_token"].to_s
        Page.new(items: Array(response.data[items_key]).freeze, next_cursor: token.empty? ? nil : token,
                 total: response.data["total_count"], response:)
      end
    end
  end
  private_constant :Resources
end
