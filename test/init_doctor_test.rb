# frozen_string_literal: true

require "test_helper"
require "json"

class InitDoctorTest < JM::TestCase
  def test_doctor_fails_before_init
    code, _out, err = run_cli("doctor")
    assert_equal 5, code
    assert_match(/jm init/, err)
  end

  def test_init_creates_database_and_schema
    code, out, _err = run_cli("init")
    assert_equal 0, code
    assert_match(/Initialized database/, out)
    assert File.exist?(@db_path)

    db = JM::Database.open(@db_path)
    tables = db.db.execute(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
    ).map { |r| r["name"] }
    %w[items entries item_revisions repositories item_repositories
       item_relations item_references tags item_tags meta
       schema_migrations].each do |t|
      assert_includes tables, t
    end
    db.close
  end

  def test_init_is_idempotent
    run_cli("init")
    code, out, _err = run_cli("init")
    assert_equal 0, code
    assert_match(/ready/, out)
  end

  def test_init_json_output
    code, out, _err = run_cli("init", "--json")
    assert_equal 0, code
    doc = JSON.parse(out)
    assert_equal JM::JSON_SCHEMA_VERSION, doc["schema_version"]
    assert_equal true, doc["created"]
  end

  def test_doctor_clean_after_init
    run_cli("init")
    code, out, _err = run_cli("doctor")
    assert_equal 0, code
    assert_match(/No problems/, out)
  end

  def test_reference_unique_index_enforces_idempotency
    db = init_db
    now = JM::Clock.now
    db.db.execute(
      "INSERT INTO items(type, title, created_at, updated_at) VALUES('note','t',?,?)",
      [now, now]
    )
    item_id = db.db.last_insert_row_id
    insert = lambda do
      db.db.execute(
        "INSERT INTO item_references(item_id, kind, value, created_at) VALUES(?,?,?,?)",
        [item_id, "url", "https://example.com", now]
      )
    end
    insert.call
    assert_raises(SQLite3::ConstraintException) { insert.call }
    db.close
  end

  def test_fts_trigram_matches_japanese_substring
    db = init_db
    now = JM::Clock.now
    db.db.execute(
      "INSERT INTO items(type, title, body, created_at, updated_at) " \
      "VALUES('design','WebSocketイベント配送','本文',?,?)",
      [now, now]
    )
    rows = db.db.execute("SELECT title FROM items_fts WHERE items_fts MATCH 'イベント'")
    assert_equal 1, rows.length
    db.close
  end
end
