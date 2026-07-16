# frozen_string_literal: true

module JM
  # Read-model shared by the CLI, and later by the TUI and web viewer. Assembles
  # items and their associations from the stores; it knows nothing about
  # rendering or transport, so every frontend can project the same data (PLAN 2).
  class Queries
    def initialize(database)
      @items = Store::Items.new(database)
      @entries = Store::Entries.new(database)
      @tags = Store::Tags.new(database)
      @relations = Store::Relations.new(database)
      @repos = Store::Repositories.new(database)
      @refs = Store::References.new(database)
      @search = Store::Search.new(database)
    end

    # Item rows matching the filters, each augmented with "repositories" => names.
    def list(states: nil, type: nil, author: nil, since: nil, priority_min: nil,
             tag: nil, repo: nil, ready: false)
      with_repositories(
        @items.list(states: states, type: type, author: author, since: since,
                    priority_min: priority_min, tag: tag, repo: repo, ready: ready)
      )
    end

    # Full-text search rows, augmented like #list.
    def search(query, type: nil, states: nil, tag: nil, repo: nil)
      with_repositories(@search.run(query, type: type, states: states, tag: tag, repo: repo))
    end

    # Per-state counts plus the ready count (SPEC 14.14).
    def stats
      @items.stats
    end

    # Registered repository names (for filtering by project).
    def repositories
      @repos.list.map { |r| r["name"] }
    end

    # Full detail for one item, or nil when it does not exist. Entries are
    # returned in full; a frontend decides how many to show.
    def show(id)
      return nil unless @items.exists?(id)

      {
        "item" => @items.get(id),
        "tags" => @tags.for_item(id),
        "repositories" => @repos.for_item(id).map { |r| r["name"] },
        "relations" => @relations.described_for(id).map { |e| relation_dto(e) },
        "references" => @refs.list(id),
        "entries" => @entries.for_item(id)
      }
    end

    # Repository name for a reference row, or nil when it has none. Kept here so
    # frontends resolve the display name the same way.
    def reference_repo_name(ref_row)
      ref_row["repository_id"] ? @repos.get(ref_row["repository_id"])["name"] : nil
    end

    private

    def with_repositories(rows)
      rows.map do |row|
        names = @repos.for_item(row["id"]).map { |r| r["name"] }
        row.to_h.merge("repositories" => names)
      end
    end

    def relation_dto(edge)
      { "relation" => edge["relation"],
        "id" => PublicId.format(edge["other_id"]),
        "title" => @items.get(edge["other_id"])["title"] }
    end
  end
end
