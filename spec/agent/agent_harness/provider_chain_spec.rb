require "rails_helper"

RSpec.describe AgentHarness::ProviderChain do
  def completion(model: "gpt-4o", input: 100, output: 50)
    AgentHarness::LlmClient::Completion.new(
      content: "ok", tool_calls: [], input_tokens: input, output_tokens: output, model: model
    )
  end

  def member(name, client)
    AgentHarness::ProviderChain::Member.new(client: client, provider_name: name)
  end

  let(:primary_client)  { double("primary") }
  let(:fallback_client) { double("fallback") }

  it "uses the primary and does not flag fallback on success" do
    allow(primary_client).to receive(:chat).and_return(completion)
    chain = described_class.new(primary: member("openai", primary_client))

    call = chain.chat(messages: [], tools: [])

    expect(call.fallback).to be(false)
    expect(call.provider_name).to eq("openai")
    expect(call.cost_usd).to eq(AgentHarness::Pricing.cost(model: "gpt-4o", input_tokens: 100, output_tokens: 50))
  end

  it "falls back and flags the call when the primary fails" do
    allow(primary_client).to receive(:chat).and_raise(AgentHarness::LlmClient::ProviderError, "boom")
    allow(fallback_client).to receive(:chat).and_return(completion(model: "gpt-4o-mini"))

    chain = described_class.new(
      primary:  member("openai", primary_client),
      fallback: member("together", fallback_client)
    )

    call = chain.chat(messages: [], tools: [])

    expect(call.fallback).to be(true)
    expect(call.provider_name).to eq("together")
    expect(call.model).to eq("gpt-4o-mini")
  end

  it "propagates the primary error when no fallback is configured" do
    allow(primary_client).to receive(:chat).and_raise(AgentHarness::LlmClient::ProviderError, "boom")
    chain = described_class.new(primary: member("openai", primary_client))

    expect { chain.chat(messages: [], tools: []) }
      .to raise_error(AgentHarness::LlmClient::ProviderError)
  end
end
