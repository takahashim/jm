# frozen_string_literal: true

require "json"

module JM
  # Rendering and stream handling for human and machine output (SPEC 22, 23).
  # Commands receive an Output and call #line / #json rather than touching
  # $stdout directly, so text vs JSON stays a presentation concern.
  class Output
    attr_reader :stdout, :stderr

    def initialize(stdout: $stdout, stderr: $stderr, json: false, quiet: false, color: nil)
      @stdout = stdout
      @stderr = stderr
      @json = json
      @quiet = quiet
      # Default: color only on a TTY unless explicitly disabled (--no-color).
      @color = color.nil? ? stdout.tty? : color
    end

    def json?
      @json
    end

    def quiet?
      @quiet
    end

    def color?
      @color
    end

    # A human-facing line, suppressed by --quiet and by --json.
    def line(text = "")
      return if @quiet || @json

      @stdout.puts(text)
    end

    # A machine-readable payload. Wraps single objects and arrays with the JSON
    # schema version (SPEC 22). For a list, pass an Array and a key name.
    def json(payload, list_key: nil)
      doc =
        if list_key
          { "schema_version" => JSON_SCHEMA_VERSION, list_key => payload }
        else
          { "schema_version" => JSON_SCHEMA_VERSION }.merge(payload)
        end
      @stdout.puts(JSON.pretty_generate(doc))
    end

    # An error message to stderr (always shown, even under --quiet).
    def error(text)
      @stderr.puts("jm: #{text}")
    end
  end
end
