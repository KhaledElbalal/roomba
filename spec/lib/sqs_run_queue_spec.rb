require "rails_helper"

RSpec.describe SqsRunQueue do
  let(:sqs_client) { instance_double(Aws::SQS::Client) }
  let(:queue_url)  { "https://sqs.us-east-1.amazonaws.com/123/roomba-test" }

  around do |example|
    saved = ENV["SQS_QUEUE_URL"]
    ENV["SQS_QUEUE_URL"] = queue_url
    example.run
  ensure
    saved.nil? ? ENV.delete("SQS_QUEUE_URL") : ENV["SQS_QUEUE_URL"] = saved
  end

  before { allow(Aws::SQS::Client).to receive(:new).and_return(sqs_client) }

  subject(:queue) { SqsRunQueue.new }

  describe "#enqueue" do
    it "sends the run id as a JSON message to SQS" do
      run = create(:run)
      allow(sqs_client).to receive(:send_message)

      queue.enqueue(run)

      expect(sqs_client).to have_received(:send_message).with(
        queue_url:    queue_url,
        message_body: JSON.generate(run_id: run.id)
      )
    end
  end

  describe "#poll" do
    let(:run) { create(:run, status: :queued) }
    let(:receipt_handle) { "receipt-abc-123" }
    let(:sqs_message) do
      instance_double(
        Aws::SQS::Types::Message,
        body:           JSON.generate(run_id: run.id),
        receipt_handle: receipt_handle
      )
    end
    let(:sqs_response_with_message) do
      instance_double(Aws::SQS::Types::ReceiveMessageResult, messages: [ sqs_message ])
    end

    before do
      # First poll returns a message; second raises StopIteration to exit the loop
      call_count = 0
      allow(sqs_client).to receive(:receive_message) do
        call_count += 1
        call_count == 1 ? sqs_response_with_message : raise(StopIteration)
      end
      allow(sqs_client).to receive(:delete_message)
    end

    it "marks the run as running and stamps started_at before yielding" do
      yielded = nil
      queue.poll { |r| yielded = r }

      expect(yielded.id).to eq(run.id)
      expect(run.reload.status).to eq("running")
      expect(run.reload.started_at).to be_within(2.seconds).of(Time.current)
    end

    it "deletes the SQS message after the block succeeds" do
      queue.poll { |_r| }

      expect(sqs_client).to have_received(:delete_message).with(
        queue_url:      queue_url,
        receipt_handle: receipt_handle
      )
    end

    it "does not delete the SQS message when the block raises" do
      expect {
        queue.poll { |_r| raise "agent failure" }
      }.to raise_error("agent failure")

      expect(sqs_client).not_to have_received(:delete_message)
    end
  end
end
