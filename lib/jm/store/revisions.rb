# frozen_string_literal: true

module JM
  module Store
    # Read access to item revisions (SPEC 17). Revisions are written by
    # Store::Items on title/body change; this store exposes them for `jm history`.
    class Revisions
      def initialize(database)
        @database = database
        @db = database.db
      end

      # Revisions for an item, newest first.
      def for_item(item_id)
        @db.execute(
          "SELECT * FROM item_revisions WHERE item_id = ? ORDER BY created_at DESC, id DESC",
          [item_id]
        )
      end

      # A single revision scoped to the item; raises NotFound.
      def get(item_id, revision_id)
        row = @db.get_first_row(
          "SELECT * FROM item_revisions WHERE id = ? AND item_id = ?",
          [revision_id, item_id]
        )
        if row.nil?
          raise NotFound,
                "no such revision ##{revision_id} for #{PublicId.format(item_id)}"
        end

        row
      end
    end
  end
end
