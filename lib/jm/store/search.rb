# frozen_string_literal: true

module JM
  module Store
    # Full-text search over item title/body and entry body (SPEC 19). Uses FTS5
    # trigram with a LIKE fallback for queries shorter than the 3-char trigram
    # minimum. Results are filtered like `jm list` and ranked by relevance, then
    # priority and recency.
    class Search
      MIN_TRIGRAM = 3

      def initialize(database)
        @database = database
        @db = database.db
        @items = Items.new(database)
      end

      def run(query, type: nil, states: nil, tag: nil, repo: nil)
        scores = query.strip.length < MIN_TRIGRAM ? like_scores(query) : fts_scores(query)
        return [] if scores.empty?

        rows = @items.list(
          ids: scores.keys, type: type, states: states, tag: tag, repo: repo, order: :none
        )
        rank(rows, scores)
      end

      private

      # item_id => best (lowest) bm25 score across title/body and entry matches.
      def fts_scores(query)
        match = fts_quote(query)
        scores = {}
        @db.execute(
          "SELECT rowid AS id, bm25(items_fts, 10.0, 1.0) AS score " \
          "FROM items_fts WHERE items_fts MATCH ?", [match]
        ).each { |r| merge_score(scores, r["id"], r["score"]) }

        @db.execute(
          "SELECT e.item_id AS id, bm25(entries_fts) AS score " \
          "FROM entries_fts JOIN entries e ON e.id = entries_fts.rowid " \
          "WHERE entries_fts MATCH ?", [match]
        ).each { |r| merge_score(scores, r["id"], r["score"]) }
        scores
      end

      # Short queries: substring match with uniform score (no relevance order).
      def like_scores(query)
        pattern = "%#{escape_like(query)}%"
        scores = {}
        @db.execute(
          "SELECT id FROM items WHERE title LIKE ?1 ESCAPE '\\' OR body LIKE ?1 ESCAPE '\\'",
          [pattern]
        ).each { |r| scores[r["id"]] = 0.0 }
        @db.execute(
          "SELECT DISTINCT item_id AS id FROM entries WHERE body LIKE ? ESCAPE '\\'",
          [pattern]
        ).each { |r| scores[r["id"]] ||= 0.0 }
        scores
      end

      def merge_score(scores, id, score)
        scores[id] = scores.key?(id) ? [scores[id], score].min : score
      end

      # Relevance asc (bm25: lower is better), then priority desc, updated desc, id asc.
      def rank(rows, scores)
        rows.sort do |a, b|
          by = scores[a["id"]] <=> scores[b["id"]]
          next by unless by.zero?

          by = b["priority"] <=> a["priority"]
          next by unless by.zero?

          by = b["updated_at"] <=> a["updated_at"]
          by.zero? ? a["id"] <=> b["id"] : by
        end
      end

      # Wrap the whole query as one FTS5 string literal so user input is treated
      # literally; quoting the argument therefore does a phrase search.
      def fts_quote(query)
        %("#{query.strip.gsub('"', '""')}")
      end

      def escape_like(query)
        query.gsub(/([%_\\])/, '\\\\\1')
      end
    end
  end
end
