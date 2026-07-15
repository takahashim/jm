# frozen_string_literal: true

module JM
  # Base class for all errors that map to a process exit code (SPEC 22).
  # Commands raise these; CLI.run rescues them, prints to stderr, and returns
  # the exit code.
  class Error < StandardError
    def exit_code
      1
    end
  end

  # Bad arguments / usage, including "editor needed but no TTY" (SPEC 14.1.1).
  class ArgError < Error
    def exit_code
      2
    end
  end

  # Target item / repository / reference does not exist.
  class NotFound < Error
    def exit_code
      3
    end
  end

  # Integrity violation, e.g. a depends_on cycle (SPEC 9.4).
  class IntegrityError < Error
    def exit_code
      4
    end
  end

  # Database problem: cannot open, pending migration, missing FTS5, etc.
  class DatabaseError < Error
    def exit_code
      5
    end
  end

  # External command / Git failure (SPEC 24).
  class GitError < Error
    def exit_code
      6
    end
  end
end
