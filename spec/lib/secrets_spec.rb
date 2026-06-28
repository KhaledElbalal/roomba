require "rails_helper"

RSpec.describe Secrets do
  let(:client) { instance_double(Aws::SecretsManager::Client) }

  subject(:secrets) { described_class.new(client: client) }

  describe "#put" do
    it "creates a new secret by name and returns its ARN" do
      allow(client).to receive(:create_secret)
        .with(name: "roomba/x", secret_string: "tok")
        .and_return(double(arn: "arn:new"))

      expect(secrets.put(name: "roomba/x", value: "tok")).to eq("arn:new")
    end

    it "updates the value when the name already exists" do
      allow(client).to receive(:create_secret)
        .and_raise(Aws::SecretsManager::Errors::ResourceExistsException.new(nil, "exists"))
      allow(client).to receive(:put_secret_value)
        .with(secret_id: "roomba/x", secret_string: "tok")
        .and_return(double(arn: "arn:existing"))

      expect(secrets.put(name: "roomba/x", value: "tok")).to eq("arn:existing")
    end

    it "rotates in place when given a ref, keeping the same ARN" do
      expect(client).not_to receive(:create_secret)
      allow(client).to receive(:put_secret_value)
        .with(secret_id: "arn:keep", secret_string: "rotated")
        .and_return(double(arn: "arn:keep"))

      expect(secrets.put(ref: "arn:keep", value: "rotated")).to eq("arn:keep")
    end

    it "raises without a name or ref" do
      expect { secrets.put(value: "tok") }.to raise_error(ArgumentError)
    end
  end

  describe "#get" do
    it "returns the secret string" do
      allow(client).to receive(:get_secret_value)
        .with(secret_id: "arn:1")
        .and_return(double(secret_string: "tok", secret_binary: nil))

      expect(secrets.get("arn:1")).to eq("tok")
    end

    it "raises NotFound on a blank ref without calling AWS" do
      expect(client).not_to receive(:get_secret_value)
      expect { secrets.get("") }.to raise_error(Secrets::NotFound)
    end

    it "wraps a missing secret as NotFound and names the ref, not the value" do
      allow(client).to receive(:get_secret_value)
        .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, "gone"))

      expect { secrets.get("arn:missing") }.to raise_error(Secrets::NotFound, /arn:missing/)
    end
  end

  describe "#delete" do
    it "force-deletes the secret by ref" do
      expect(client).to receive(:delete_secret)
        .with(secret_id: "arn:1", force_delete_without_recovery: true)

      secrets.delete("arn:1")
    end

    it "is a no-op on a blank ref" do
      expect(client).not_to receive(:delete_secret)
      expect(secrets.delete(nil)).to be_nil
    end

    it "swallows an already-deleted secret (idempotent)" do
      allow(client).to receive(:delete_secret)
        .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, "gone"))

      expect { secrets.delete("arn:gone") }.not_to raise_error
    end
  end
end
