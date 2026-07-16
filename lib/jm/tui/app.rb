# frozen_string_literal: true

# Loaded lazily by `jm tui` after tui_tui is required, so the class body may
# reference TuiTui constants.
module JM
  module TUI
    # Read-only terminal viewer over JM::Queries (SPEC 30). A TuiTui MVU app:
    # `update(event) -> self | :quit` and `view(size) -> Canvas`. Two screens,
    # an item list and an item detail, both keyboard-navigated. State is mutated
    # in place and `self` returned (the model holds the item list + a DB handle).
    # rubocop:disable Metrics/ClassLength -- one cohesive read-only view
    class App
      HEADER = TuiTui::Style.new(attrs: [:bold])
      DIM = TuiTui::Style.new(attrs: [:dim])
      SELECTED = TuiTui::Style.new(attrs: [:reverse])

      def self.run(queries)
        TuiTui::Runtime.new(new(queries)).run
      end

      def initialize(queries)
        @queries = queries
        @items = queries.list(states: nil)
        @sel = 0
        @scroll = 0
        @screen = :list
        @detail = nil
        @detail_lines = nil
      end

      def update(event)
        case event
        in TuiTui::KeyEvent(key: "q" | TuiTui::KeyCode::CTRL_C) then :quit
        else
          @screen == :list ? update_list(event) : update_detail(event)
        end
      end

      def view(size)
        @screen == :list ? render_list(size) : render_detail(size)
      end

      private

      # --- list screen ---

      def update_list(event)
        case event
        in TuiTui::KeyEvent(key: "j" | :down) then select(@sel + 1)
        in TuiTui::KeyEvent(key: "k" | :up) then select(@sel - 1)
        in TuiTui::KeyEvent(key: "g") then select(0)
        in TuiTui::KeyEvent(key: "G") then select(@items.length - 1)
        in TuiTui::KeyEvent(key: "l" | :right | "\r" | "\n") then open
        in TuiTui::KeyEvent(key: "r") then reload
        else self
        end
      end

      def select(index)
        @sel = index.clamp(0, [@items.length - 1, 0].max)
        self
      end

      def open
        return self if @items.empty?

        @detail = @queries.show(@items[@sel]["id"])
        @detail_lines = nil
        @scroll = 0
        @screen = :detail
        self
      end

      def reload
        @items = @queries.list(states: nil)
        select(@sel)
      end

      def render_list(size)
        canvas = TuiTui::Canvas.blank(size)
        canvas.text(1, 1, "jm  (#{@items.length} items)", HEADER)
        body_rows = [size.rows - 2, 0].max
        @scroll = window_top(@scroll, @sel, body_rows)
        if @items.empty?
          canvas.text(3, 1, "(no items)", DIM)
        else
          @items[@scroll, body_rows].to_a.each_with_index do |row, i|
            style = (@scroll + i) == @sel ? SELECTED : nil
            canvas.text(2 + i, 1, list_line(row), style)
          end
        end
        canvas.text(size.rows, 1, "j/k move  l/Enter open  g/G top/bottom  r reload  q quit", DIM)
        canvas
      end

      def list_line(row)
        repos = row["repositories"].empty? ? "" : "  [#{row["repositories"].join(", ")}]"
        format("%-9s %-7s %-9s %s%s",
               PublicId.format(row["id"]), row["state"], row["type"], row["title"], repos)
      end

      # --- detail screen ---

      def update_detail(event)
        case event
        in TuiTui::KeyEvent(key: "h" | :left | TuiTui::KeyCode::ESCAPE | TuiTui::KeyCode::BACKSPACE)
          @screen = :list
          self
        in TuiTui::KeyEvent(key: "j" | :down) then scroll_to(@scroll + 1)
        in TuiTui::KeyEvent(key: "k" | :up) then scroll_to(@scroll - 1)
        in TuiTui::KeyEvent(key: "g") then scroll_to(0)
        in TuiTui::KeyEvent(key: "G") then scroll_to(detail_lines.length)
        else self
        end
      end

      def scroll_to(value)
        @scroll = value.clamp(0, [detail_lines.length - 1, 0].max)
        self
      end

      def render_detail(size)
        canvas = TuiTui::Canvas.blank(size)
        body_rows = [size.rows - 1, 0].max
        scroll_to(@scroll)
        detail_lines[@scroll, body_rows].to_a.each_with_index do |(text, style), i|
          canvas.text(1 + i, 1, text, style)
        end
        canvas.text(size.rows, 1, "j/k scroll  h/Esc back  q quit", DIM)
        canvas
      end

      def detail_lines
        @detail_lines ||= build_detail_lines(@detail)
      end

      # Flatten the item detail into [text, style] lines for a scrollable view.
      def build_detail_lines(detail)
        item = detail["item"]
        lines = [[detail_header(item), HEADER], [item["title"].to_s, HEADER],
                 ["created: #{item["created_at"]}   updated: #{item["updated_at"]}", DIM]]
        meta_lines(detail, lines)
        body_lines(item, lines)
        entry_lines(detail["entries"], lines)
        lines
      end

      def detail_header(item)
        head = "#{PublicId.format(item["id"])}  [#{item["type"]}]  #{item["state"]}"
        item["resolution"] ? "#{head}  (#{item["resolution"]})" : head
      end

      def meta_lines(detail, lines)
        lines << ["tags: #{detail["tags"].join(", ")}", DIM] unless detail["tags"].empty?
        unless detail["repositories"].empty?
          lines << ["repositories: #{detail["repositories"].join(", ")}", DIM]
        end
        section(lines, "relations", detail["relations"]) do |r|
          "  #{r["relation"]} #{r["id"]}  #{r["title"]}"
        end
        section(lines, "references", detail["references"]) do |r|
          name = @queries.reference_repo_name(r)
          suffix = name ? " @#{name}" : ""
          "  ##{r["id"]} #{r["kind"]} #{r["value"]}#{suffix}"
        end
      end

      def body_lines(item, lines)
        lines << ["", nil]
        body = item["body"].to_s
        if body.strip.empty?
          lines << ["(no body)", DIM]
        else
          body.each_line { |l| lines << [l.chomp, nil] }
        end
      end

      def entry_lines(entries, lines)
        return if entries.empty?

        lines << ["", nil]
        lines << ["entries:", HEADER]
        entries.each do |e|
          author = e["created_by"] ? " <#{e["created_by"]}>" : ""
          lines << ["  [#{e["created_at"]}] #{e["kind"]}#{author}", DIM]
          e["body"].to_s.each_line { |l| lines << ["    #{l.chomp}", nil] }
        end
      end

      def section(lines, label, rows)
        return if rows.empty?

        lines << ["", nil]
        lines << ["#{label}:", HEADER]
        rows.each { |r| lines << [yield(r), nil] }
      end

      # Scroll offset that keeps `sel` within a window of `height` rows.
      def window_top(top, sel, height)
        return 0 if height <= 0

        if sel < top then sel
        elsif sel >= top + height then sel - height + 1
        else top
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
