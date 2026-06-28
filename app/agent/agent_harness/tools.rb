class AgentHarness
  # The function-calling tools exposed to the model, plus the dispatcher that
  # executes one tool call against the workspace and records its artifact. Each
  # executed tool emits exactly one artifact (read_file/edit_file/run_command),
  # so steps replay in order. `finish` is the model's signal to stop iterating.
  module Tools
    SCHEMA = [
      {
        type: "function",
        function: {
          name: "read_file",
          description: "Read a UTF-8 text file from the repository.",
          parameters: {
            type: "object",
            properties: { path: { type: "string" } },
            required: [ "path" ]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "edit_file",
          description: "Overwrite (or create) a file with the given full contents.",
          parameters: {
            type: "object",
            properties: { path: { type: "string" }, content: { type: "string" } },
            required: [ "path", "content" ]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "run_command",
          description: "Run a shell command in the repository root and return its output.",
          parameters: {
            type: "object",
            properties: { command: { type: "string" } },
            required: [ "command" ]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "finish",
          description: "Call when the task is complete and ready for tests.",
          parameters: {
            type: "object",
            properties: { summary: { type: "string" } },
            required: [ "summary" ]
          }
        }
      }
    ].freeze

    FINISH = "finish".freeze

    Outcome = Struct.new(:content, :finished, keyword_init: true)

    # Executes one tool call, records its artifact, and returns the string fed
    # back to the model as the tool result. Returns nil for `finish` (the loop
    # checks the name to terminate).
    def self.dispatch(name:, arguments:, workspace:, recorder:)
      args = arguments.is_a?(String) ? JSON.parse(arguments.presence || "{}") : arguments

      case name
      when "read_file"
        content = workspace.read_file(args.fetch("path"))
        recorder.record(:read_file, { path: args["path"], bytes: content.bytesize })
        content
      when "edit_file"
        workspace.write_file(args.fetch("path"), args.fetch("content"))
        recorder.record(:edit_file, { path: args["path"], bytes: args["content"].to_s.bytesize })
        "wrote #{args['path']}"
      when "run_command"
        result = workspace.run_command(args.fetch("command"))
        recorder.record(:run_command, {
          command: args["command"], exit_status: result.exit_status,
          stdout: truncate(result.stdout), stderr: truncate(result.stderr)
        })
        "exit=#{result.exit_status}\n#{truncate(result.stdout)}#{truncate(result.stderr)}"
      when FINISH
        recorder.record(:thinking, { summary: args["summary"] })
        nil
      else
        "unknown tool: #{name}"
      end
    rescue ArgumentError, KeyError, JSON::ParserError, Errno::ENOENT => e
      # Surface the error to the model instead of crashing the run — it can retry.
      "error: #{e.message}"
    end

    MAX_OUTPUT = 4_000

    def self.truncate(text)
      str = text.to_s
      str.bytesize > MAX_OUTPUT ? "#{str.byteslice(0, MAX_OUTPUT)}…[truncated]" : str
    end
  end
end
