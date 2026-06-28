require "rails_helper"

RSpec.describe RunQueue do
  describe ".build" do
    around do |example|
      saved = { "QUEUE_BACKEND" => ENV["QUEUE_BACKEND"], "SQS_QUEUE_URL" => ENV["SQS_QUEUE_URL"] }
      example.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    context "when QUEUE_BACKEND=db" do
      before { ENV["QUEUE_BACKEND"] = "db" }

      it "returns a DbRunQueue" do
        expect(RunQueue.build).to be_a(DbRunQueue)
      end
    end

    context "when QUEUE_BACKEND=sqs" do
      before do
        ENV["QUEUE_BACKEND"] = "sqs"
        ENV["SQS_QUEUE_URL"] = "https://sqs.us-east-1.amazonaws.com/123/test"
        allow(Aws::SQS::Client).to receive(:new).and_return(instance_double(Aws::SQS::Client))
      end

      it "returns a SqsRunQueue" do
        expect(RunQueue.build).to be_a(SqsRunQueue)
      end
    end

    context "when QUEUE_BACKEND is an unknown value" do
      before { ENV["QUEUE_BACKEND"] = "kafka" }

      it "raises ArgumentError" do
        expect { RunQueue.build }.to raise_error(ArgumentError, /Unknown QUEUE_BACKEND/)
      end
    end
  end
end
