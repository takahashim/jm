# frozen_string_literal: true

require "test_helper"
require "json"

class SearchReadyTest < JM::TestCase
  def setup
    super
    run_cli("init")
  end

  def json_of(*argv)
    out = StringIO.new
    JM::CLI.run(argv + ["--json"], env: { "JM_DATABASE" => @db_path },
                                   stdout: out, stderr: StringIO.new, stdin: StringIO.new)
    JSON.parse(out.string)
  end

  def public_ids(*argv)
    json_of(*argv)["items"].map { |i| i["public_id"] }
  end

  # --- search ---

  def test_search_matches_title_substring_japanese
    run_cli("add", "WebSocketイベント配送", "--type", "design")
    run_cli("add", "無関係な項目")
    assert_equal ["JM-000001"], public_ids("search", "イベント")
  end

  def test_search_matches_body
    run_cli("add", "plain title", "--message", "the quick brown fox")
    run_cli("add", "another")
    assert_equal ["JM-000001"], public_ids("search", "brown fox")
  end

  def test_search_matches_entry_body
    run_cli("add", "item")
    run_cli("log", "1", "--message", "Promise job ordering matters")
    assert_equal ["JM-000001"], public_ids("search", "Promise job")
  end

  def test_search_short_query_uses_like_fallback
    run_cli("add", "ab item")
    # 2-char query is below the trigram minimum
    assert_equal ["JM-000001"], public_ids("search", "ab")
  end

  def test_search_filters_by_type
    run_cli("add", "socket design", "--type", "design")
    run_cli("add", "socket task", "--type", "task")
    assert_equal ["JM-000001"], public_ids("search", "socket", "--type", "design")
  end

  def test_search_no_match_is_empty
    run_cli("add", "something")
    assert_empty json_of("search", "nonexistentxyz")["items"]
  end

  def test_search_phrase_when_quoted_arg
    run_cli("add", "event loop machinery")
    run_cli("add", "loop and event separately")
    # single quoted arg -> phrase; only the contiguous "event loop" matches
    assert_equal ["JM-000001"], public_ids("search", "event loop")
  end

  # --- ready / next / stats ---

  def test_ready_requires_open_and_satisfied_deps
    run_cli("add", "blocker")   # 1
    run_cli("add", "dependent") # 2
    run_cli("open", "2")
    run_cli("link", "2", "depends_on", "1")

    assert_empty json_of("list", "--ready")["items"] # 1 not done

    run_cli("done", "1")
    assert_equal ["JM-000002"], public_ids("list", "--ready")
  end

  def test_inbox_item_is_not_ready
    run_cli("add", "fresh") # stays inbox
    assert_empty json_of("list", "--ready")["items"]
  end

  def test_next_picks_highest_priority_ready
    run_cli("add", "low")
    run_cli("open", "1")
    run_cli("add", "high")
    run_cli("open", "2")
    run_cli("priority", "2", "high")
    assert_equal "JM-000002", json_of("next")["public_id"]
  end

  def test_next_start_activates
    run_cli("add", "task")
    run_cli("open", "1")
    doc = json_of("next", "--start")
    assert_equal "active", doc["state"]
    refute_nil doc["started_at"]
  end

  def test_next_nothing_ready_exits_3
    run_cli("add", "inbox-only")
    code, _out, _err = run_cli("next")
    assert_equal 3, code
  end

  def test_stats_counts_states_and_ready
    run_cli("add", "a")
    run_cli("add", "b")
    run_cli("open", "2")
    run_cli("add", "c")
    run_cli("done", "3")
    stats = json_of("stats")
    assert_equal 1, stats["inbox"]
    assert_equal 1, stats["open"]
    assert_equal 1, stats["done"]
    assert_equal 1, stats["ready"]
  end
end
