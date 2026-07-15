# frozen_string_literal: true

module JM
  module Store
    # Directed item relations with input normalization and depends_on cycle
    # prevention (SPEC 9).
    class Relations
      def initialize(database)
        @database = database
        @db = database.db
      end

      # Add a relation between internal ids `a` and `b`. Input aliases are
      # normalized; a depends_on that would form a cycle raises. Idempotent.
      # Returns the stored [source, target, relation].
      def add(from, to, relation)
        raise ArgError, "cannot relate an item to itself" if from == to

        source, target, rel = normalize(from, to, relation)
        if rel == "depends_on" && creates_cycle?(source, target)
          raise IntegrityError,
                "adding this depends_on would create a cycle"
        end

        @db.execute(
          "INSERT INTO item_relations(source_item_id, target_item_id, relation, created_at) " \
          "VALUES(?,?,?,?) ON CONFLICT DO NOTHING",
          [source, target, rel, Clock.now]
        )
        [source, target, rel]
      end

      def remove(from, to, relation)
        source, target, rel = normalize(from, to, relation)
        @db.execute(
          "DELETE FROM item_relations WHERE source_item_id = ? AND target_item_id = ? " \
          "AND relation = ?",
          [source, target, rel]
        )
      end

      # Stored edges touching an item, either side.
      def for_item(item_id)
        @db.execute(
          "SELECT source_item_id, target_item_id, relation FROM item_relations " \
          "WHERE source_item_id = ? OR target_item_id = ? " \
          "ORDER BY relation, source_item_id, target_item_id",
          [item_id, item_id]
        )
      end

      # Edges from an item's perspective, with the inverse name applied when the
      # item is on the target side (SPEC 9.3). Callers add ids/titles.
      def described_for(item_id)
        for_item(item_id).map do |edge|
          if edge["source_item_id"] == item_id
            { "relation" => edge["relation"], "other_id" => edge["target_item_id"] }
          else
            { "relation" => RELATION_INVERSE[edge["relation"]],
              "other_id" => edge["source_item_id"] }
          end
        end
      end

      # Ids this item depends on (used by ready evaluation later).
      def dependency_ids(item_id)
        @db.execute(
          "SELECT target_item_id FROM item_relations " \
          "WHERE source_item_id = ? AND relation = 'depends_on'",
          [item_id]
        ).map { |r| r["target_item_id"] }
      end

      # Source ids that lie on a depends_on cycle. A safety net for `jm doctor`;
      # normal inserts already prevent cycles.
      def cycle_node_ids
        @db.execute(
          "SELECT DISTINCT source_item_id AS id FROM item_relations WHERE relation = 'depends_on'"
        ).map { |r| r["id"] }.select { |id| depends_path?(id, id) }
      end

      private

      def normalize(from, to, relation)
        case relation
        when "depends_on" then [from, to, "depends_on"]
        when "blocks" then [to, from, "depends_on"]
        when "parent_of" then [from, to, "parent_of"]
        when "child_of" then [to, from, "parent_of"]
        when "relates_to" then [*[from, to].minmax, "relates_to"]
        else
          raise ArgError, "unknown relation: #{relation} (#{RELATION_INPUTS.join(", ")})"
        end
      end

      # True if target already reaches source via depends_on, so adding
      # source -> target (source depends on target) would close a loop.
      def creates_cycle?(source, target)
        depends_path?(target, source)
      end

      # True if `from` reaches `to` following depends_on edges.
      def depends_path?(from, to)
        row = @db.get_first_row(<<~SQL, [from, to])
          WITH RECURSIVE reach(id) AS (
            SELECT target_item_id FROM item_relations
              WHERE source_item_id = ? AND relation = 'depends_on'
            UNION
            SELECT r.target_item_id FROM item_relations r
              JOIN reach ON r.source_item_id = reach.id
              WHERE r.relation = 'depends_on'
          )
          SELECT 1 FROM reach WHERE id = ? LIMIT 1
        SQL
        !row.nil?
      end
    end
  end
end
