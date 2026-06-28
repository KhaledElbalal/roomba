require "rails_helper"

RSpec.describe LlmKeyValidator do
  let(:http) { instance_double(AgentHarness::LlmClient::HttpAdapter) }

  def http_response(klass, code, body = "")
    klass.new("1.1", code, "").tap { |r| allow(r).to receive(:body).and_return(body) }
  end

  it "passes when the models endpoint returns 200" do
    captured = nil
    allow(http).to receive(:request) do |uri, _req|
      captured = uri.to_s
      http_response(Net::HTTPOK, "200")
    end

    expect(described_class.call(base_url: "https://api.openai.com/v1", api_key: "sk-good", http: http)).to be(true)
    expect(captured).to eq("https://api.openai.com/v1/models")
  end

  it "accepts without a network call when base_url is blank" do
    expect(http).not_to receive(:request)
    expect(described_class.call(base_url: nil, api_key: "sk-x", http: http)).to be(true)
  end

  it "raises a validation error on a rejected key" do
    allow(http).to receive(:request).and_return(http_response(Net::HTTPUnauthorized, "401"))

    expect { described_class.call(base_url: "https://api.openai.com/v1", api_key: "sk-bad", http: http) }
      .to raise_error(ProviderValidation::Error, /rejected the API key/)
  end
end
