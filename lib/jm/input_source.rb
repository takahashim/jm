# frozen_string_literal: true

module JM
  # Resolves body text from exactly one source: --message, --stdin, or the
  # editor (SPEC 14.1.3). Specifying more than one is an argument error.
  module InputSource
    module_function

    # @param message [String, nil] value of --message
    # @param use_stdin [Boolean] whether --stdin was given
    # @param stdin [IO] the input stream
    # @param editor [#edit, nil] editor used when no explicit source is given
    # @param initial [String] seed text for the editor
    def resolve(message:, use_stdin:, stdin:, editor: nil, initial: "")
      chosen = [!message.nil?, use_stdin].count(true)
      raise ArgError, "choose only one of --message or --stdin" if chosen > 1

      return message if message
      return stdin.read if use_stdin
      return editor.edit(initial) if editor

      raise ArgError, "no body given; use --message, --stdin, or run in a terminal"
    end
  end
end
