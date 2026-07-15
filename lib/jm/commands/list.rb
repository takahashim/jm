# frozen_string_literal: true

module JM
  module Commands
    # List items with filters (SPEC 14.5). Repo/tag/ready filters arrive in
    # later phases.
    class List < Command
      private

      def perform(args)
        opts = {}
        parse(args, opts)

        rows = items.list(
          states: resolve_states(opts),
          type: opts[:type],
          author: opts[:by],
          since: opts[:since],
          priority_min: opts[:priority_min],
          tag: opts[:tag],
          repo: opts[:repo],
          ready: opts[:ready] || false
        )

        emit(rows)
      end

      # rubocop:disable Metrics/AbcSize -- a flat list of option definitions
      def parse(args, opts)
        parse_options(args) do |o|
          o.on("--state STATE") { |v| opts[:state] = Parse.state(v) }
          o.on("--type TYPE") { |v| opts[:type] = Parse.type(v) }
          o.on("--archived") { opts[:archived] = true }
          o.on("--all") { opts[:all] = true }
          o.on("--ready") { opts[:ready] = true }
          o.on("--tag TAG") { |v| opts[:tag] = v }
          o.on("--repo NAME") { |v| opts[:repo] = v }
          o.on("--by NAME") { |v| opts[:by] = v }
          o.on("--since WHEN") { |v| opts[:since] = Parse.since(v) }
          o.on("--priority-min N") { |v| opts[:priority_min] = Parse.priority(v) }
        end
      end
      # rubocop:enable Metrics/AbcSize

      # Explicit --state wins; --all shows every state (including done/archived);
      # --archived shows archived; otherwise the default working set (SPEC 14.5).
      def resolve_states(opts)
        return [opts[:state]] if opts[:state]
        return nil if opts[:all] # nil => no state filter in the store
        return ["archived"] if opts[:archived]

        DEFAULT_LIST_STATES
      end

      def emit(rows)
        if @output.json?
          @output.json(rows.map { |r| ItemView.new(r).to_h }, list_key: "items")
        elsif rows.empty?
          @output.line("(no items)")
        else
          rows.each do |r|
            names = repos.for_item(r["id"]).map { |x| x["name"] }
            @output.line(ItemView.new(r).summary_line(repos: names))
          end
        end
      end
    end
  end
end
