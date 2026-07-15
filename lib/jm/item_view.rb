# frozen_string_literal: true

module JM
  # Presentation of item rows for human and JSON output. Keeps rendering out of
  # commands and the store.
  class ItemView
    def initialize(row)
      @row = row
    end

    def public_id
      PublicId.format(@row["id"])
    end

    # Full JSON object for `jm show --json` and `jm add --json`.
    def to_h
      {
        "id" => @row["id"],
        "public_id" => public_id,
        "type" => @row["type"],
        "title" => @row["title"],
        "state" => @row["state"],
        "priority" => @row["priority"],
        "resolution" => @row["resolution"],
        "created_by" => @row["created_by"],
        "created_at" => @row["created_at"],
        "updated_at" => @row["updated_at"],
        "started_at" => @row["started_at"],
        "completed_at" => @row["completed_at"],
        "archived_at" => @row["archived_at"],
        "body" => @row["body"]
      }
    end

    # Compact one-line summary for `jm list`.
    def summary_line
      format(
        "%-9s %-7s %-12s %4s  %s",
        public_id, @row["state"], @row["type"],
        "p#{@row["priority"]}", @row["title"]
      )
    end

    # Multi-line detail for `jm show`.
    def render(output)
      header = "#{public_id}  [#{@row["type"]}]  #{@row["state"]}  p#{@row["priority"]}"
      header += "  (#{@row["resolution"]})" if @row["resolution"]
      output.line(header)
      output.line("title: #{@row["title"]}")
      output.line("created: #{@row["created_at"]}   updated: #{@row["updated_at"]}")
      output.line(timestamps_line) if timestamps_line
      output.line("")
      output.line(@row["body"].to_s.empty? ? "(no body)" : @row["body"])
    end

    private

    def timestamps_line
      parts = []
      parts << "started: #{@row["started_at"]}" if @row["started_at"]
      parts << "completed: #{@row["completed_at"]}" if @row["completed_at"]
      parts << "archived: #{@row["archived_at"]}" if @row["archived_at"]
      parts.empty? ? nil : parts.join("   ")
    end
  end
end
