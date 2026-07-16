# frozen_string_literal: true

require "test_helper"

class QueriesTest < JM::TestCase
  def setup
    super
    run_cli("init")
  end

  def teardown
    @db&.close
    super
  end

  # Opened lazily so it connects after the test has seeded data.
  def q
    @db ||= JM::Database.open(@db_path)
    @q ||= JM::Queries.new(@db)
  end

  def test_show_assembles_associations
    run_cli("add", "parent")  # JM-1
    run_cli("add", "child")   # JM-2
    run_cli("tag", "add", "1", "urgent")
    run_cli("link", "1", "depends_on", "2")
    run_cli("log", "1", "--message", "progress note")

    detail = q.show(1)
    assert_equal "parent", detail["item"]["title"]
    assert_includes detail["tags"], "urgent"

    rel = detail["relations"].find { |r| r["relation"] == "depends_on" }
    assert_equal "JM-000002", rel["id"]
    assert_equal "child", rel["title"]

    assert_equal 1, detail["entries"].length
    assert_equal "progress note", detail["entries"].first["body"]
  end

  def test_show_returns_nil_for_missing_item
    assert_nil q.show(999)
  end

  def test_list_augments_rows_with_repository_names
    run_cli("add", "task")
    repo = File.join(@tmpdir, "r")
    FileUtils.mkdir_p(repo)
    run_cli("repo", "add", "myrepo", repo)
    run_cli("repo", "link", "1", "myrepo")

    row = q.list.find { |r| r["id"] == 1 }
    assert_equal ["myrepo"], row["repositories"]
  end

  def test_search_matches_title
    run_cli("add", "needle in the title")
    assert_equal 1, q.search("needle").length
    assert_empty q.search("haystack")
  end

  def test_stats_counts_states
    run_cli("add", "a")
    run_cli("add", "b")
    run_cli("done", "2")
    assert_equal 1, q.stats["inbox"]
    assert_equal 1, q.stats["done"]
  end
end
