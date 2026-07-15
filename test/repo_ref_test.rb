# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

class RepoRefTest < JM::TestCase
  def setup
    super
    run_cli("init")
    run_cli("add", "item")
    @repo = File.join(@tmpdir, "repo")
    build_git_repo(@repo)
  end

  def build_git_repo(dir)
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "lib", "foo.rb"), "x\n")
    run_git(dir, "init", "-q")
    run_git(dir, "config", "user.email", "t@e.com")
    run_git(dir, "config", "user.name", "t")
    run_git(dir, "add", ".")
    run_git(dir, "commit", "-qm", "init")
  end

  def run_git(dir, *args)
    _out, status = Open3.capture2e("git", "-C", dir, *args)
    raise "git failed: #{args.join(" ")}" unless status.success?
  end

  def json_of(*argv)
    out = StringIO.new
    JM::CLI.run(argv + ["--json"], env: { "JM_DATABASE" => @db_path },
                                   stdout: out, stderr: StringIO.new, stdin: StringIO.new)
    JSON.parse(out.string)
  end

  def head_sha
    out, = Open3.capture2e("git", "-C", @repo, "rev-parse", "HEAD")
    out.strip
  end

  def test_repo_add_autodetects_git_metadata
    run_cli("repo", "add", "myrepo", @repo)
    doc = json_of("repo", "show", "myrepo")
    assert_equal File.realpath(@repo), File.realpath(doc["path"])
    refute_nil doc["default_branch"]
  end

  def test_repo_add_duplicate_name_rejected
    run_cli("repo", "add", "myrepo", @repo)
    code, _out, err = run_cli("repo", "add", "myrepo", @repo)
    assert_equal 2, code
    assert_match(/already exists/, err)
  end

  def test_repo_link_and_show
    run_cli("repo", "add", "myrepo", @repo)
    run_cli("repo", "link", "1", "myrepo")
    assert_equal ["myrepo"], json_of("show", "1")["repositories"]
  end

  def test_add_with_repo_links_on_create
    run_cli("repo", "add", "myrepo", @repo)
    doc = json_of("add", "linked item", "--repo", "myrepo")
    assert_equal ["myrepo"], json_of("show", doc["id"].to_s)["repositories"]
  end

  def test_list_shows_linked_repo_names
    run_cli("repo", "add", "myrepo", @repo)
    run_cli("add", "linked", "--repo", "myrepo")
    _code, out, = run_cli("list")
    linked = out.lines.find { |l| l.include?("linked") }
    assert_match(/\[myrepo\]/, linked)
    # The setup item has no repo, so no bracket is appended.
    plain = out.lines.find { |l| l.include?(" item") }
    refute_match(/\[/, plain)
  end

  def test_add_with_unknown_repo_creates_no_item
    code, _out, err = run_cli("add", "orphan?", "--repo", "nope")
    assert_equal 3, code
    assert_match(/no such repository/, err)
    titles = json_of("list")["items"].map { |i| i["title"] }
    refute_includes titles, "orphan?"
  end

  def test_repo_remove_keeps_items
    run_cli("repo", "add", "myrepo", @repo)
    run_cli("repo", "link", "1", "myrepo")
    run_cli("repo", "remove", "myrepo")
    assert_empty json_of("show", "1")["repositories"]
    refute_nil json_of("show", "1")["id"]
  end

  def test_ref_commit_resolves_full_sha
    run_cli("repo", "add", "myrepo", @repo)
    run_cli("ref", "add", "1", "commit", "HEAD", "--repo", "myrepo")
    ref = json_of("ref", "list", "1")["references"].first
    assert_equal "commit", ref["kind"]
    assert_equal head_sha, ref["value"]
    assert_equal 40, ref["value"].length
  end

  def test_ref_file_stored_repo_relative
    run_cli("repo", "add", "myrepo", @repo)
    abs = File.join(@repo, "lib", "foo.rb")
    run_cli("ref", "add", "1", "file", abs, "--repo", "myrepo")
    ref = json_of("ref", "list", "1")["references"].first
    assert_equal "lib/foo.rb", ref["value"]
  end

  def test_ref_add_is_idempotent
    run_cli("repo", "add", "myrepo", @repo)
    run_cli("ref", "add", "1", "url", "https://example.com")
    run_cli("ref", "add", "1", "url", "https://example.com")
    assert_equal 1, json_of("ref", "list", "1")["references"].length
  end

  def test_ref_same_value_different_repo_is_distinct
    run_cli("repo", "add", "myrepo", @repo)
    run_cli("ref", "add", "1", "url", "https://example.com")
    run_cli("ref", "add", "1", "url", "https://example.com", "--repo", "myrepo")
    assert_equal 2, json_of("ref", "list", "1")["references"].length
  end

  def test_ref_remove
    run_cli("ref", "add", "1", "url", "https://example.com")
    ref_id = json_of("ref", "list", "1")["references"].first["id"]
    run_cli("ref", "remove", "1", ref_id.to_s)
    assert_empty json_of("ref", "list", "1")["references"]
  end
end
