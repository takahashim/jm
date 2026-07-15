# frozen_string_literal: true

module JM
  module Store
    # Data access for external references (SPEC 10). Uniqueness (and thus
    # idempotency) is enforced by the schema's unique index.
    class References
      def initialize(database)
        @database = database
        @db = database.db
      end

      # Add a reference. Idempotent on (item, kind, value, repository).
      # Returns the stored row (existing or new).
      def add(item_id:, kind:, value:, repository_id: nil, label: nil, metadata_json: nil)
        @db.execute(
          "INSERT INTO item_references(item_id, repository_id, kind, value, label, " \
          "metadata_json, created_at) VALUES(?,?,?,?,?,?,?) " \
          "ON CONFLICT DO NOTHING",
          [item_id, repository_id, kind, value, label, metadata_json, Clock.now]
        )
        find(item_id, kind, value, repository_id)
      end

      # Whether a matching reference already exists (for scan idempotency).
      def exists?(item_id:, kind:, value:, repository_id: nil)
        !find(item_id, kind, value, repository_id).nil?
      end

      def list(item_id)
        @db.execute(
          "SELECT * FROM item_references WHERE item_id = ? ORDER BY id",
          [item_id]
        )
      end

      # Remove by reference row id, scoped to the item.
      def remove(item_id, ref_id)
        @db.execute(
          "DELETE FROM item_references WHERE id = ? AND item_id = ?",
          [ref_id, item_id]
        )
      end

      private

      def find(item_id, kind, value, repository_id)
        @db.get_first_row(
          "SELECT * FROM item_references WHERE item_id = ? AND kind = ? AND value = ? " \
          "AND COALESCE(repository_id, -1) = COALESCE(?, -1)",
          [item_id, kind, value, repository_id]
        )
      end
    end
  end
end
