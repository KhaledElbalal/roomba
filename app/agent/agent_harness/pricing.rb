class AgentHarness
  # Per-token pricing so every `llm_call` artifact carries a `cost_usd` and the
  # run's cached `cost_usd` is meaningful. Rates are USD per 1M tokens — the unit
  # every major provider publishes — and encode external pricing a reader can't
  # infer from the code. Unknown models fall back to DEFAULT rather than failing
  # the run, so a new model id never blocks the loop (cost is then approximate).
  module Pricing
    RATES = {
      "gpt-4o"        => { input: 2.50,  output: 10.00 },
      "gpt-4o-mini"   => { input: 0.15,  output: 0.60 },
      "gpt-4.1"       => { input: 2.00,  output: 8.00 },
      "gpt-4.1-mini"  => { input: 0.40,  output: 1.60 },
      "o4-mini"       => { input: 1.10,  output: 4.40 }
    }.freeze

    DEFAULT = { input: 1.00, output: 3.00 }.freeze

    PER_MILLION = 1_000_000.0

    def self.cost(model:, input_tokens:, output_tokens:)
      rate = RATES.fetch(model, DEFAULT)
      usd = (input_tokens * rate[:input] + output_tokens * rate[:output]) / PER_MILLION
      BigDecimal(usd.to_s).round(6)
    end
  end
end
