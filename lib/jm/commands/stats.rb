# frozen_string_literal: true

module JM
  module Commands
    # `jm stats`: per-state counts and the ready count (SPEC 14.14).
    class Stats < Command
      private

      def perform(_args)
        counts = items.stats
        if @output.json?
          @output.json(counts)
        else
          render(counts)
        end
      end

      def render(counts)
        STATES.each { |s| @output.line(format("%-9s %5d", "#{s.capitalize}:", counts[s])) }
        @output.line("")
        @output.line(format("%-9s %5d", "Ready:", counts["ready"]))
      end
    end
  end
end
