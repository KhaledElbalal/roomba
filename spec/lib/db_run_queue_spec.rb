require "rails_helper"

RSpec.describe DbRunQueue do
  subject(:queue) { DbRunQueue.new }

  describe "#enqueue" do
    it "is a no-op (run is already persisted in DB)" do
      run = create(:run, status: :queued)
      expect { queue.enqueue(run) }.not_to change { run.reload.status }
    end
  end

  describe "claim behavior (via #poll)" do
    it "claims the oldest queued run, marks it running, and stamps started_at" do
      _newer = create(:run, status: :queued, created_at: 1.minute.ago)
      oldest = create(:run, status: :queued, created_at: 5.minutes.ago)

      claimed = queue.send(:claim_next)

      expect(claimed.id).to eq(oldest.id)
      expect(oldest.reload.status).to eq("running")
      expect(oldest.reload.started_at).to be_within(2.seconds).of(Time.current)
    end

    it "returns nil when no queued runs exist" do
      create(:run, status: :running)
      expect(queue.send(:claim_next)).to be_nil
    end

    it "skips already-running runs (multi-worker safety)" do
      run_a = create(:run, status: :queued, created_at: 5.minutes.ago)
      run_b = create(:run, status: :queued, created_at: 1.minute.ago)

      first  = queue.send(:claim_next)
      second = queue.send(:claim_next)

      expect([first.id, second.id]).to contain_exactly(run_a.id, run_b.id)
      expect(first.id).not_to eq(second.id)
    end

    it "sets the in-memory status to running before yielding" do
      create(:run, status: :queued)
      claimed = queue.send(:claim_next)
      expect(claimed.status).to eq("running")
    end
  end
end
