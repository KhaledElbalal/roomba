class AgentHarness
  # Thin OpenAI-compatible chat-completions client (works against any provider
  # exposing `/chat/completions`: OpenAI, Together, Groq, local vLLM, …). It
  # returns a normalized Completion; any transport/HTTP/parse failure surfaces
  # as ProviderError so ProviderChain can fall back. The api_key is held in
  # memory only and never logged.
  class LlmClient
    class ProviderError < StandardError; end

    Completion = Struct.new(
      :content, :tool_calls, :input_tokens, :output_tokens, :model,
      keyword_init: true
    )

    REQUEST_TIMEOUT = 120

    def initialize(base_url:, api_key:, model:, http: nil)
      @base_url = base_url.to_s.chomp("/")
      @api_key  = api_key
      @model    = model
      @http     = http
    end

    def chat(messages:, tools: nil)
      body = { model: @model, messages: messages }
      body[:tools] = tools if tools.present?

      parse(post(body))
    rescue ProviderError
      raise
    rescue => e
      # Normalize everything (timeouts, DNS, JSON, etc.) into one fallback signal.
      raise ProviderError, "#{@model}: #{e.class}: #{e.message}"
    end

    private

    def post(body)
      uri = URI.join("#{@base_url}/", "chat/completions")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"]  = "application/json"
      request.body = body.to_json

      response = http.request(uri, request)
      unless response.is_a?(Net::HTTPSuccess)
        raise ProviderError, "#{@model}: HTTP #{response.code}"
      end

      JSON.parse(response.body)
    end

    def parse(json)
      choice  = json.dig("choices", 0) or raise ProviderError, "#{@model}: no choices"
      message = choice.fetch("message")
      usage   = json["usage"] || {}

      Completion.new(
        content:       message["content"],
        tool_calls:    message["tool_calls"] || [],
        input_tokens:  usage["prompt_tokens"].to_i,
        output_tokens: usage["completion_tokens"].to_i,
        model:         json["model"] || @model
      )
    end

    # Injectable seam for specs; defaults to a real timed Net::HTTP call.
    def http
      @http ||= HttpAdapter.new(REQUEST_TIMEOUT)
    end

    class HttpAdapter
      def initialize(timeout) = @timeout = timeout

      def request(uri, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: @timeout, read_timeout: @timeout) do |http|
          http.request(request)
        end
      end
    end
  end
end
