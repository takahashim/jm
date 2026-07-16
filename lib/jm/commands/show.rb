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

        detail = queries.show(id)
        raise NotFound, "no such item: #{PublicId.format(id)}" if detail.nil?

        @output.json? ? emit_json(detail) : render_human(detail)
      end

      # The most recent entries, or all of them under --all.
      def visible_entries(all_entries)
        @all ? all_entries : all_entries.last(RECENT_ENTRIES)
      end

      def emit_json(detail)
        data = ItemView.new(detail["item"]).to_h.merge(
          "tags" => detail["tags"],
          "repositories" => detail["repositories"],
          "relations" => detail["relations"],
          "references" => detail["references"].map { |r| reference_hash(r) },
          "entries" => visible_entries(detail["entries"]).map { |e| entry_hash(e) }
        )
        @output.json(data)
      end

      def render_human(detail)
        ItemView.new(detail["item"]).render(@output)
        section("tags", detail["tags"].join(", ")) unless detail["tags"].empty?
        unless detail["repositories"].empty?
          section("repositories", detail["repositories"].join(", "))
        end
        render_relations(detail["relations"])
        render_references(detail["references"])
        render_entries(visible_entries(detail["entries"]), detail["entries"].length)
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
          name = queries.reference_repo_name(r)
          repo = name ? " @#{name}" : ""
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
        name = queries.reference_repo_name(row)
        h["repository"] = name if name
        h
      end

      def entry_hash(row)
        row.reject { |k, _| k.is_a?(Integer) }
      end
    end
  end
end
