require "rails_helper"
require "rake"

RSpec.describe "roomba:reap" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("roomba:reap")
    unless Rake::Task.task_defined?("roomba:reap")
      Rake::Task.define_task(:environment)
      load Rails.root.join("lib/tasks/roomba.rake")
    end
  end

  before do
    Rake::Task["roomba:reap"].reenable
    ENV.delete("REAP_GRACE_SECONDS")
  end

  def create_running_run(started_ago:, max_wall_clock_seconds:)
    create(:run, :running,
           started_at:           started_ago.ago,
           max_wall_clock_seconds: max_wall_clock_seconds)
  end

  it "flips a stale run to failed with a reason" do
    # started 2 hours ago, max 30 min → 30+5min grace < 2h → should be reaped
    stale = create_running_run(started_ago: 2.hours, max_wall_clock_seconds: 30.minutes.to_i)

    Rake::Task["roomba:reap"].invoke

    stale.reload
    expect(stale.status).to eq("failed")
    expect(stale.failure_reason).to match(/max_wall_clock_seconds/)
    expect(stale.finished_at).to be_within(5.seconds).of(Time.current)
  end

  it "does not touch a run still within its deadline" do
    # started 10 min ago, max 1 hour → still alive
    fresh = create_running_run(started_ago: 10.minutes, max_wall_clock_seconds: 1.hour.to_i)

    Rake::Task["roomba:reap"].invoke

    expect(fresh.reload.status).to eq("running")
  end

  it "does not touch a running run without max_wall_clock_seconds" do
    run = create(:run, :running, started_at: 3.hours.ago, max_wall_clock_seconds: nil)

    Rake::Task["roomba:reap"].invoke

    expect(run.reload.status).to eq("running")
  end

  it "respects REAP_GRACE_SECONDS from the environment" do
    # started 35 min ago, max 30 min; with 600s (10 min) grace → deadline = 30+10 = 40min → not yet
    ENV["REAP_GRACE_SECONDS"] = "600"
    borderline = create_running_run(started_ago: 35.minutes, max_wall_clock_seconds: 30.minutes.to_i)

    Rake::Task["roomba:reap"].invoke

    expect(borderline.reload.status).to eq("running")
  ensure
    ENV.delete("REAP_GRACE_SECONDS")
  end
end
