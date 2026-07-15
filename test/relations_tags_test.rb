# frozen_string_literal: true

require "test_helper"
require "json"

class RelationsTagsTest < JM::TestCase
  def setup
    super
    run_cli("init")
    run_cli("add", "first")
    run_cli("add", "second")
    run_cli("add", "third")
  end

  def json_of(*argv)
    out = StringIO.new
    JM::CLI.run(argv + ["--json"], env: { "JM_DATABASE" => @db_path },
                                   stdout: out, stderr: StringIO.new, stdin: StringIO.new)
    JSON.parse(out.string)
  end

  # --- relations ---

  def test_depends_on_shows_both_directions
    run_cli("link", "1", "depends_on", "2")
    rels1 = json_of("links", "1")["relations"]
    rels2 = json_of("links", "2")["relations"]
    assert_equal [{ "relation" => "depends_on", "id" => "JM-000002", "title" => "second" }], rels1
    assert_equal [{ "relation" => "blocks", "id" => "JM-000001", "title" => "first" }], rels2
  end

  def test_blocks_alias_normalizes_to_depends_on
    # "1 blocks 2" means 2 depends_on 1
    run_cli("link", "1", "blocks", "2")
    assert_equal "depends_on", json_of("links", "2")["relations"].first["relation"]
    assert_equal "JM-000001", json_of("links", "2")["relations"].first["id"]
  end

  def test_cycle_is_rejected
    run_cli("link", "1", "depends_on", "2")
    run_cli("link", "2", "depends_on", "3")
    code, _out, err = run_cli("link", "3", "depends_on", "1")
    assert_equal 4, code
    assert_match(/cycle/, err)
  end

  def test_relates_to_is_idempotent_and_symmetric
    run_cli("link", "2", "relates_to", "1")
    run_cli("link", "1", "relates_to", "2") # same edge, normalized order
    db = JM::Database.open(@db_path)
    count = db.db.get_first_value(
      "SELECT COUNT(*) FROM item_relations WHERE relation = 'relates_to'"
    )
    db.close
    assert_equal 1, count
  end

  def test_link_self_is_rejected
    code, _out, err = run_cli("link", "1", "relates_to", "1")
    assert_equal 2, code
    assert_match(/itself/, err)
  end

  def test_unlink_removes_relation
    run_cli("link", "1", "depends_on", "2")
    run_cli("unlink", "1", "depends_on", "2")
    assert_empty json_of("links", "1")["relations"]
  end

  # --- tags ---

  def test_tag_add_is_case_insensitive_unique_first_writer_casing
    run_cli("tag", "add", "1", "WebSocket")
    run_cli("tag", "add", "2", "websocket")
    assert_equal(["WebSocket"], json_of("tag", "list")["tags"].map { |t| t["name"] })
    assert_equal 2, json_of("tag", "list")["tags"].first["count"]
  end

  def test_tag_add_idempotent
    run_cli("tag", "add", "1", "x")
    run_cli("tag", "add", "1", "x")
    assert_equal ["x"], json_of("show", "1")["tags"]
  end

  def test_tag_remove
    run_cli("tag", "add", "1", "a", "b")
    run_cli("tag", "remove", "1", "a")
    assert_equal ["b"], json_of("show", "1")["tags"]
  end

  # --- entries ---

  def test_log_appends_entry_and_shows_in_item
    run_cli("log", "1", "--kind", "finding", "--message", "discovered X")
    doc = json_of("show", "1")
    assert_equal 1, doc["entries"].length
    assert_equal "finding", doc["entries"].first["kind"]
    assert_equal "discovered X", doc["entries"].first["body"]
  end

  def test_log_empty_is_rejected
    code, _out, err = run_cli("log", "1", "--message", "   ")
    assert_equal 2, code
    assert_match(/empty entry/, err)
  end
end
