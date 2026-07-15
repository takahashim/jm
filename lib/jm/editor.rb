# frozen_string_literal: true

require "shellwords"
require "tempfile"

module JM
  # Launches the configured editor on a temp Markdown file and returns the
  # edited text. Refuses to run without a TTY so agents never hang (SPEC 14.1.1).
  class Editor
    def initialize(config:, stdin: $stdin, launcher: nil)
      @config = config
      @stdin = stdin
      # Injectable for tests; defaults to spawning the real editor.
      @launcher = launcher || method(:spawn_editor)
    end

    # Open `initial` in the editor and return the saved contents.
    def edit(initial = "")
      raise ArgError, "no TTY available for the editor; use --message or --stdin" unless @stdin.tty?

      file = Tempfile.new(["jm", ".md"])
      begin
        file.write(initial)
        file.flush
        @launcher.call(@config.editor, file.path)
        File.read(file.path)
      ensure
        file.close
        file.unlink
      end
    end

    private

    def spawn_editor(editor, path)
      cmd = Shellwords.split(editor) + [path]
      ok = system(*cmd)
      raise ArgError, "editor exited with failure: #{editor}" unless ok
    end
  end
end
