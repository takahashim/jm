# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module JM
  # Owns the SQLite connection, PRAGMAs, and schema migrations (SPEC 18).
  #
  # Migration policy: only `jm init` / `jm migrate` mutate the schema. A normal
  # open verifies the version and refuses to run (exit 5) if migrations are
  # pending, so reads never silently rewrite the database.
  class Database
    MIGRATIONS_DIR = File.expand_path("migrations", __dir__)

    attr_reader :db, :path

    # Open for normal use. Raises DatabaseError if the DB is missing or behind.
    def self.open(path)
      new(path).tap(&:ensure_ready)
    end

    # Open and apply any pending migrations (used by `jm init` / `jm migrate`).
    def self.setup(path)
      new(path).tap(&:migrate!)
    end

    def initialize(path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      apply_pragmas
    end

    # Verify the schema is present and current; otherwise fail clearly.
    def ensure_ready
      unless table_exists?("schema_migrations") && pending_migrations.empty?
        raise DatabaseError,
              "database not initialized or out of date at #{@path}. Run `jm init`."
      end
      self
    end

    # Apply all pending migrations. Verifies FTS5/trigram first (SPEC 18.2).
    def migrate!
      verify_fts_available!
      ensure_migrations_table
      pending_migrations.each { |version, file| apply_migration(version, file) }
      self
    end

    # Run a block inside an IMMEDIATE transaction (SPEC 18.2).
    def transaction(&)
      @db.transaction(:immediate, &)
    end

    def get_meta(key)
      row = @db.get_first_row("SELECT value FROM meta WHERE key = ?", [key])
      row && row["value"]
    end

    def set_meta(key, value)
      @db.execute(
        "INSERT INTO meta(key, value) VALUES(?, ?) " \
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        [key, value]
      )
    end

    def close
      @db&.close
    end

    private

    def apply_pragmas
      @db.execute("PRAGMA foreign_keys = ON")
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA synchronous = NORMAL")
      @db.execute("PRAGMA busy_timeout = 5000")
    end

    # Probe the linked SQLite for FTS5 + trigram on a throwaway temp table so a
    # missing extension fails loudly at init rather than at first search.
    def verify_fts_available!
      @db.execute("CREATE VIRTUAL TABLE temp.__fts_probe USING fts5(x, tokenize='trigram')")
      @db.execute("DROP TABLE temp.__fts_probe")
    rescue SQLite3::Exception => e
      raise DatabaseError,
            "SQLite lacks FTS5 or the trigram tokenizer (#{e.message}). " \
            "jm requires an FTS5-enabled SQLite build."
    end

    def ensure_migrations_table
      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version TEXT PRIMARY KEY,
          applied_at TEXT NOT NULL
        )
      SQL
    end

    def applied_versions
      return [] unless table_exists?("schema_migrations")

      @db.execute("SELECT version FROM schema_migrations").map { |r| r["version"] }
    end

    # [[version, path], ...] sorted, for migrations not yet applied.
    def pending_migrations
      done = applied_versions
      all_migrations.reject { |migration| done.include?(migration.first) }
    end

    def all_migrations
      # Dir.glob returns sorted results, giving deterministic migration order.
      Dir.glob(File.join(MIGRATIONS_DIR, "*.sql")).filter_map do |file|
        m = File.basename(file).match(/\A(\d+)_/)
        m && [m[1], file]
      end
    end

    def apply_migration(version, file)
      sql = File.read(file)
      transaction do
        @db.execute_batch(sql)
        @db.execute(
          "INSERT INTO schema_migrations(version, applied_at) VALUES(?, ?)",
          [version, Clock.now]
        )
      end
    end

    def table_exists?(name)
      !@db.get_first_row(
        "SELECT 1 FROM sqlite_master WHERE type IN ('table','virtual') AND name = ?",
        [name]
      ).nil?
    end
  end
end
