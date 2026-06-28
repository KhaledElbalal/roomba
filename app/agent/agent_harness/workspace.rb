class AgentHarness
  # A cloned checkout of the target repo plus the file/command operations the
  # loop drives. Git auth uses GIT_ASKPASS feeding the PAT through the child
  # environment, so the token never lands in argv, logs, or `.git/config`
  # (the remote URL keeps only the non-secret `x-access-token` username).
  class Workspace
    WORK_BRANCH_PREFIX = "roomba/run-".freeze

    attr_reader :dir, :repo, :branch

    def self.clone(repo:, pat:, run_id:, dir:, runner: CommandRunner.new)
      askpass = Askpass.write!(pat)
      url = "https://x-access-token@github.com/#{repo}.git"
      runner.run!([ "git", "clone", "--depth", "1", url, dir ], env: askpass.env)

      branch = "#{WORK_BRANCH_PREFIX}#{run_id}"
      runner.run!([ "git", "checkout", "-b", branch ], chdir: dir)
      new(repo: repo, dir: dir, branch: branch, askpass: askpass, runner: runner)
    end

    def initialize(repo:, dir:, branch:, askpass:, runner:)
      @repo    = repo
      @dir     = dir
      @branch  = branch
      @askpass = askpass
      @runner  = runner
    end

    def read_file(path)
      File.read(safe_path(path))
    end

    def write_file(path, content)
      full = safe_path(path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def run_command(command)
      # The model supplies a single command string; run it under a shell.
      @runner.run([ "bash", "-lc", command ], chdir: @dir)
    end

    def changes?
      !@runner.run!([ "git", "status", "--porcelain" ], chdir: @dir).stdout.strip.empty?
    end

    def commit_all(message)
      @runner.run!([ "git", "add", "-A" ], chdir: @dir)
      @runner.run!([ "git", "-c", "user.name=Roomba Agent",
                    "-c", "user.email=agent@roomba.dev",
                    "commit", "-m", message ], chdir: @dir)
    end

    def push
      @runner.run!([ "git", "push", "-u", "origin", @branch ], chdir: @dir, env: @askpass.env)
    end

    private

    # Block path traversal out of the checkout — the model's file paths are
    # untrusted input.
    def safe_path(path)
      full = File.expand_path(path, @dir)
      unless full == @dir || full.start_with?("#{@dir}/")
        raise ArgumentError, "path escapes workspace: #{path}"
      end
      full
    end

    # Tiny GIT_ASKPASS shim: git invokes it for the password prompt and it
    # echoes the PAT from its environment.
    class Askpass
      SCRIPT = "#!/bin/sh\nprintf '%s' \"$ROOMBA_GIT_PASSWORD\"\n".freeze

      def self.write!(pat)
        path = File.join(Dir.mktmpdir("roomba-askpass"), "askpass.sh")
        File.write(path, SCRIPT)
        File.chmod(0o700, path)
        new(path, pat)
      end

      def initialize(path, pat)
        @path = path
        @pat  = pat
      end

      def env
        { "GIT_ASKPASS" => @path, "ROOMBA_GIT_PASSWORD" => @pat, "GIT_TERMINAL_PROMPT" => "0" }
      end
    end
  end
end
