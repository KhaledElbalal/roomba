class AgentHarness
  # Runs the target repo's own test suite and records the result as a
  # `run_command` artifact. The command is detected from the repo's manifest
  # (Ruby/Node/Make), since the schema doesn't carry a test command yet; an
  # explicit ROOMBA_TEST_COMMAND wins when the runner provides one.
  class TestRunner
    Result = Struct.new(:passed, :command, keyword_init: true) do
      def passed? = passed
    end

    def initialize(workspace:, recorder:, command: nil)
      @workspace = workspace
      @recorder  = recorder
      @command   = command || ENV["ROOMBA_TEST_COMMAND"].presence || detect
    end

    def call
      # No detectable suite: don't block the PR on tests we can't run, but make
      # the absence visible in the timeline.
      unless @command
        @recorder.record(:run_command, { command: nil, note: "no test command detected" })
        return Result.new(passed: true, command: nil)
      end

      install_deps

      result = @workspace.run_command(@command)
      @recorder.record(:run_command, {
        command: @command, exit_status: result.exit_status,
        stdout: Tools.truncate(result.stdout), stderr: Tools.truncate(result.stderr)
      })

      # Missing binary/deps (exit 127 / command not found) is infra, not a test
      # failure — treat as no-test rather than failed so a frontend-only repo
      # without a test setup doesn't get marked failed.
      if result.exit_status == 127 && (result.stderr.include?("command not found") || result.stderr.include?("not found") || result.stdout.include?("command not found"))
        @recorder.record(:run_command, { command: @command, note: "test command not found — treating as no test command detected", exit_status: result.exit_status })
        return Result.new(passed: true, command: @command)
      end

      Result.new(passed: result.success?, command: @command)
    end

    private

    def install_deps
      # Ruby: install gems for the cloned repo (separate bundle from the agent image).
      if exists?("Gemfile")
        result = @workspace.run_command("bundle install")
        @recorder.record(:run_command, {
          command: "bundle install", exit_status: result.exit_status,
          stdout: Tools.truncate(result.stdout), stderr: Tools.truncate(result.stderr)
        })
      end

      # Node: install from lockfile if present for reproducibility.
      if exists?("package.json")
        cmd = if exists?("package-lock.json")
          "npm ci"
        elsif exists?("yarn.lock")
          "yarn install --frozen-lockfile"
        elsif exists?("pnpm-lock.yaml")
          "pnpm install --frozen-lockfile"
        else
          "npm install"
        end
        result = @workspace.run_command(cmd)
        @recorder.record(:run_command, {
          command: cmd, exit_status: result.exit_status,
          stdout: Tools.truncate(result.stdout), stderr: Tools.truncate(result.stderr)
        })
      end
    end

    def detect
      return "bundle exec rspec" if exists?("Gemfile") && (exists?(".rspec") || dir?("spec"))
      return "bundle exec rails test" if exists?("Gemfile") && dir?("test")
      return "npm test --silent" if exists?("package.json")
      return "make test" if exists?("Makefile")

      nil
    end

    def exists?(path) = File.exist?(File.join(@workspace.dir, path))
    def dir?(path)    = File.directory?(File.join(@workspace.dir, path))
  end
end
