# frozen_string_literal: true

module JM
  module Commands
    # Shared implementation for the state-transition commands (SPEC 14.6):
    # open / start / block / done / archive. Subclasses declare their target
    # state and which options apply.
    class StateChange < Command
      class << self
        attr_accessor :target_state, :accepts_resolution, :accepts_reason
      end

      private

      def perform(args)
        opts = {}
        rest = parse(args, opts)
        id = item_id(rest.shift)
        raise ArgError, "too many arguments" unless rest.empty?

        items.get(id) # existence check with a clear error before mutating
        row = items.set_state(id, self.class.target_state, resolution: opts[:resolution])
        add_reason_entry(id, opts) if opts[:reason]
        emit(row)
      end

      def parse(args, opts)
        parse_options(args) do |o|
          o.on("--resolution R") { |v| opts[:resolution] = v } if self.class.accepts_resolution
          o.on("--reason R") { |v| opts[:reason] = v } if self.class.accepts_reason
          o.on("--by NAME") { |v| opts[:by] = v }
        end
      end

      def add_reason_entry(id, opts)
        entries.create(
          item_id: id, kind: "comment", body: opts[:reason], author: author(opts[:by])
        )
      end

      def emit(row)
        if @output.json?
          @output.json(ItemView.new(row).to_h)
        else
          @output.line("#{row["state"]} #{PublicId.format(row["id"])}")
        end
      end
    end

    class Open < StateChange
      self.target_state = "open"
    end

    class Start < StateChange
      self.target_state = "active"
    end

    class Block < StateChange
      self.target_state = "blocked"
      self.accepts_reason = true
    end

    class Done < StateChange
      self.target_state = "done"
      self.accepts_resolution = true
    end

    class Archive < StateChange
      self.target_state = "archived"
      self.accepts_resolution = true
    end
  end
end
