class AgentHarness
  # Minimal GitHub REST client for the one write the harness needs: open a pull
  # request. Authenticated with the same PAT used to clone. The PAT is sent only
  # in the Authorization header and is never logged.
  class GithubClient
    class Error < StandardError; end

    API_ROOT = "https://api.github.com".freeze

    PullRequest = Struct.new(:html_url, :number, keyword_init: true)

    def initialize(pat:, repo:, http: nil)
      @pat  = pat
      @repo = repo
      @http = http
    end

    def default_branch
      get("/repos/#{@repo}").fetch("default_branch")
    end

    def open_pull_request(head:, title:, body:, base: nil)
      base ||= default_branch
      data = post("/repos/#{@repo}/pulls", {
        title: title, body: body, head: head, base: base
      })
      PullRequest.new(html_url: data.fetch("html_url"), number: data["number"])
    end

    private

    def get(path)
      request(Net::HTTP::Get.new(uri(path)))
    end

    def post(path, body)
      req = Net::HTTP::Post.new(uri(path))
      req.body = body.to_json
      request(req)
    end

    def uri(path) = URI.join(API_ROOT, path)

    def request(req)
      req["Authorization"] = "Bearer #{@pat}"
      req["Accept"]        = "application/vnd.github+json"
      req["Content-Type"]  = "application/json"
      req["User-Agent"]    = "roomba-agent"

      response = http.request(req.uri, req)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "GitHub #{req.method} #{req.uri.path} -> #{response.code}"
      end
      JSON.parse(response.body)
    end

    def http
      @http ||= LlmClient::HttpAdapter.new(30)
    end
  end
end
