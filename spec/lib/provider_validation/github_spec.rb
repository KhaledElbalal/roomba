require "rails_helper"

RSpec.describe ProviderValidation::Github do
  let(:http) { instance_double(AgentHarness::LlmClient::HttpAdapter) }

  def http_response(klass, code, body)
    klass.new("1.1", code, "").tap { |r| allow(r).to receive(:body).and_return(body) }
  end

  it "returns the login metadata on a 200" do
    allow(http).to receive(:request)
      .and_return(http_response(Net::HTTPOK, "200", { login: "octocat", id: 42 }.to_json))

    expect(described_class.call("ghp_good", http: http)).to eq(login: "octocat", account_id: 42)
  end

  it "raises a surfaced error on a 401 without echoing the token" do
    allow(http).to receive(:request)
      .and_return(http_response(Net::HTTPUnauthorized, "401", "Bad credentials"))

    expect { described_class.call("ghp_bad", http: http) }
      .to raise_error(ProviderValidation::Error, /GitHub rejected/)
  end

  it "wraps transport failures as a validation error" do
    allow(http).to receive(:request).and_raise(SocketError.new("getaddrinfo"))

    expect { described_class.call("ghp_x", http: http) }
      .to raise_error(ProviderValidation::Error, /could not reach GitHub/)
  end
end
