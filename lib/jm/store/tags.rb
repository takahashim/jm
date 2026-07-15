# frozen_string_literal: true

module JM
  module Store
    # Data access for tags (SPEC 11). Names are case-insensitively unique with
    # first-writer casing; matching is case-insensitive.
    class Tags
      def initialize(database)
        @database = database
        @db = database.db
      end

      # Attach a tag to an item, creating the tag if new. Idempotent.
      def add(item_id, name)
        @database.transaction do
          @db.execute("INSERT INTO tags(name) VALUES(?) ON CONFLICT(name) DO NOTHING", [name])
          tag_id = tag_id_for(name)
          @db.execute(
            "INSERT INTO item_tags(item_id, tag_id) VALUES(?,?) " \
            "ON CONFLICT DO NOTHING",
            [item_id, tag_id]
          )
        end
      end

      # Detach a tag from an item. No-op if not attached.
      def remove(item_id, name)
        tag_id = tag_id_for(name)
        return if tag_id.nil?

        @db.execute("DELETE FROM item_tags WHERE item_id = ? AND tag_id = ?", [item_id, tag_id])
      end

      def for_item(item_id)
        @db.execute(
          "SELECT t.name FROM tags t JOIN item_tags it ON it.tag_id = t.id " \
          "WHERE it.item_id = ? ORDER BY t.name COLLATE NOCASE",
          [item_id]
        ).map { |r| r["name"] }
      end

      # [{ "name" => ..., "count" => n }, ...] for `jm tag list`.
      def all_with_counts
        @db.execute(
          "SELECT t.name AS name, COUNT(it.item_id) AS count FROM tags t " \
          "LEFT JOIN item_tags it ON it.tag_id = t.id " \
          "GROUP BY t.id ORDER BY t.name COLLATE NOCASE"
        )
      end

      private

      def tag_id_for(name)
        @db.get_first_value("SELECT id FROM tags WHERE name = ? COLLATE NOCASE", [name])
      end
    end
  end
end
