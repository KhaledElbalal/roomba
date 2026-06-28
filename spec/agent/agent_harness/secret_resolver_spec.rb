require "rails_helper"

RSpec.describe AgentHarness::SecretResolver do
  let(:client) { instance_double(Aws::SecretsManager::Client) }

  subject(:resolver) { described_class.new(client: client) }

  it "returns the secret string for a ref" do
    allow(client).to receive(:get_secret_value)
      .with(secret_id: "ref-1")
      .and_return(double(secret_string: "ghp_token", secret_binary: nil))

    expect(resolver.resolve("ref-1")).to eq("ghp_token")
  end

  it "decodes binary secrets when no string is present" do
    allow(client).to receive(:get_secret_value)
      .and_return(double(secret_string: nil, secret_binary: Base64.strict_encode64("binsecret")))

    expect(resolver.resolve("ref-2")).to eq("binsecret")
  end

  it "raises SecretNotFound on a blank ref without calling AWS" do
    expect(client).not_to receive(:get_secret_value)
    expect { resolver.resolve("") }.to raise_error(described_class::SecretNotFound)
  end

  it "wraps AWS service errors as SecretNotFound without leaking the value" do
    allow(client).to receive(:get_secret_value)
      .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, "missing"))

    expect { resolver.resolve("ref-3") }.to raise_error(described_class::SecretNotFound, /ref-3/)
  end
end
