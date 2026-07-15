# frozen_string_literal: true

module JM
  module Store
    # Data access for entries (SPEC 7). Introduced here for `block --reason`;
    # `jm log` builds on it in a later phase.
    class Entries
      def initialize(database)
        @database = database
        @db = database.db
      end

      def create(item_id:, body:, kind: "comment", author: nil)
        @db.execute(
          "INSERT INTO entries(item_id, kind, body, created_by, created_at) " \
          "VALUES(?,?,?,?,?)",
          [item_id, kind, body, author, Clock.now]
        )
        @db.last_insert_row_id
      end

      # Entries for an item, oldest first.
      def for_item(item_id)
        @db.execute(
          "SELECT * FROM entries WHERE item_id = ? ORDER BY created_at ASC, id ASC",
          [item_id]
        )
      end
    end
  end
end
