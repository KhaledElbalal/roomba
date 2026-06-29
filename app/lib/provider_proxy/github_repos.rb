module ProviderProxy
  # Lists the repos a GitHub token can access, reduced to the fields the repo
  # picker needs. We never hand the raw provider payload to the frontend.
  class GithubRepos
    ENDPOINT = URI("https://api.github.com/user/repos?per_page=100&sort=updated").freeze

    def self.call(token, http: ProviderProxy.adapter)
      new(http).call(token)
    end

    def initialize(http)
      @http = http
    end

    def call(token)
      req = Net::HTTP::Get.new(ENDPOINT)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"]        = "application/vnd.github+json"
      req["User-Agent"]    = "roomba"

      resp = @http.request(ENDPOINT, req)
      raise_for_status!(resp)

      JSON.parse(resp.body).map do |repo|
        {
          name:           repo["name"],
          full_name:      repo["full_name"],
          default_branch: repo["default_branch"],
          private:        repo["private"]
        }
      end
    rescue Error
      raise
    rescue => e
      raise Error.new("could not reach GitHub: #{e.class}", status: :bad_gateway)
    end

    private

    def raise_for_status!(resp)
      return if resp.is_a?(Net::HTTPSuccess)

      # GitHub signals a throttled request with a 429 or a 403 whose remaining
      # quota is zero; both should be a 429 to the caller, not a token failure.
      if resp.is_a?(Net::HTTPTooManyRequests) ||
         (resp.code == "403" && resp["x-ratelimit-remaining"] == "0")
        raise Error.new("GitHub rate limit exceeded", status: :too_many_requests)
      end

      raise Error.new("GitHub rejected the token (HTTP #{resp.code})", status: :bad_gateway)
    end
  end
end
