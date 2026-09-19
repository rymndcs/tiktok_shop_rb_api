# frozen_string_literal: true

module TiktokShopRbApi
  # Every non-paged call returns a Response. `data` is the platform payload verbatim with the envelope removed;
  # `raw` is the parsed body exactly as received. Both are deeply frozen.
  Response = Data.define(:data, :request_id, :warnings, :item_errors, :http_status, :endpoint, :raw)

  # Turns TikTok's envelope into a Response, or raises the classified ApiError.
  #
  # Every response is {"code": int, "message": string, "request_id": string, "data": object|null}; code 0 is
  # success, and the HTTP status is set independently (https://partner.tiktokshop.com/docv2/page/common-errors).
  # Two shapes inside a success matter: create and edit return data.warnings[] (a field may have been silently
  # dropped), and the batch endpoints return per-item failures in data.errors[] inside code 0.
  module Envelope
    module_function

    # What an error needs besides the body: where the call went, whether it was idempotent, the response headers
    # and the time it was stamped.
    Call = Data.define(:endpoint, :idempotent, :headers, :now)

    def build(result, endpoint:, idempotent:, now:)
      status = result.fetch(:status).to_i
      call = Call.new(endpoint:, idempotent:, headers: result[:headers] || {}, now:)
      parsed = parse(result[:body])
      raise http_error(status, call) if parsed.nil?

      response = to_response(parsed, status, endpoint)
      raise api_error(parsed, response, call) unless success?(parsed)
      raise http_error(status, call, response) if status >= 400

      response
    end

    def parse(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    # A JSON body without `code` (a gateway page, say) carries no platform verdict: the HTTP status decides.
    def success?(parsed)
      !parsed.key?("code") || parsed["code"].to_s == "0"
    end

    def to_response(parsed, status, endpoint)
      data = parsed["data"].nil? ? {} : parsed["data"]
      Response.new(data: deep_freeze(data), request_id: parsed["request_id"]&.to_s, warnings: warnings(data),
                   item_errors: item_errors(data).freeze, http_status: status, endpoint:, raw: deep_freeze(parsed))
    end

    # data.warnings[].message on create and edit; Check Product Listing documents a single warnings object instead.
    def warnings(data)
      return [].freeze unless data.is_a?(Hash)

      list = data["warnings"].is_a?(Hash) ? [data["warnings"]] : data["warnings"]
      entries(list).map { |w| w["message"].to_s }.reject(&:empty?).freeze
    end

    # data.errors[] {code, message, detail {product_id | sku_id, extra_errors}} on activate, deactivate and
    # inventory update.
    def item_errors(data)
      return [] unless data.is_a?(Hash)

      entries(data["errors"]).map do |error|
        detail = error["detail"].is_a?(Hash) ? error["detail"] : {}
        id = detail["product_id"] || detail["sku_id"]
        ItemError.new(id: id.to_s, code: error["code"].to_s, message: error["message"].to_s, raw: deep_freeze(error))
      end
    end

    def entries(list)
      list.is_a?(Array) ? list.grep(Hash) : []
    end

    def api_error(parsed, response, call)
      code = parsed["code"].to_s
      klass = ErrorTable.classify(code, parsed["message"])
      message = parsed["message"].to_s.empty? ? code : parsed["message"].to_s
      klass.new(message, code:, request_id: response.request_id, http_status: response.http_status,
                         endpoint: call.endpoint, detail: detail(response.data), response:,
                         idempotent: call.idempotent, retry_after: retry_after(call))
    end

    def http_error(status, call, response = nil)
      klass = ErrorTable.classify_status(status)
      klass.new("HTTP #{status}", code: status.to_s, request_id: response&.request_id, http_status: status,
                                  endpoint: call.endpoint, detail: [], response:, idempotent: call.idempotent,
                                  retry_after: retry_after(call))
    end

    # An error body's data.errors[], when TikTok sends one.
    def detail(data)
      data.is_a?(Hash) ? entries(data["errors"]) : []
    end

    # Retry-After in seconds or as an HTTP date.
    def retry_after(call)
      value = Array(call.headers.find { |k, _| k.to_s.casecmp?("retry-after") }&.last).first.to_s.strip
      return nil if value.empty?
      return Float(value) if value.match?(/\A\d+(\.\d+)?\z/)

      [Time.httpdate(value) - call.now, 0.0].max
    rescue ArgumentError
      nil
    end

    def deep_freeze(value)
      case value
      when Hash then value.each_value { |v| deep_freeze(v) }.freeze
      when Array then value.each { |v| deep_freeze(v) }.freeze
      when String then value.freeze
      else value
      end
    end
  end
  private_constant :Envelope
end
