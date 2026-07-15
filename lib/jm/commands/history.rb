# frozen_string_literal: true

module JM
  module Commands
    # `jm history ID [--show REVISION_ID]`: list or display prior title/body
    # snapshots (SPEC 17.2). There is no restore command; copy back manually.
    class History < Command
      private

      def perform(args)
        show_id = nil
        rest = parse_options(args) { |o| o.on("--show REV", Integer) { |v| show_id = v } }
        id = item_id(rest.shift)
        raise ArgError, "too many arguments" unless rest.empty?

        items.get(id)
        show_id ? show_revision(id, show_id) : list_revisions(id)
      end

      def revisions
        @revisions ||= Store::Revisions.new(db)
      end

      def list_revisions(id)
        rows = revisions.for_item(id)
        if @output.json?
          @output.json(rows.map { |r| revision_summary(r) }, list_key: "revisions")
        elsif rows.empty?
          @output.line("(no revisions)")
        else
          rows.each { |r| @output.line("##{r["id"]}  #{r["created_at"]}  #{r["title"]}") }
        end
      end

      def show_revision(id, revision_id)
        row = revisions.get(id, revision_id)
        if @output.json?
          @output.json(revision_full(row))
        else
          @output.line("##{row["id"]}  #{row["created_at"]}")
          @output.line("title: #{row["title"]}")
          @output.line("")
          @output.line(row["body"].to_s.empty? ? "(no body)" : row["body"])
        end
      end

      def revision_summary(row)
        { "id" => row["id"], "created_at" => row["created_at"], "title" => row["title"] }
      end

      def revision_full(row)
        { "id" => row["id"], "created_at" => row["created_at"],
          "title" => row["title"], "body" => row["body"] }
      end
    end
  end
end
