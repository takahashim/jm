# frozen_string_literal: true

module JM
  module Commands
    # Append a time-ordered Entry to an item (SPEC 7, 14.7).
    class Log < Command
      private

      def perform(args)
        opts = { kind: "comment" }
        rest = parse(args, opts)
        id = item_id(rest.shift)
        raise ArgError, "too many arguments" unless rest.empty?

        items.get(id)
        body = resolve_body(message: opts[:message], use_stdin: opts[:stdin], editor_seed: "")
        raise ArgError, "empty entry; nothing logged" if body.strip.empty?

        entry_id = entries.create(
          item_id: id, kind: opts[:kind], body: body, author: author(opts[:by])
        )
        emit(id, entry_id, opts[:kind])
      end

      def parse(args, opts)
        parse_options(args) do |o|
          o.on("--kind KIND") { |v| opts[:kind] = v }
          o.on("--message MSG") { |v| opts[:message] = v }
          o.on("--stdin") { opts[:stdin] = true }
          o.on("--by NAME") { |v| opts[:by] = v }
        end
      end

      def emit(item_id, entry_id, kind)
        if @output.json?
          @output.json({ "item" => PublicId.format(item_id), "entry_id" => entry_id,
                         "kind" => kind })
        else
          @output.line("Logged #{kind} entry ##{entry_id} on #{PublicId.format(item_id)}")
        end
      end
    end
  end
end
