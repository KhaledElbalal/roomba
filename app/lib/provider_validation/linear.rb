module ProviderValidation
  # Linear PAT check: a `viewer` GraphQL query. Note Linear expects the token
  # raw in the Authorization header — NOT a "Bearer " prefix.
  class Linear
    ENDPOINT     = URI("https://api.linear.app/graphql").freeze
    VIEWER_QUERY = "{ viewer { id name } }".freeze

    def self.call(token, http: ProviderValidation.adapter)
      new(http).call(token)
    end

    def initialize(http)
      @http = http
    end

    def call(token)
      req = Net::HTTP::Post.new(ENDPOINT)
      req["Authorization"] = token
      req["Content-Type"]  = "application/json"
      req.body = { query: VIEWER_QUERY }.to_json

      resp   = @http.request(ENDPOINT, req)
      viewer = parse(resp).dig("data", "viewer")
      unless resp.is_a?(Net::HTTPSuccess) && viewer
        raise Error, "Linear rejected the token (HTTP #{resp.code})"
      end

      { user_id: viewer["id"], name: viewer["name"] }
    rescue Error
      raise
    rescue => e
      raise Error, "could not reach Linear: #{e.class}"
    end

    private

    def parse(resp)
      JSON.parse(resp.body)
    rescue JSON::ParserError
      {}
    end
  end
end
