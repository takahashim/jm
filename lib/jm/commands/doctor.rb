# frozen_string_literal: true

module JM
  module Commands
    # Check database consistency (SPEC 14.15). v1 covers DB-internal checks only
    # (external path / file / git checks are deferred). `--rebuild-fts` rebuilds
    # the FTS indexes. Returns exit code 4 when problems are found.
    class Doctor
      def initialize(output:, config:, env: ENV, stdin: $stdin)
        @output = output
        @config = config
        @env = env
        @stdin = stdin
      end

      def run(args)
        rebuild = args.include?("--rebuild-fts")
        db = Database.open(@config.database_path)
        begin
          return rebuild_fts(db) if rebuild

          report(collect_problems(db))
        ensure
          db.close
        end
      end

      private

      def collect_problems(db)
        conn = db.db
        problems = []
        problems.concat(integrity_check(conn))
        problems.concat(foreign_key_check(conn))
        problems.concat(fts_integrity(conn))
        problems.concat(cycle_check(db))
        problems.concat(timestamp_checks(conn))
        problems
      end

      def integrity_check(conn)
        rows = conn.execute("PRAGMA integrity_check").map { |r| r["integrity_check"] }
        rows == ["ok"] ? [] : rows.map { |msg| "integrity: #{msg}" }
      end

      def foreign_key_check(conn)
        conn.execute("PRAGMA foreign_key_check").map do |r|
          "foreign_key: row in #{r["table"]} references missing #{r["parent"]}"
        end
      end

      def fts_integrity(conn)
        problems = []
        { "items_fts" => "items", "entries_fts" => "entries" }.each_key do |fts|
          conn.execute("INSERT INTO #{fts}(#{fts}) VALUES('integrity-check')")
        rescue SQLite3::Exception => e
          problems << "fts: #{fts} inconsistent (#{e.message}); run `jm doctor --rebuild-fts`"
        end
        problems
      end

      def cycle_check(db)
        nodes = Store::Relations.new(db).cycle_node_ids
        return [] if nodes.empty?

        ["depends_on: cycle involving #{nodes.map { |n| PublicId.format(n) }.join(", ")}"]
      end

      def timestamp_checks(conn)
        missing(conn, "done", "completed_at") + missing(conn, "active", "started_at")
      end

      # Items in `state` whose `column` timestamp is unexpectedly NULL.
      def missing(conn, state, column)
        conn.execute("SELECT id FROM items WHERE state = ? AND #{column} IS NULL", [state])
            .map { |r| "state: #{PublicId.format(r["id"])} is #{state} but has no #{column}" }
      end

      def rebuild_fts(db)
        db.db.execute("INSERT INTO items_fts(items_fts) VALUES('rebuild')")
        db.db.execute("INSERT INTO entries_fts(entries_fts) VALUES('rebuild')")
        if @output.json?
          @output.json({ "rebuilt" => true })
        else
          @output.line("Rebuilt FTS indexes.")
        end
        0
      end

      def report(problems)
        if @output.json?
          @output.json({ "ok" => problems.empty?, "problems" => problems })
        elsif problems.empty?
          @output.line("No problems found.")
        else
          @output.line("Found #{problems.length} problem(s):")
          problems.each { |p| @output.line("  - #{p}") }
        end
        problems.empty? ? 0 : 4
      end
    end
  end
end
