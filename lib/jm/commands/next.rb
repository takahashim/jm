# frozen_string_literal: true

module JM
  module Commands
    # `jm next` selects one ready item: highest priority, then oldest, then
    # lowest id (SPEC 14.13). --start moves it to active; otherwise state is
    # left unchanged.
    class Next < Command
      private

      def perform(args)
        opts = {}
        parse_options(args) do |o|
          o.on("--repo NAME") { |v| opts[:repo] = v }
          o.on("--start") { opts[:start] = true }
        end

        row = items.list(ready: true, repo: opts[:repo], order: :next, limit: 1).first
        return emit_empty if row.nil?

        row = items.set_state(row["id"], "active") if opts[:start]
        emit(row)
      end

      def emit_empty
        if @output.json?
          @output.json({ "item" => nil })
        else
          @output.line("(nothing ready)")
        end
        3
      end

      def emit(row)
        if @output.json?
          @output.json(ItemView.new(row).to_h)
        else
          ItemView.new(row).render(@output)
        end
      end
    end
  end
end
