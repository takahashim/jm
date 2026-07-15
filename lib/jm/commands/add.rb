# frozen_string_literal: true

module JM
  module Commands
    # Create an item (SPEC 14.2). Fast path: `jm add "title"`. With no title and
    # a TTY, the editor opens and its first non-empty line becomes the title.
    class Add < Command
      private

      def perform(args)
        opts = { type: DEFAULT_TYPE, state: DEFAULT_STATE, priority: DEFAULT_PRIORITY }
        apply_defaults(opts)
        rest = parse(args, opts)

        title = rest.shift
        raise ArgError, "too many arguments" unless rest.empty?

        title, body = resolve_title_and_body(title, opts)
        row = items.create(
          type: opts[:type], title: title, body: body,
          state: opts[:state], priority: opts[:priority], author: author(opts[:by])
        )

        emit(row)
      end

      def apply_defaults(opts)
        d = @config.defaults
        opts[:type] = d["type"] if d["type"]
        opts[:state] = d["state"] if d["state"]
        opts[:priority] = d["priority"] if d["priority"]
      end

      def parse(args, opts)
        parse_options(args) do |o|
          o.on("--type TYPE") { |v| opts[:type] = Parse.type(v) }
          o.on("--state STATE") { |v| opts[:state] = Parse.state(v) }
          o.on("--priority P") { |v| opts[:priority] = Parse.priority(v) }
          o.on("--message MSG") { |v| opts[:message] = v }
          o.on("--stdin") { opts[:stdin] = true }
          o.on("--by NAME") { |v| opts[:by] = v }
        end
      end

      # Title from the positional arg, or extracted from editor input; body from
      # --message/--stdin, or the editor when no title was given.
      def resolve_title_and_body(title, opts)
        has_body_source = !opts[:message].nil? || opts[:stdin]

        if title
          body = has_body_source ? read_body(opts) : ""
          [ensure_title(title), body]
        else
          raise ArgError, "title required with --message/--stdin" if has_body_source

          split_editor_content(editor.edit(""))
        end
      end

      def read_body(opts)
        resolve_body(message: opts[:message], use_stdin: opts[:stdin])
      end

      def split_editor_content(content)
        lines = content.to_s.lines
        idx = lines.index { |l| !l.strip.empty? }
        raise ArgError, "empty item; nothing created" if idx.nil?

        title = lines[idx].strip
        body = lines[(idx + 1)..].join.strip
        [title, body]
      end

      def ensure_title(title)
        stripped = title.to_s.strip
        raise ArgError, "title must not be empty" if stripped.empty?

        stripped
      end

      def emit(row)
        if @output.json?
          @output.json(ItemView.new(row).to_h)
        else
          @output.line("Created #{PublicId.format(row["id"])}")
        end
      end
    end
  end
end
