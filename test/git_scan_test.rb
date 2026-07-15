# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

class GitScanTest < JM::TestCase
  def setup
    super
    run_cli("init")
    @repo = File.join(@tmpdir, "repo")
    FileUtils.mkdir_p(@repo)
    git("init", "-q")
    git("config", "user.email", "t@e.com")
    git("config", "user.name", "t")
    run_cli("repo", "add", "myrepo", @repo)
    @seq = 0
  end

  def git(*args)
    _out, status = Open3.capture2e("git", "-C", @repo, *args)
    raise "git failed: #{args.join(" ")}" unless status.success?
  end

  def commit(message)
    @seq += 1
    File.write(File.join(@repo, "f#{@seq}.txt"), "x\n")
    git("add", ".")
    git("commit", "-qm", message)
    head_sha
  end

  def head_sha
    out, = Open3.capture2e("git", "-C", @repo, "rev-parse", "HEAD")
    out.strip
  end

  def refs_of(id)
    out = StringIO.new
    JM::CLI.run(["ref", "list", id.to_s, "--json"],
                env: { "JM_DATABASE" => @db_path },
                stdout: out, stderr: StringIO.new, stdin: StringIO.new)
    JSON.parse(out.string)["references"]
  end

  def test_scan_links_commit_to_referenced_item
    run_cli("add", "task")
    sha = commit("Implement the thing\n\nRefs: JM-1")
    run_cli("git", "scan", "--repo", "myrepo")

    refs = refs_of(1)
    assert_equal 1, refs.length
    assert_equal "commit", refs.first["kind"]
    assert_equal sha, refs.first["value"]
    assert_equal "myrepo", refs.first["repository"]
  end

  def test_scan_is_idempotent
    run_cli("add", "task")
    commit("work Refs: JM-1")
    run_cli("git", "scan", "--repo", "myrepo")
    run_cli("git", "scan", "--repo", "myrepo")
    assert_equal 1, refs_of(1).length
  end

  def test_scan_ignores_unknown_item_ids
    run_cli("add", "task")
    commit("mentions JM-999 which does not exist")
    _code, out, = run_cli("git", "scan", "--repo", "myrepo")
    assert_empty refs_of(1)
    assert_match(/No new commit references/, out)
  end

  def test_scan_matches_various_id_forms
    run_cli("add", "task") # JM-1
    commit("lower jm-1 and padded JM-000001 both point here")
    run_cli("git", "scan", "--repo", "myrepo")
    # Same commit + same item collapses to one reference.
    assert_equal 1, refs_of(1).length
  end

  def test_scan_requires_repo
    code, _out, err = run_cli("git", "scan")
    assert_equal 2, code
    assert_match(/--repo/, err)
  end

  def test_scan_rejects_unknown_subcommand
    code, _out, err = run_cli("git", "bogus")
    assert_equal 2, code
    assert_match(/usage: jm git scan/, err)
  end
end
