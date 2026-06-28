require "rails_helper"

RSpec.describe ProviderProxy::GithubRepos do
  let(:http) { instance_double(AgentHarness::LlmClient::HttpAdapter) }

  def http_response(klass, code, body, headers = {})
    klass.new("1.1", code, "").tap do |r|
      allow(r).to receive(:body).and_return(body)
      headers.each { |k, v| r[k] = v }
    end
  end

  it "maps the raw payload to the minimal picker shape" do
    payload = [
      { name: "roomba", full_name: "acme/roomba", default_branch: "main",
        private: true, owner: { id: 1 }, stargazers_count: 9 }
    ].to_json
    allow(http).to receive(:request).and_return(http_response(Net::HTTPOK, "200", payload))

    expect(described_class.call("ghp_good", http: http)).to eq([
      { name: "roomba", full_name: "acme/roomba", default_branch: "main", private: true }
    ])
  end

  it "raises a 502 provider error on a revoked token without echoing it" do
    allow(http).to receive(:request)
      .and_return(http_response(Net::HTTPUnauthorized, "401", "Bad credentials"))

    expect { described_class.call("ghp_revoked", http: http) }
      .to raise_error(ProviderProxy::Error, /GitHub rejected/) { |e|
        expect(e.status).to eq(:bad_gateway)
        expect(e.message).not_to include("ghp_revoked")
      }
  end

  it "maps a 403 with exhausted quota to a 429 rate-limit error" do
    allow(http).to receive(:request).and_return(
      http_response(Net::HTTPForbidden, "403", "rate limited", "x-ratelimit-remaining" => "0")
    )

    expect { described_class.call("ghp_x", http: http) }
      .to raise_error(ProviderProxy::Error) { |e| expect(e.status).to eq(:too_many_requests) }
  end

  it "maps an explicit 429 to a rate-limit error" do
    allow(http).to receive(:request)
      .and_return(http_response(Net::HTTPTooManyRequests, "429", "slow down"))

    expect { described_class.call("ghp_x", http: http) }
      .to raise_error(ProviderProxy::Error) { |e| expect(e.status).to eq(:too_many_requests) }
  end

  it "wraps transport failures as a 502 provider error" do
    allow(http).to receive(:request).and_raise(SocketError.new("getaddrinfo"))

    expect { described_class.call("ghp_x", http: http) }
      .to raise_error(ProviderProxy::Error, /could not reach GitHub/) { |e|
        expect(e.status).to eq(:bad_gateway)
      }
  end
end
