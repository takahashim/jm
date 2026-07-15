# frozen_string_literal: true

require "test_helper"
require "json"

class MaintenanceTest < JM::TestCase
  def setup
    super
    run_cli("init")
  end

  def json_of(*argv, stdin: nil)
    out = StringIO.new
    JM::CLI.run(argv + ["--json"], env: { "JM_DATABASE" => @db_path },
                                   stdout: out, stderr: StringIO.new, stdin: stdin || StringIO.new)
    JSON.parse(out.string)
  end

  # --- history ---

  def test_history_lists_revisions_newest_first
    run_cli("add", "v0")
    run_cli("edit", "1", "--title", "v1")
    run_cli("edit", "1", "--title", "v2")
    revs = json_of("history", "1")["revisions"]
    assert_equal(%w[v1 v0], revs.map { |r| r["title"] })
  end

  def test_history_show_specific_revision
    run_cli("add", "orig", "--message", "orig body")
    run_cli("edit", "1", "--message", "new body")
    rev_id = json_of("history", "1")["revisions"].first["id"]
    doc = json_of("history", "1", "--show", rev_id.to_s)
    assert_equal "orig body", doc["body"]
  end

  # --- backup ---

  def test_backup_creates_valid_restorable_copy
    run_cli("add", "keep me")
    code, out, = run_cli("backup")
    assert_equal 0, code
    path = out[/Backed up to (.+)$/, 1]
    assert File.exist?(path)

    restored = SQLite3::Database.new(path)
    restored.results_as_hash = true
    title = restored.get_first_value("SELECT title FROM items WHERE id = 1")
    restored.close
    assert_equal "keep me", title
  end

  # --- delete ---

  def test_delete_force_removes_item_and_cascades
    run_cli("add", "doomed")
    run_cli("add", "other")
    run_cli("log", "1", "--message", "note")
    run_cli("tag", "add", "1", "x")
    run_cli("link", "1", "relates_to", "2")
    run_cli("ref", "add", "1", "url", "https://example.com")
    run_cli("edit", "1", "--title", "renamed") # creates a revision

    code, = run_cli("delete", "1", "--force")
    assert_equal 0, code

    db = JM::Database.open(@db_path)
    conn = db.db
    assert_equal 0, conn.get_first_value("SELECT COUNT(*) FROM items WHERE id = 1")
    assert_equal 0, conn.get_first_value("SELECT COUNT(*) FROM entries WHERE item_id = 1")
    assert_equal 0, conn.get_first_value("SELECT COUNT(*) FROM item_tags WHERE item_id = 1")
    assert_equal 0, conn.get_first_value("SELECT COUNT(*) FROM item_references WHERE item_id = 1")
    assert_equal 0, conn.get_first_value("SELECT COUNT(*) FROM item_revisions WHERE item_id = 1")
    assert_equal 0, conn.get_first_value(
      "SELECT COUNT(*) FROM item_relations WHERE source_item_id = 1 OR target_item_id = 1"
    )
    # the other item survives
    assert_equal 1, conn.get_first_value("SELECT COUNT(*) FROM items WHERE id = 2")
    db.close
  end

  def test_delete_requires_force_without_tty
    run_cli("add", "x")
    code, _out, err = run_cli("delete", "1")
    assert_equal 2, code
    assert_match(/--force/, err)
    assert_equal 1, json_of("show", "1")["id"] # still there
  end

  def test_delete_confirm_yes_via_tty
    run_cli("add", "x")
    # Simulate a TTY that answers "y"
    answer = StringIO.new("y\n")
    def answer.tty? = true
    code, = run_cli("delete", "1", stdin: answer)
    assert_equal 0, code
    code2, = run_cli("show", "1")
    assert_equal 3, code2
  end

  def test_delete_confirm_no_aborts
    run_cli("add", "x")
    answer = StringIO.new("n\n")
    def answer.tty? = true
    code, = run_cli("delete", "1", stdin: answer)
    assert_equal 2, code
    assert_equal 1, json_of("show", "1")["id"]
  end

  # --- doctor ---

  def test_doctor_clean
    run_cli("add", "x")
    code, out, = run_cli("doctor")
    assert_equal 0, code
    assert_match(/No problems/, out)
  end

  def test_doctor_detects_done_without_completed_at
    run_cli("add", "x")
    db = JM::Database.open(@db_path)
    db.db.execute("UPDATE items SET state='done', completed_at=NULL WHERE id=1")
    db.close
    code, out, = run_cli("doctor")
    assert_equal 4, code
    assert_match(/done but has no completed_at/, out)
  end

  def test_doctor_detects_depends_on_cycle
    run_cli("add", "a")
    run_cli("add", "b")
    run_cli("link", "1", "depends_on", "2")
    # Force a cycle directly, bypassing the guard, to exercise doctor.
    db = JM::Database.open(@db_path)
    db.db.execute(
      "INSERT INTO item_relations(source_item_id, target_item_id, relation, created_at) " \
      "VALUES(2, 1, 'depends_on', ?)", [JM::Clock.now]
    )
    db.close
    code, out, = run_cli("doctor")
    assert_equal 4, code
    assert_match(/cycle/, out)
  end

  def test_doctor_rebuild_fts
    run_cli("add", "searchable")
    code, out, = run_cli("doctor", "--rebuild-fts")
    assert_equal 0, code
    assert_match(/Rebuilt FTS/, out)
    # search still works after a rebuild
    assert_equal 1, json_of("search", "searchable")["items"].length
  end
end
