require "rails_helper"

RSpec.describe ProviderProxy::LinearIssues do
  let(:http) { instance_double(AgentHarness::LlmClient::HttpAdapter) }

  def http_response(klass, code, body)
    klass.new("1.1", code, "").tap { |r| allow(r).to receive(:body).and_return(body) }
  end

  def issues_payload(nodes)
    { data: { issues: { nodes: nodes } } }.to_json
  end

  it "maps GraphQL nodes to the minimal picker shape (identifier -> code)" do
    nodes = [
      { id: "uuid-1", identifier: "ROO-5", title: "Auth", description: "do it",
        labels: { nodes: [ { name: "Feature" } ] } }
    ]
    allow(http).to receive(:request).and_return(http_response(Net::HTTPOK, "200", issues_payload(nodes)))

    expect(described_class.call("lin_good", http: http)).to eq([
      { id: "uuid-1", code: "ROO-5", title: "Auth", description: "do it", type: "feature" }
    ])
  end

  it "derives type 'bugfix' from a bug label and defaults to 'feature' otherwise" do
    nodes = [
      { id: "b", identifier: "ROO-9", title: "Crash", description: nil,
        labels: { nodes: [ { name: "Priority" }, { name: "Bug" } ] } },
      { id: "f", identifier: "ROO-7", title: "Add", description: nil,
        labels: { nodes: [] } }
    ]
    allow(http).to receive(:request).and_return(http_response(Net::HTTPOK, "200", issues_payload(nodes)))

    expect(described_class.call("lin_good", http: http).map { |i| i[:type] }).to eq(%w[bugfix feature])
  end

  it "sends the token raw, with no Bearer prefix" do
    sent = nil
    allow(http).to receive(:request) do |_uri, req|
      sent = req["Authorization"]
      http_response(Net::HTTPOK, "200", issues_payload([]))
    end

    described_class.call("lin_raw", http: http)
    expect(sent).to eq("lin_raw")
  end

  it "treats a 200 GraphQL errors array (revoked token) as a 502" do
    body = { errors: [ { message: "Authentication required" } ] }.to_json
    allow(http).to receive(:request).and_return(http_response(Net::HTTPOK, "200", body))

    expect { described_class.call("lin_revoked", http: http) }
      .to raise_error(ProviderProxy::Error, /Linear rejected/) { |e|
        expect(e.status).to eq(:bad_gateway)
        expect(e.message).not_to include("lin_revoked")
      }
  end

  it "maps a 429 to a rate-limit error" do
    allow(http).to receive(:request)
      .and_return(http_response(Net::HTTPTooManyRequests, "429", "slow down"))

    expect { described_class.call("lin_x", http: http) }
      .to raise_error(ProviderProxy::Error) { |e| expect(e.status).to eq(:too_many_requests) }
  end

  it "wraps transport failures as a 502 provider error" do
    allow(http).to receive(:request).and_raise(SocketError.new("getaddrinfo"))

    expect { described_class.call("lin_x", http: http) }
      .to raise_error(ProviderProxy::Error, /could not reach Linear/) { |e|
        expect(e.status).to eq(:bad_gateway)
      }
  end
end
