# frozen_string_literal: true

module JM
  module Store
    # Data access for items, including revision snapshots and state
    # transitions (SPEC 5, 14.6, 17). All SQL for items lives here so commands
    # stay thin.
    class Items
      # Columns a caller may set through #update; updated_at is always bumped.
      UPDATABLE = %w[
        type title body state priority resolution
        started_at completed_at archived_at
      ].freeze

      # State that stamps a timestamp column on entry (SPEC 14.6).
      STATE_TIMESTAMP = {
        "active" => "started_at", "done" => "completed_at", "archived" => "archived_at"
      }.freeze

      def initialize(database)
        @database = database
        @db = database.db
      end

      def create(type:, title:, body: "", state: DEFAULT_STATE,
                 priority: DEFAULT_PRIORITY, resolution: nil, author: nil)
        now = Clock.now
        @db.execute(
          "INSERT INTO items(type, title, body, state, priority, resolution, " \
          "created_by, created_at, updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
          [type, title, body, state, priority, resolution, author, now, now]
        )
        get(@db.last_insert_row_id)
      end

      # Fetch by internal integer id; raises NotFound.
      def exists?(id)
        !@db.get_first_value("SELECT 1 FROM items WHERE id = ?", [id]).nil?
      end

      def get(id)
        row = @db.get_first_row("SELECT * FROM items WHERE id = ?", [id])
        raise NotFound, "no such item: #{PublicId.format(id)}" if row.nil?

        row
      end

      # Update whitelisted fields. Snapshots the prior title/body as a revision
      # when either changes (SPEC 17). Returns the updated row.
      def update(id, fields)
        current = get(id)
        assignable = fields.transform_keys(&:to_s).slice(*UPDATABLE)

        @database.transaction do
          snapshot_revision(current) if title_or_body_changed?(current, assignable)
          apply_update(id, assignable)
        end
        get(id)
      end

      # Move to a state, recording the associated timestamp on first entry and
      # leaving it unchanged on repeat (idempotent, SPEC 14.1.2 / 14.6).
      # `at` backdates the timestamp this transition stamps (SPEC 14.6); it only
      # applies when the field is still unset, preserving idempotency.
      def set_state(id, state, resolution: nil, at: nil)
        current = get(id)
        fields = { "state" => state }
        fields["resolution"] = resolution unless resolution.nil?
        if (col = STATE_TIMESTAMP[state])
          fields[col] = current[col] || at || Clock.now
        end
        update(id, fields)
      end

      # An item is ready when it is open and every depends_on target is done or
      # archived (SPEC 13). Correlated on items.id.
      READY_CLAUSE = <<~SQL
        items.state = 'open' AND NOT EXISTS (
          SELECT 1 FROM item_relations r JOIN items d ON d.id = r.target_item_id
          WHERE r.source_item_id = items.id AND r.relation = 'depends_on'
            AND d.state NOT IN ('done', 'archived')
        )
      SQL

      # Rows for `jm list` / `jm next`, filtered and ordered (SPEC 13, 14.5).
      # order: :default (state rank first) or :next (oldest ready first).
      def list(states: nil, type: nil, author: nil, since: nil, priority_min: nil,
               tag: nil, repo: nil, ready: false, ids: nil, order: :default, limit: nil)
        where, params = build_conditions(
          states: states, type: type, author: author, since: since,
          priority_min: priority_min, tag: tag, repo: repo, ready: ready, ids: ids
        )
        return [] if ids && ids.empty?

        sql = +"SELECT * FROM items"
        sql << " WHERE #{where.join(" AND ")}" unless where.empty?
        sql << " ORDER BY #{order_clause(order)}" unless order == :none
        sql << " LIMIT #{Integer(limit)}" if limit
        @db.execute(sql, params)
      end

      # State => count, plus a computed ready count (SPEC 14.14).
      def stats
        counts = STATES.to_h { |s| [s, 0] }
        @db.execute("SELECT state, COUNT(*) AS n FROM items GROUP BY state").each do |r|
          counts[r["state"]] = r["n"]
        end
        counts["ready"] = @db.get_first_value("SELECT COUNT(*) FROM items WHERE #{READY_CLAUSE}")
        counts
      end

      private

      def build_conditions(states:, type:, author:, since:, priority_min:, tag:, repo:,
                           ready:, ids: nil)
        where = []
        params = []
        if ids && !ids.empty?
          where << "items.id IN (#{(["?"] * ids.length).join(",")})"
          params.concat(ids)
        end
        # A ready query forces state=open via READY_CLAUSE, so skip states here.
        if ready
          where << "(#{READY_CLAUSE})"
        elsif states && !states.empty?
          where << "items.state IN (#{(["?"] * states.length).join(",")})"
          params.concat(states)
        end
        add_eq(where, params, "items.type", type)
        add_eq(where, params, "items.created_by", author)
        add_cmp(where, params, "items.updated_at", ">=", since)
        add_cmp(where, params, "items.priority", ">=", priority_min)
        add_tag(where, params, tag)
        add_repo(where, params, repo)
        [where, params]
      end

      def add_eq(where, params, column, value)
        return if value.nil?

        where << "#{column} = ?"
        params << value
      end

      def add_cmp(where, params, column, operator, value)
        return if value.nil?

        where << "#{column} #{operator} ?"
        params << value
      end

      def add_tag(where, params, tag)
        return if tag.nil?

        where << "EXISTS (SELECT 1 FROM item_tags it JOIN tags t ON t.id = it.tag_id " \
                 "WHERE it.item_id = items.id AND t.name = ? COLLATE NOCASE)"
        params << tag
      end

      def add_repo(where, params, repo)
        return if repo.nil?

        where << "EXISTS (SELECT 1 FROM item_repositories ir " \
                 "JOIN repositories rp ON rp.id = ir.repository_id " \
                 "WHERE ir.item_id = items.id AND rp.name = ?)"
        params << repo
      end

      # :default = state rank, priority desc, updated desc (SPEC 14.5).
      # :next = priority desc, updated_at ASC (oldest first), id asc (SPEC 14.13).
      def order_clause(order)
        return "priority DESC, updated_at ASC, id ASC" if order == :next

        cases = STATE_RANK.map { |state, rank| "WHEN '#{state}' THEN #{rank}" }.join(" ")
        "CASE state #{cases} ELSE 99 END ASC, priority DESC, updated_at DESC, id ASC"
      end

      def title_or_body_changed?(current, fields)
        (fields.key?("title") && fields["title"] != current["title"]) ||
          (fields.key?("body") && fields["body"] != current["body"])
      end

      def snapshot_revision(current)
        @db.execute(
          "INSERT INTO item_revisions(item_id, title, body, created_at) VALUES(?,?,?,?)",
          [current["id"], current["title"], current["body"], Clock.now]
        )
      end

      def apply_update(id, fields)
        return if fields.empty?

        assignments = fields.keys.map { |col| "#{col} = ?" }
        assignments << "updated_at = ?"
        values = fields.values + [Clock.now, id]
        @db.execute("UPDATE items SET #{assignments.join(", ")} WHERE id = ?", values)
      end
    end
  end
end
