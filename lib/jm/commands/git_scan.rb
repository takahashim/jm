# frozen_string_literal: true

module JM
  module Commands
    # `jm git scan --repo NAME` (SPEC 24.2). Scans a repository's recent commit
    # messages for JM-<id> references and attaches a commit Reference (full SHA)
    # to each existing item. Idempotent: re-scanning adds no duplicates.
    #
    # Named GitScan rather than Git so a bare `Git` in the Commands namespace
    # still resolves to the JM::Git helper module.
    class GitScan < Command
      # IDs are read only from a `Refs:`/`Ref:` trailer line (SPEC 24.2), so an
      # incidental JM-<id> in prose or an example is not linked.
      TRAILER = /\A[ \t]*refs?:[ \t]*(.+)/i
      ID_PATTERN = /\bJM-0*(\d+)\b/i
      DEFAULT_LIMIT = 100

      private

      def perform(args)
        sub = args.shift
        raise ArgError, "usage: jm git scan --repo NAME [--limit N]" unless sub == "scan"

        scan(args)
      end

      def scan(args)
        opts = { limit: DEFAULT_LIMIT }
        parse_options(args) do |o|
          o.on("--repo NAME") { |v| opts[:repo] = v }
          o.on("--limit N") { |v| opts[:limit] = positive_int(v) }
        end
        raise ArgError, "jm git scan requires --repo NAME" if opts[:repo].nil?

        repo = repos.get_by_name(opts[:repo])
        dir = repo["path"]
        raise ArgError, "repository #{repo["name"]} has no local path" if dir.nil?

        emit(link_commits(repo, dir, opts[:limit]))
      end

      def link_commits(repo, dir, limit)
        added = []
        Git.log(dir, limit: limit).each do |commit|
          item_ids_in(commit[:message]).each do |id|
            next unless items.exists?(id)
            next if refs.exists?(item_id: id, kind: "commit", value: commit[:sha],
                                 repository_id: repo["id"])

            refs.add(item_id: id, kind: "commit", value: commit[:sha], repository_id: repo["id"])
            added << { id: id, sha: commit[:sha] }
          end
        end
        added
      end

      def item_ids_in(message)
        numbers = message.to_s.each_line.flat_map { |line| ids_on_line(line) }
        numbers.map { |n| Integer(n, 10) }.uniq
      end

      def ids_on_line(line)
        m = line.match(TRAILER)
        m ? m[1].scan(ID_PATTERN).flatten : []
      end

      def positive_int(value)
        n = Integer(value, 10)
        raise ArgError, "--limit must be a positive integer" unless n.positive?

        n
      rescue ArgumentError
        raise ArgError, "invalid --limit: #{value}"
      end

      def emit(added)
        if @output.json?
          @output.json(added.map { |a| link_hash(a) }, list_key: "linked")
        elsif added.empty?
          @output.line("No new commit references.")
        else
          added.each { |a| @output.line("Linked #{a[:sha][0, 8]} -> #{PublicId.format(a[:id])}") }
          @output.line("Added #{added.length} commit reference(s).")
        end
      end

      def link_hash(added)
        { "item" => PublicId.format(added[:id]), "commit" => added[:sha] }
      end
    end
  end
end
