# frozen_string_literal: true

require "test_helper"

# tui_tui is an optional dependency (only needed for `jm tui`); skip these tests
# where it is not installed (e.g. CI without the gem).
begin
  require "tui_tui"
  require "jm/tui/app"
  TUI_TUI_AVAILABLE = true
rescue LoadError
  TUI_TUI_AVAILABLE = false
end

class TuiAppTest < JM::TestCase
  def setup
    super
    skip "tui_tui not installed" unless TUI_TUI_AVAILABLE
    run_cli("init")
    run_cli("add", "alpha item")
    run_cli("add", "beta item")
    @db = JM::Database.open(@db_path)
    @app = JM::TUI::App.new(JM::Queries.new(@db))
    @size = TuiTui::Size.new(rows: 20, cols: 80)
  end

  def teardown
    @db&.close
    super
  end

  def key(code)
    TuiTui::KeyEvent.new(key: code)
  end

  def rendered(app)
    app.view(@size).to_text
  end

  def test_list_screen_shows_items
    text = rendered(@app)
    assert_match(/alpha item/, text)
    assert_match(/beta item/, text)
    assert_match(/q quit/, text)
  end

  def test_open_detail_switches_screen
    detail = @app.update(key("l")) # open the selected item
    text = rendered(detail)
    assert_match(/back/, text)      # detail footer
    assert_match(/JM-0000/, text)   # shows a public id header
  end

  def test_back_returns_to_list
    app = @app.update(key("l")).update(key("h"))
    assert_match(/r reload/, rendered(app)) # list footer again
  end

  def test_detail_shift_jk_moves_between_items
    order = JM::Queries.new(@db).list(states: nil).map { |r| r["id"] }
    skip "need >= 2 items" if order.length < 2

    @app.update(key("l")) # open the first item's detail
    @app.update(key("J")) # next item
    assert_match(/#{JM::PublicId.format(order[1])}/, rendered(@app))

    @app.update(key("K")) # back to previous
    assert_match(/#{JM::PublicId.format(order[0])}/, rendered(@app))
  end

  def test_help_toggles
    @app.update(key("?"))
    text = rendered(@app)
    assert_match(/jm tui .* keys/, text)
    assert_match(%r{previous / next item}, text)

    @app.update(key("?")) # close, back to the list
    assert_match(/r reload/, rendered(@app))
  end

  def test_q_quits
    assert_equal :quit, @app.update(key("q"))
  end

  def test_navigation_clamps
    # Up from the top stays valid and renders.
    app = @app.update(key("k")).update(key("k"))
    refute_empty rendered(app)
  end
end
