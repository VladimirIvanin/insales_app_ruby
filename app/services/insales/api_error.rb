module Insales
  class ApiError < Error
    attr_reader :status, :headers, :body, :data

    def initialize(status, headers, body: "")
      @status, @headers, @body = status, headers, body
      @data = parse_body(body)
      super("InSales API returned HTTP #{status}")
    end

    def usage_limit
      headers["api-usage-limit"]
    end

    def retry_after
      headers["retry-after"]
    end

    private
      def parse_body(body)
        JSON.parse(body)
      rescue JSON::ParserError, EncodingError
        nil
      end
  end
end
