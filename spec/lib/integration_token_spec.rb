require "rails_helper"

RSpec.describe IntegrationToken do
  let(:user_id) { SecureRandom.uuid }
  let(:secrets) { instance_double(Secrets) }

  it "resolves the plaintext token from the integration's secret ref" do
    create(:integration, user_id: user_id, provider: :github, token_secret_ref: "arn:gh")
    allow(secrets).to receive(:get).with("arn:gh").and_return("ghp_token")

    token = described_class.resolve(user_id: user_id, provider: :github, secrets: secrets)

    expect(token).to eq("ghp_token")
  end

  it "raises NotConnected when the provider has no integration row" do
    expect { described_class.resolve(user_id: user_id, provider: :linear, secrets: secrets) }
      .to raise_error(ProviderProxy::NotConnected)
  end

  it "is scoped to the user — another user's integration does not resolve" do
    create(:integration, user_id: SecureRandom.uuid, provider: :github)

    expect { described_class.resolve(user_id: user_id, provider: :github, secrets: secrets) }
      .to raise_error(ProviderProxy::NotConnected)
  end

  it "treats a vanished secret as a not-connected (reconnect) condition" do
    create(:integration, user_id: user_id, provider: :github, token_secret_ref: "arn:gone")
    allow(secrets).to receive(:get).with("arn:gone").and_raise(Secrets::NotFound, "gone")

    expect { described_class.resolve(user_id: user_id, provider: :github, secrets: secrets) }
      .to raise_error(ProviderProxy::NotConnected)
  end
end
