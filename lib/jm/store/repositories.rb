# frozen_string_literal: true

module JM
  module Store
    # Data access for repositories and their item associations (SPEC 8).
    class Repositories
      def initialize(database)
        @database = database
        @db = database.db
      end

      def create(name:, path: nil, remote_url: nil, default_branch: nil)
        now = Clock.now
        @db.execute(
          "INSERT INTO repositories(name, path, remote_url, default_branch, " \
          "created_at, updated_at) VALUES(?,?,?,?,?,?)",
          [name, path, remote_url, default_branch, now, now]
        )
        get(@db.last_insert_row_id)
      end

      def get(id)
        row = @db.get_first_row("SELECT * FROM repositories WHERE id = ?", [id])
        raise NotFound, "no such repository id: #{id}" if row.nil?

        row
      end

      def get_by_name(name)
        row = @db.get_first_row("SELECT * FROM repositories WHERE name = ?", [name])
        raise NotFound, "no such repository: #{name}" if row.nil?

        row
      end

      def find_by_name(name)
        @db.get_first_row("SELECT * FROM repositories WHERE name = ?", [name])
      end

      def list
        @db.execute("SELECT * FROM repositories ORDER BY name")
      end

      def update(id, fields)
        allowed = fields.transform_keys(&:to_s).slice("path", "remote_url", "default_branch")
        return get(id) if allowed.empty?

        assignments = allowed.keys.map { |c| "#{c} = ?" } << "updated_at = ?"
        @db.execute(
          "UPDATE repositories SET #{assignments.join(", ")} WHERE id = ?",
          allowed.values + [Clock.now, id]
        )
        get(id)
      end

      def remove(id)
        @db.execute("DELETE FROM repositories WHERE id = ?", [id])
      end

      # Associate an item with a repository. Idempotent (SPEC 8.3 / 14.1.2).
      def link(item_id, repository_id)
        @db.execute(
          "INSERT INTO item_repositories(item_id, repository_id, created_at) " \
          "VALUES(?,?,?) ON CONFLICT DO NOTHING",
          [item_id, repository_id, Clock.now]
        )
      end

      def unlink(item_id, repository_id)
        @db.execute(
          "DELETE FROM item_repositories WHERE item_id = ? AND repository_id = ?",
          [item_id, repository_id]
        )
      end

      def for_item(item_id)
        @db.execute(
          "SELECT r.* FROM repositories r " \
          "JOIN item_repositories ir ON ir.repository_id = r.id " \
          "WHERE ir.item_id = ? ORDER BY r.name",
          [item_id]
        )
      end
    end
  end
end
