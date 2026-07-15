# frozen_string_literal: true

require "test_helper"
require "json"

class ItemLifecycleTest < JM::TestCase
  def setup
    super
    run_cli("init")
  end

  def add(*args, stdin: nil, env: {})
    out = StringIO.new
    err = StringIO.new
    full_env = { "JM_DATABASE" => @db_path }.merge(env)
    code = JM::CLI.run(
      ["add", *args],
      env: full_env, stdout: out, stderr: err, stdin: stdin || StringIO.new
    )
    [code, out.string, err.string]
  end

  def json_of(*argv, stdin: nil)
    out = StringIO.new
    JM::CLI.run(argv + ["--json"], env: { "JM_DATABASE" => @db_path },
                                   stdout: out, stderr: StringIO.new, stdin: stdin || StringIO.new)
    JSON.parse(out.string)
  end

  def test_add_fast_path_creates_inbox_note
    code, out, = run_cli("add", "quick idea")
    assert_equal 0, code
    assert_match(/Created JM-000001/, out)

    doc = json_of("show", "1")
    assert_equal "quick idea", doc["title"]
    assert_equal "note", doc["type"]
    assert_equal "inbox", doc["state"]
    assert_equal 0, doc["priority"]
    assert_equal "", doc["body"]
  end

  def test_add_json_returns_full_item
    doc = json_of("add", "titled", "--type", "bug", "--priority", "high")
    assert_equal JM::JSON_SCHEMA_VERSION, doc["schema_version"]
    assert_equal "JM-000001", doc["public_id"]
    assert_equal "bug", doc["type"]
    assert_equal 10, doc["priority"]
  end

  def test_add_body_from_stdin_requires_title
    code, _out, err = add("--stdin", stdin: StringIO.new("some body"))
    assert_equal 2, code
    assert_match(/title required/, err)
  end

  def test_add_body_from_stdin_with_title
    code, = add("captured", "--stdin", stdin: StringIO.new("line1\nline2"))
    assert_equal 0, code
    assert_equal "line1\nline2", json_of("show", "1")["body"]
  end

  def test_add_rejects_unknown_type
    code, _out, err = run_cli("add", "x", "--type", "bogus")
    assert_equal 2, code
    assert_match(/unknown type/, err)
  end

  def test_add_no_tty_without_title_fails
    code, _out, err = add(stdin: StringIO.new(""))
    assert_equal 2, code
    assert_match(/no TTY/, err)
  end

  def test_add_stdin_and_message_conflict
    code, _out, err = add("t", "--stdin", "--message", "m", stdin: StringIO.new("x"))
    assert_equal 2, code
    assert_match(/only one/, err)
  end

  def test_created_by_uses_jm_author
    out = StringIO.new
    JM::CLI.run(
      ["add", "agent work", "--json"],
      env: { "JM_DATABASE" => @db_path, "JM_AUTHOR" => "claude" },
      stdout: out, stderr: StringIO.new, stdin: StringIO.new
    )
    assert_equal "claude", JSON.parse(out.string)["created_by"]
  end

  def test_state_transitions_record_timestamps
    run_cli("add", "task")
    run_cli("start", "1")
    started = json_of("show", "1")
    assert_equal "active", started["state"]
    refute_nil started["started_at"]

    run_cli("done", "1", "--resolution", "completed")
    done = json_of("show", "1")
    assert_equal "done", done["state"]
    assert_equal "completed", done["resolution"]
    refute_nil done["completed_at"]
  end

  def test_done_at_backdates_completed_at
    run_cli("add", "already finished")
    run_cli("done", "1", "--resolution", "completed", "--at", "2026-01")
    done = json_of("show", "1")
    assert_equal "done", done["state"]
    assert_equal "2026-01-01T00:00:00Z", done["completed_at"]
  end

  def test_done_at_is_idempotent_and_does_not_overwrite
    run_cli("add", "task")
    run_cli("done", "1", "--at", "2026-01-20")
    run_cli("done", "1", "--at", "2020-05-05")
    assert_equal "2026-01-20T00:00:00Z", json_of("show", "1")["completed_at"]
  end

  def test_done_at_rejects_invalid_value
    run_cli("add", "task")
    code, _out, err = run_cli("done", "1", "--at", "sometime")
    assert_equal 2, code
    assert_match(/invalid --at/, err)
  end

  def test_start_is_idempotent_on_started_at
    run_cli("add", "task")
    run_cli("start", "1")
    first = json_of("show", "1")["started_at"]
    run_cli("start", "1")
    assert_equal first, json_of("show", "1")["started_at"]
  end

  def test_priority_alias_and_integer
    run_cli("add", "task")
    run_cli("priority", "1", "highest")
    assert_equal 20, json_of("show", "1")["priority"]
    run_cli("priority", "1", "-5")
    assert_equal(-5, json_of("show", "1")["priority"])
  end

  def test_edit_title_snapshots_revision
    run_cli("add", "orig")
    run_cli("edit", "1", "--title", "renamed")
    assert_equal "renamed", json_of("show", "1")["title"]

    db = JM::Database.open(@db_path)
    revs = db.db.execute("SELECT title FROM item_revisions")
    db.close
    assert_equal([{ "title" => "orig" }], revs.map { |r| { "title" => r["title"] } })
  end

  def test_edit_metadata_only_does_not_snapshot
    run_cli("add", "orig")
    run_cli("edit", "1", "--type", "design")
    db = JM::Database.open(@db_path)
    count = db.db.get_first_value("SELECT COUNT(*) FROM item_revisions")
    db.close
    assert_equal 0, count
  end

  def test_edit_completed_at_overwrites_existing_stamp
    run_cli("add", "task")
    run_cli("done", "1", "--at", "2026-07")
    assert_equal "2026-07-01T00:00:00Z", json_of("show", "1")["completed_at"]

    run_cli("edit", "1", "--completed-at", "2026-07-15")
    fixed = json_of("show", "1")
    assert_equal "2026-07-15T00:00:00Z", fixed["completed_at"]
    assert_equal "done", fixed["state"] # state unchanged by the correction
  end

  def test_edit_completed_at_rejects_invalid_value
    run_cli("add", "task")
    code, _out, err = run_cli("edit", "1", "--completed-at", "whenever")
    assert_equal 2, code
    assert_match(/invalid --at/, err)
  end

  def test_edit_timestamp_only_does_not_snapshot_revision
    run_cli("add", "task")
    run_cli("done", "1", "--at", "2026-07")
    run_cli("edit", "1", "--completed-at", "2026-07-15")
    db = JM::Database.open(@db_path)
    count = db.db.get_first_value("SELECT COUNT(*) FROM item_revisions")
    db.close
    assert_equal 0, count # only title/body are revisioned (SPEC 17)
  end

  def test_block_reason_adds_entry
    run_cli("add", "task")
    run_cli("block", "1", "--reason", "waiting")
    db = JM::Database.open(@db_path)
    bodies = db.db.execute("SELECT body FROM entries").map { |r| r["body"] }
    db.close
    assert_equal ["waiting"], bodies
  end

  def test_list_default_hides_done_and_archived
    run_cli("add", "a")
    run_cli("add", "b")
    run_cli("done", "2")
    _code, out, = run_cli("list")
    assert_match(/JM-000001/, out)
    refute_match(/JM-000002/, out)
  end

  def test_list_orders_by_state_rank_then_priority
    run_cli("add", "low-open")
    run_cli("open", "1")
    run_cli("add", "active-item")
    run_cli("start", "2")
    _code, out, = run_cli("list")
    # active (rank 1) should appear before open (rank 3)
    assert_operator out.index("JM-000002"), :<, out.index("JM-000001")
  end

  def test_show_missing_item_exits_3
    code, _out, err = run_cli("show", "999")
    assert_equal 3, code
    assert_match(/no such item/, err)
  end

  def test_invalid_id_exits_2
    code, _out, err = run_cli("show", "not-an-id")
    assert_equal 2, code
    assert_match(/invalid id/, err)
  end
end
