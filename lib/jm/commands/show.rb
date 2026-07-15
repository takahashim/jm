# frozen_string_literal: true

module JM
  module Commands
    # Display one item with its associations (SPEC 14.3). By default only the
    # most recent entries are shown; --all shows every entry.
    class Show < Command
      RECENT_ENTRIES = 5

      private

      def perform(args)
        rest = parse_options(args) { |o| o.on("--all") { @all = true } }
        id = item_id(rest.shift)
        raise ArgError, "too many arguments" unless rest.empty?

        row = items.get(id)
        assoc = gather(id)
        @output.json? ? emit_json(row, assoc) : render_human(row, assoc)
      end

      def gather(id)
        entry_rows = entries.for_item(id)
        {
          tags: tags.for_item(id),
          repositories: repos.for_item(id).map { |r| r["name"] },
          relations: relations.described_for(id).map { |e| relation_view(e) },
          references: refs.list(id),
          entries: @all ? entry_rows : entry_rows.last(RECENT_ENTRIES),
          entry_total: entry_rows.length
        }
      end

      def relation_view(edge)
        { "relation" => edge["relation"], "id" => PublicId.format(edge["other_id"]),
          "title" => items.get(edge["other_id"])["title"] }
      end

      def emit_json(row, assoc)
        data = ItemView.new(row).to_h.merge(
          "tags" => assoc[:tags],
          "repositories" => assoc[:repositories],
          "relations" => assoc[:relations],
          "references" => assoc[:references].map { |r| reference_hash(r) },
          "entries" => assoc[:entries].map { |e| entry_hash(e) }
        )
        @output.json(data)
      end

      def render_human(row, assoc)
        ItemView.new(row).render(@output)
        section("tags", assoc[:tags].join(", ")) unless assoc[:tags].empty?
        section("repositories", assoc[:repositories].join(", ")) unless assoc[:repositories].empty?
        render_relations(assoc[:relations])
        render_references(assoc[:references])
        render_entries(assoc[:entries], assoc[:entry_total])
      end

      def render_relations(relations)
        return if relations.empty?

        @output.line("")
        @output.line("relations:")
        relations.each { |e| @output.line("  #{e["relation"]} #{e["id"]}  #{e["title"]}") }
      end

      def render_references(references)
        return if references.empty?

        @output.line("")
        @output.line("references:")
        references.each do |r|
          repo = r["repository_id"] ? " @#{repos.get(r["repository_id"])["name"]}" : ""
          @output.line("  ##{r["id"]} #{r["kind"]} #{r["value"]}#{repo}")
        end
      end

      def render_entries(entries, total)
        return if entries.empty?

        @output.line("")
        shown = entries.length
        suffix = shown < total ? " (showing #{shown} of #{total}, --all for more)" : ""
        @output.line("entries:#{suffix}")
        entries.each do |e|
          author = e["created_by"] ? " <#{e["created_by"]}>" : ""
          @output.line("  [#{e["created_at"]}] #{e["kind"]}#{author}")
          e["body"].to_s.each_line { |l| @output.line("    #{l.chomp}") }
        end
      end

      def section(label, value)
        @output.line("#{label}: #{value}")
      end

      def reference_hash(row)
        h = row.reject { |k, _| k.is_a?(Integer) }
        h["repository"] = repos.get(row["repository_id"])["name"] if row["repository_id"]
        h
      end

      def entry_hash(row)
        row.reject { |k, _| k.is_a?(Integer) }
      end
    end
  end
end
