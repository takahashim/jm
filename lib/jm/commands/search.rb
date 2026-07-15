# frozen_string_literal: true

module JM
  module Commands
    # `jm search QUERY` over title/body/entries with list-style filters
    # (SPEC 14.8). Quote the argument for a phrase search.
    class Search < Command
      private

      def perform(args)
        opts = {}
        rest = parse(args, opts)
        query = rest.join(" ").strip
        raise ArgError, "usage: jm search QUERY [filters]" if query.empty?

        rows = search.run(
          query, type: opts[:type], states: opts[:state] && [opts[:state]],
                 tag: opts[:tag], repo: opts[:repo]
        )
        emit(rows)
      end

      def parse(args, opts)
        parse_options(args) do |o|
          o.on("--type TYPE") { |v| opts[:type] = Parse.type(v) }
          o.on("--state STATE") { |v| opts[:state] = Parse.state(v) }
          o.on("--tag TAG") { |v| opts[:tag] = v }
          o.on("--repo NAME") { |v| opts[:repo] = v }
        end
      end

      def search
        @search ||= Store::Search.new(db)
      end

      def emit(rows)
        if @output.json?
          @output.json(rows.map { |r| ItemView.new(r).to_h }, list_key: "items")
        elsif rows.empty?
          @output.line("(no matches)")
        else
          rows.each { |r| @output.line(ItemView.new(r).summary_line) }
        end
      end
    end
  end
end
