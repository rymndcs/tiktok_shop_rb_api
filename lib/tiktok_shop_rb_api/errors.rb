# frozen_string_literal: true

module TiktokShopRbApi
  class Error < StandardError
    def retryable?
      false
    end
  end

  # A bad keyword, an unknown endpoint, a malformed host URL, a missing service_id.
  class ConfigurationError < Error; end

  # No platform response was read: timeout, connection reset, TLS failure.
  class TransportError < Error
    def initialize(message = nil, idempotent: false)
      super(message)
      @idempotent = idempotent
    end

    # True only when the request was idempotent: nobody knows whether a timed-out write landed.
    def retryable?
      @idempotent
    end
  end

  # A platform hard cap stopped a Pager (product search stops at 10,000 results), so the walk is never silently
  # truncated.
  class PaginationLimitError < Error; end

  # An inbound webhook failed verification.
  class WebhookSignatureError < Error; end

  # The platform answered with an error.
  class ApiError < Error
    attr_reader :code, :request_id, :http_status, :endpoint, :detail, :response, :retry_after

    def initialize(message = nil, code: "", request_id: nil, http_status: nil, endpoint: nil, detail: [],
                   response: nil, retry_after: nil, idempotent: false)
      super(message)
      @code = code.to_s
      @request_id = request_id
      @http_status = http_status
      @endpoint = endpoint
      @detail = detail.freeze
      @response = response
      @retry_after = retry_after
      @idempotent = idempotent
    end
  end

  # This shop's token is invalid or expired, or the token and shop do not match: refresh or re-consent.
  class AuthenticationError < ApiError; end
  # The app key or secret is invalid, or the app is disabled or deleted: every shop is down.
  class AppCredentialsError < ApiError; end
  # Scope, IP allow-list, or the seller has no permission or is inactive.
  class PermissionError < ApiError; end
  # The platform rejected the signature or timestamp: a gem bug or clock skew.
  class SignatureError < ApiError; end
  # A malformed request: missing parameter, bad path, method, version or content type.
  class RequestError < ApiError; end
  # A documented business rejection: validation, content, entitlement, not found.
  class BusinessError < ApiError; end

  # Throttled; the call was not executed.
  class RateLimitError < ApiError
    def retryable?
      true
    end
  end

  # A quota is exhausted; the call was not executed. TikTok documents no such code; the class exists for the
  # shared contract.
  class QuotaExceededError < ApiError
    def retryable?
      true
    end
  end

  # A concurrent edit was refused; the call was not executed. TikTok documents no such code.
  class ConcurrencyError < ApiError
    def retryable?
      true
    end
  end

  # The platform failed internally. For a write the outcome is UNKNOWN, so only idempotent calls are retryable.
  class ServerError < ApiError
    def retryable?
      @idempotent
    end
  end
end
