# frozen_string_literal: true

module JM
  module Commands
    # Print the bundled coding-agent guide (AGENTS.md). Ships with the gem so any
    # agent, in any project, can learn how to use jm via `jm guide` without
    # reading the source tree. Works without an initialized database.
    class Guide < Command
      GUIDE_PATH = File.expand_path("../../../AGENTS.md", __dir__)

      private

      def perform(_args)
        raise NotFound, "guide not found: #{GUIDE_PATH}" unless File.exist?(GUIDE_PATH)

        # Bypass --json/--quiet suppression: the guide is documentation and
        # should always print when explicitly requested.
        @output.stdout.puts(File.read(GUIDE_PATH))
      end
    end
  end
end
