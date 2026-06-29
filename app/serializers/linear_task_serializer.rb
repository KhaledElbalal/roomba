class LinearTaskSerializer
  ATTRIBUTES = %i[id code name description task_type synced_at].freeze

  def initialize(task)
    @task = task
  end

  def as_json
    return nil if @task.nil?
    ATTRIBUTES.each_with_object({}) { |attr, memo| memo[attr] = @task.public_send(attr) }
  end
end
