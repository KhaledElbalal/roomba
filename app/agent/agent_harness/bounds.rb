class AgentHarness
  # Hard stops for the edit loop. The three bounds map 1:1 to the run columns
  # (`max_iterations`, `max_wall_clock_seconds`, `max_cost_usd`); any nil bound
  # is treated as unbounded. `breach` returns the first tripped reason as a
  # symbol (matching the run's `failure_reason` vocabulary) or nil to continue.
  class Bounds
    REASONS = %i[max_iterations max_wall_clock_seconds max_cost_usd].freeze

    def self.from(run, clock: default_clock)
      new(
        max_iterations:         run.max_iterations,
        max_wall_clock_seconds: run.max_wall_clock_seconds,
        max_cost_usd:           run.max_cost_usd,
        clock:                  clock
      )
    end

    def self.default_clock
      -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    end

    def initialize(max_iterations:, max_wall_clock_seconds:, max_cost_usd:, clock: self.class.default_clock)
      @max_iterations         = max_iterations
      @max_wall_clock_seconds = max_wall_clock_seconds
      @max_cost_usd           = max_cost_usd
      @clock                  = clock
    end

    def start!
      @started_at = @clock.call
      self
    end

    # Checked at the top of each iteration, before spending on the next model
    # call, so an exhausted bound stops the loop instead of overrunning it.
    def breach(iteration:, cost_usd:)
      return :max_iterations if @max_iterations && iteration >= @max_iterations
      return :max_wall_clock_seconds if wall_clock_exceeded?
      return :max_cost_usd if @max_cost_usd && cost_usd >= @max_cost_usd

      nil
    end

    private

    def wall_clock_exceeded?
      return false unless @max_wall_clock_seconds && @started_at

      (@clock.call - @started_at) >= @max_wall_clock_seconds
    end
  end
end
