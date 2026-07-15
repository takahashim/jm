# frozen_string_literal: true

require "jm/commands/init"
require "jm/commands/doctor"
require "jm/commands/add"
require "jm/commands/show"
require "jm/commands/list"
require "jm/commands/edit"
require "jm/commands/state_change"
require "jm/commands/priority"
require "jm/commands/log"
require "jm/commands/relation_commands"
require "jm/commands/tag"
require "jm/commands/repo"
require "jm/commands/ref"
require "jm/commands/search"
require "jm/commands/next"
require "jm/commands/stats"
require "jm/commands/backup"
require "jm/commands/delete"
require "jm/commands/history"
require "jm/commands/guide"

module JM
  # Parses global options, builds the shared Output/Config, dispatches to a
  # command, and maps errors to exit codes (SPEC 14, 22).
  class CLI
    COMMANDS = {
      "init" => Commands::Init,
      "doctor" => Commands::Doctor,
      "add" => Commands::Add,
      "show" => Commands::Show,
      "list" => Commands::List,
      "edit" => Commands::Edit,
      "inbox" => Commands::Inbox,
      "open" => Commands::Open,
      "start" => Commands::Start,
      "block" => Commands::Block,
      "done" => Commands::Done,
      "archive" => Commands::Archive,
      "priority" => Commands::Priority,
      "log" => Commands::Log,
      "link" => Commands::Link,
      "unlink" => Commands::Unlink,
      "links" => Commands::Links,
      "tag" => Commands::Tag,
      "repo" => Commands::Repo,
      "ref" => Commands::Ref,
      "search" => Commands::Search,
      "next" => Commands::Next,
      "stats" => Commands::Stats,
      "backup" => Commands::Backup,
      "delete" => Commands::Delete,
      "history" => Commands::History,
      "guide" => Commands::Guide
    }.freeze

    def self.run(argv, env: ENV, stdout: $stdout, stderr: $stderr, stdin: $stdin)
      new(env: env, stdout: stdout, stderr: stderr, stdin: stdin).run(argv)
    end

    def initialize(env: ENV, stdout: $stdout, stderr: $stderr, stdin: $stdin)
      @env = env
      @stdout = stdout
      @stderr = stderr
      @stdin = stdin
    end

    def run(argv)
      args = argv.dup
      globals = extract_global_flags!(args)
      command_name = args.shift

      output = Output.new(
        stdout: @stdout, stderr: @stderr,
        json: globals[:json], quiet: globals[:quiet], color: globals[:color]
      )

      return usage(output) if command_name.nil?

      klass = COMMANDS[command_name]
      raise ArgError, "unknown command: #{command_name}" if klass.nil?

      config = Config.load(env: @env)
      command = klass.new(output: output, config: config, env: @env, stdin: @stdin)
      result = command.run(args)
      result.is_a?(Integer) ? result : 0
    rescue JM::Error => e
      output.error(e.message)
      e.exit_code
    rescue SQLite3::Exception => e
      output.error("database error: #{e.message}")
      5
    end

    private

    # Pull recognized global flags out of args, leaving command-specific ones.
    def extract_global_flags!(args)
      globals = { json: false, quiet: false, color: nil }
      args.reject! do |arg|
        case arg
        when "--json" then globals[:json] = true
        when "--quiet" then globals[:quiet] = true
        when "--no-color" then globals[:color] = false
        else next false
        end
        true
      end
      globals
    end

    def usage(output)
      output.line("usage: jm <command> [arguments] [options]")
      output.line("commands: #{COMMANDS.keys.sort.join(", ")}")
      2
    end
  end
end
