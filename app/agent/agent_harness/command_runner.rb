class AgentHarness
  # Runs a shell command and captures its output. The only process seam in the
  # harness, so specs stub this rather than shelling out. Secrets are passed via
  # `env` (child environment), never via argv, so they stay out of `ps`, logs,
  # and `.git/config`.
  class CommandRunner
    Result = Struct.new(:stdout, :stderr, :exit_status, keyword_init: true) do
      def success? = exit_status.zero?
    end

    def run(command, chdir: nil, env: {})
      opts = {}
      opts[:chdir] = chdir if chdir
      stdout, stderr, status = Open3.capture3(env, *command, **opts)
      Result.new(stdout: stdout, stderr: stderr, exit_status: status.exitstatus || 1)
    end

    def run!(command, chdir: nil, env: {})
      result = run(command, chdir: chdir, env: env)
      unless result.success?
        # Interpolate the command (never the env) — env carries the secrets.
        raise CommandFailed.new(command, result)
      end
      result
    end

    class CommandFailed < StandardError
      attr_reader :result

      def initialize(command, result)
        @result = result
        super("`#{Array(command).join(' ')}` exited #{result.exit_status}: #{result.stderr.to_s.strip}")
      end
    end
  end
end
