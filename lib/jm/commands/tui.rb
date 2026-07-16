# frozen_string_literal: true

module JM
  module Commands
    # `jm tui`: a read-only terminal viewer (SPEC 30). Interactive, so it needs a
    # TTY and the optional tui_tui gem; both are checked before launching.
    class Tui < Command
      private

      def perform(_args)
        raise ArgError, "jm tui requires an interactive terminal (TTY)" unless interactive?

        load_tui
        TUI::App.run(queries)
      end

      def interactive?
        @stdin.respond_to?(:tty?) && @stdin.tty? && $stdout.tty?
      end

      def load_tui
        require "tui_tui"
        require "jm/tui/app"
      rescue LoadError => e
        raise ArgError, "jm tui needs the tui_tui gem (#{e.message})"
      end
    end
  end
end
