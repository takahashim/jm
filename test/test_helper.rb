# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "minitest/autorun"
require "tmpdir"
require "stringio"
require "jm"

module JM
  # Base test case with a throwaway database directory and a CLI runner that
  # captures stdout/stderr without spawning a subprocess.
  class TestCase < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir("jm-test")
      @db_path = File.join(@tmpdir, "jm.sqlite3")
    end

    def teardown
      FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
    end

    # Run the CLI in-process. Returns [exit_code, stdout, stderr].
    def run_cli(*argv, env: {}, stdin: nil)
      out = StringIO.new
      err = StringIO.new
      full_env = { "JM_DATABASE" => @db_path }.merge(env)
      code = JM::CLI.run(argv, env: full_env, stdout: out, stderr: err,
                               stdin: stdin || StringIO.new)
      [code, out.string, err.string]
    end

    # Initialize the database and return an open Database for direct assertions.
    def init_db
      run_cli("init")
      JM::Database.open(@db_path)
    end
  end
end
