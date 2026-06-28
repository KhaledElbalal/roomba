class RunQueue
  BACKENDS = {
    "db"  => -> { DbRunQueue.new },
    "sqs" => -> { SqsRunQueue.new }
  }.freeze

  def self.build
    key = ENV.fetch("QUEUE_BACKEND")
    factory = BACKENDS[key] or raise ArgumentError, "Unknown QUEUE_BACKEND: #{key.inspect}"
    factory.call
  end
end
