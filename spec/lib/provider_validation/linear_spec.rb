require "rails_helper"

RSpec.describe ProviderValidation::Linear do
  let(:http) { instance_double(AgentHarness::LlmClient::HttpAdapter) }

  def http_response(klass, code, body)
    klass.new("1.1", code, "").tap { |r| allow(r).to receive(:body).and_return(body) }
  end

  it "returns the viewer metadata on a 200 with a viewer" do
    body = { data: { viewer: { id: "usr_1", name: "Ada" } } }.to_json
    allow(http).to receive(:request).and_return(http_response(Net::HTTPOK, "200", body))

    expect(described_class.call("lin_good", http: http)).to eq(user_id: "usr_1", name: "Ada")
  end

  it "sends the token raw in Authorization (no Bearer prefix)" do
    captured = nil
    allow(http).to receive(:request) do |_uri, req|
      captured = req["Authorization"]
      http_response(Net::HTTPOK, "200", { data: { viewer: { id: "1", name: "x" } } }.to_json)
    end

    described_class.call("lin_raw", http: http)
    expect(captured).to eq("lin_raw")
  end

  it "raises when the response has no viewer" do
    allow(http).to receive(:request)
      .and_return(http_response(Net::HTTPOK, "200", { data: { viewer: nil } }.to_json))

    expect { described_class.call("lin_bad", http: http) }
      .to raise_error(ProviderValidation::Error, /Linear rejected/)
  end

  it "raises on a non-success response" do
    allow(http).to receive(:request)
      .and_return(http_response(Net::HTTPUnauthorized, "401", "{}"))

    expect { described_class.call("lin_bad", http: http) }
      .to raise_error(ProviderValidation::Error, /Linear rejected/)
  end
end
