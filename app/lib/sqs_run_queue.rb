class SqsRunQueue
  LONG_POLL_SECONDS = 20

  def initialize
    @client    = Aws::SQS::Client.new
    @queue_url = ENV.fetch("RUN_QUEUE_URL")
  end

  def enqueue(run)
    @client.send_message(
      queue_url:    @queue_url,
      message_body: JSON.generate(run_id: run.id)
    )
  end

  def poll
    loop do
      resp = @client.receive_message(
        queue_url:              @queue_url,
        max_number_of_messages: 1,
        wait_time_seconds:      LONG_POLL_SECONDS
      )
      resp.messages.each { |msg| process_message(msg) { |run| yield run } }
    end
  end

  private

  def process_message(msg)
    run_id = JSON.parse(msg.body).fetch("run_id")
    run    = Run.find(run_id)

    now = Time.current
    run.update_columns(status: "running", started_at: now)
    run.status     = "running"
    run.started_at = now

    yield run
    # delete only after the block succeeds, so a failure re-delivers via the visibility timeout
    @client.delete_message(queue_url: @queue_url, receipt_handle: msg.receipt_handle)
  end
end
