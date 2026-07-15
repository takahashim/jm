# frozen_string_literal: true

module JM
  module Commands
    # Edit an item (SPEC 14.4). Bare `jm edit ID` opens the editor on the body;
    # --title/--type change metadata; --stdin/--message replace the body.
    # Title/body changes are snapshotted as revisions by the store (SPEC 17).
    class Edit < Command
      # Option key => item column for the scalar (non-body) fields edit can set.
      SCALAR_FIELDS = {
        title: "title", type: "type",
        completed_at: "completed_at", started_at: "started_at", archived_at: "archived_at"
      }.freeze

      private

      def perform(args)
        opts = {}
        rest = parse(args, opts)
        id = item_id(rest.shift)
        raise ArgError, "too many arguments" unless rest.empty?

        current = items.get(id)
        fields = build_fields(opts, current)
        raise ArgError, "nothing to edit" if fields.empty?

        row = items.update(id, fields)
        emit(row)
      end

      def parse(args, opts)
        parse_options(args) do |o|
          o.on("--title TITLE") { |v| opts[:title] = v }
          o.on("--type TYPE") { |v| opts[:type] = Parse.type(v) }
          # Correct a stored timestamp (SPEC 14.4). Unlike `done --at`, this
          # overwrites an existing value; state is left unchanged.
          o.on("--completed-at WHEN") { |v| opts[:completed_at] = Parse.at(v) }
          o.on("--started-at WHEN") { |v| opts[:started_at] = Parse.at(v) }
          o.on("--archived-at WHEN") { |v| opts[:archived_at] = Parse.at(v) }
          o.on("--message MSG") { |v| opts[:message] = v }
          o.on("--stdin") { opts[:stdin] = true }
        end
      end

      def build_fields(opts, current)
        fields = {}
        SCALAR_FIELDS.each { |opt, col| fields[col] = opts[opt] unless opts[opt].nil? }

        body_source = !opts[:message].nil? || opts[:stdin]
        anything = !fields.empty? || body_source

        if body_source
          fields["body"] = resolve_body(message: opts[:message], use_stdin: opts[:stdin])
        elsif !anything
          fields["body"] = editor.edit(current["body"].to_s)
        end
        fields
      end

      def emit(row)
        if @output.json?
          @output.json(ItemView.new(row).to_h)
        else
          @output.line("Updated #{PublicId.format(row["id"])}")
        end
      end
    end
  end
end
