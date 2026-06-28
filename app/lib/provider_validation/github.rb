module ProviderValidation
  # GitHub PAT check: GET /user. A 200 means the token authenticates; we keep
  # the login as metadata (handy for the connect UI) but never the token.
  class Github
    ENDPOINT = URI("https://api.github.com/user").freeze

    def self.call(token, http: ProviderValidation.adapter)
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
      unless resp.is_a?(Net::HTTPSuccess)
        raise Error, "GitHub rejected the token (HTTP #{resp.code})"
      end

      data = JSON.parse(resp.body)
      { login: data["login"], account_id: data["id"] }
    rescue Error
      raise
    rescue => e
      raise Error, "could not reach GitHub: #{e.class}"
    end
  end
end
