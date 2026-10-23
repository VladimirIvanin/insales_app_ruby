require "net/http"
require "json"
require "timeout"

module Insales
  class Client
    MAX_RESPONSE_BYTES = 2 * 1024 * 1024
    MAX_ERROR_BYTES = 64 * 1024
    REQUEST_CLASSES = { get: Net::HTTP::Get, put: Net::HTTP::Put }.freeze
    Response = Data.define(:data, :status, :headers) do
      def usage_limit
        headers["api-usage-limit"]
      end

      def retry_after
        headers["retry-after"]
      end
    end

    def initialize(shop:, password:, app_id: Rails.configuration.x.insales.app_id, test_url: nil)
      domain = Protocol.shop(shop)
      @origin = URI("https://#{domain}")
      if test_url
        candidate = URI(test_url)
        unless Rails.env.test? && candidate.scheme == "http" && candidate.host == "127.0.0.1" &&
            candidate.path.empty? && !candidate.userinfo && !candidate.query && !candidate.fragment
          raise ArgumentError, "Test transport must use loopback HTTP in test environment"
        end
        @origin = candidate
      end
      @app_id, @password = app_id, password
    end

    def account(timeout: 5)
      response = request(:get, "/admin/account.json", timeout: timeout)
      validate_object(response)
    end

    def list_orders(**query)
      collection("orders", query)
    end

    def get_order(id)
      validate_object(request(:get, "/admin/orders/#{Protocol.identifier(id)}.json"))
    end

    def count_orders(**query)
      count("orders", query)
    end

    def update_order(id, attributes)
      validate_object(request(:put, "/admin/orders/#{Protocol.identifier(id)}.json", body: { order: attributes }), allow_empty: true)
    end

    def list_products(**query)
      collection("products", query)
    end

    def get_product(id)
      validate_object(request(:get, "/admin/products/#{Protocol.identifier(id)}.json"))
    end

    def count_products(**query)
      count("products", query)
    end

    def update_product(id, attributes)
      validate_object(request(:put, "/admin/products/#{Protocol.identifier(id)}.json", body: { product: attributes }), allow_empty: true)
    end

    private
      def collection(resource, query)
        response = request(:get, "/admin/#{resource}.json", query: query)
        raise ResourceError, "Expected a collection" unless response.data.is_a?(Array) && response.data.all? { |item| item.is_a?(Hash) }
        response
      end

      def count(resource, query)
        response = request(:get, "/admin/#{resource}/count.json", query: query)
        unless response.data.is_a?(Hash) && response.data["count"].is_a?(Integer) && response.data["count"] >= 0
          raise ResourceError, "Expected a count"
        end
        response
      end

      def validate_object(response, allow_empty: false)
        return response if allow_empty && response.status == 204
        unless response.data.is_a?(Hash) && response.data["id"].is_a?(Integer) && response.data["id"] > 0
          raise ResourceError, "Expected an object with an id"
        end
        response
      end

      def request(method, path, query: {}, body: nil, timeout: 5)
        uri = @origin.dup
        uri.path = path
        uri.query = URI.encode_www_form(query) if query.any?
        request_class = REQUEST_CLASSES.fetch(method)
        outgoing = request_class.new(uri)
        outgoing.basic_auth(@app_id, @password)
        outgoing["Accept"] = "application/json"
        outgoing["Accept-Encoding"] = "identity"
        if body
          outgoing["Content-Type"] = "application/json"
          outgoing.body = JSON.generate(body)
        end
        perform(uri, outgoing, timeout: timeout)
      end

      def perform(uri, outgoing, timeout:)
        http = Net::HTTP.new(uri.host, uri.port, nil)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = http.write_timeout = timeout
        http.max_retries = 0
        Timeout.timeout(timeout) do
          http.start do |connection|
            connection.request(outgoing) do |incoming|
              status = incoming.code.to_i
              headers = incoming.to_hash.transform_values { |values| values.join(", ") }
              read_api_error(incoming, status, headers) unless (200..299).cover?(status)
              body = +""
              incoming.read_body do |chunk|
                raise ResourceError, "Response exceeds size limit" if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES
                body << chunk
              end
              if incoming["content-length"] && body.bytesize != incoming["content-length"].to_i
                raise TransportError, "Incomplete API response"
              end
              data = status == 204 ? nil : JSON.parse(body)
              return Response.new(data: data, status: status, headers: headers)
            end
          end
        end
      rescue JSON::ParserError, EncodingError
        raise ResourceError, "Invalid API JSON response"
      rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
        raise TransportError, "InSales API connection failed"
      end

      def read_api_error(incoming, status, headers)
        body = +""
        incoming.read_body do |chunk|
          body << chunk.byteslice(0, MAX_ERROR_BYTES - body.bytesize)
          raise ApiError.new(status, headers, body: body) if body.bytesize >= MAX_ERROR_BYTES
        end
        raise ApiError.new(status, headers, body: body)
      end
  end
end
