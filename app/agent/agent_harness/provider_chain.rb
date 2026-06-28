class AgentHarness
  # Primary provider with optional fallback. On a primary ProviderError it
  # transparently retries on the fallback and flags the resulting call so the
  # `llm_call` artifact records `fallback: true` (AC: fallback is flagged). With
  # no fallback configured, the primary error propagates and ends the run.
  class ProviderChain
    # A single model call paired with the metadata the recorder needs.
    Call = Struct.new(
      :completion, :provider_name, :model, :cost_usd, :fallback,
      keyword_init: true
    )

    Member = Struct.new(:client, :provider_name, keyword_init: true)

    def initialize(primary:, fallback: nil, pricing: Pricing)
      @primary  = primary
      @fallback = fallback
      @pricing  = pricing
    end

    def chat(messages:, tools: nil)
      call(@primary, fallback: false, messages: messages, tools: tools)
    rescue LlmClient::ProviderError
      raise unless @fallback

      call(@fallback, fallback: true, messages: messages, tools: tools)
    end

    private

    def call(member, fallback:, messages:, tools:)
      completion = member.client.chat(messages: messages, tools: tools)

      Call.new(
        completion:    completion,
        provider_name: member.provider_name,
        model:         completion.model,
        cost_usd:      @pricing.cost(
          model: completion.model,
          input_tokens: completion.input_tokens,
          output_tokens: completion.output_tokens
        ),
        fallback:      fallback
      )
    end
  end
end
