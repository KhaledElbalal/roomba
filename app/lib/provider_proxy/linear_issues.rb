module ProviderProxy
  # Lists Linear issues for the issue picker. `code` is Linear's human
  # identifier (e.g. ROO-5); `type` is the work category the agent branches on —
  # "bugfix" or "feature". Linear has no native type field, so we derive it from
  # the issue's labels (a "bug" label means bugfix; everything else is a
  # feature). Note: Linear wants the token raw in Authorization, no "Bearer ".
  class LinearIssues
    ENDPOINT = URI("https://api.linear.app/graphql").freeze
    QUERY = <<~GRAPHQL.freeze
      query {
        issues(first: 50, orderBy: updatedAt) {
          nodes {
            id
            identifier
            title
            description
            labels { nodes { name } }
          }
        }
      }
    GRAPHQL

    def self.call(token, http: ProviderProxy.adapter)
      new(http).call(token)
    end

    def initialize(http)
      @http = http
    end

    def call(token)
      req = Net::HTTP::Post.new(ENDPOINT)
      req["Authorization"] = token
      req["Content-Type"]  = "application/json"
      req.body = { query: QUERY }.to_json

      resp = @http.request(ENDPOINT, req)
      body = parse(resp)
      raise_for_status!(resp, body)

      body.dig("data", "issues", "nodes").to_a.map do |node|
        {
          id:          node["id"],
          code:        node["identifier"],
          title:       node["title"],
          description: node["description"],
          type:        issue_type(node)
        }
      end
    rescue Error
      raise
    rescue => e
      raise Error.new("could not reach Linear: #{e.class}", status: :bad_gateway)
    end

    private

    def issue_type(node)
      labels = node.dig("labels", "nodes").to_a.map { |l| l["name"].to_s.downcase }
      labels.any? { |name| name.include?("bug") } ? "bugfix" : "feature"
    end

    def raise_for_status!(resp, body)
      if resp.is_a?(Net::HTTPTooManyRequests)
        raise Error.new("Linear rate limit exceeded", status: :too_many_requests)
      end

      # GraphQL returns 200 with an `errors` array for auth/validation failures,
      # so a successful HTTP status alone doesn't mean the call worked.
      return if resp.is_a?(Net::HTTPSuccess) && body["errors"].blank? && body.key?("data")

      raise Error.new("Linear rejected the token (HTTP #{resp.code})", status: :bad_gateway)
    end

    def parse(resp)
      JSON.parse(resp.body)
    rescue JSON::ParserError
      {}
    end
  end
end
