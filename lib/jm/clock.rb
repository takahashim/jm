# frozen_string_literal: true

require "time"

module JM
  # Single source of timestamps. Stored values are UTC ISO 8601 with a literal
  # trailing "Z" and fixed width, so TEXT column sorting matches chronological
  # order (SPEC 31).
  module Clock
    FORMAT = "%Y-%m-%dT%H:%M:%SZ"

    module_function

    # Current time as a storage string.
    def now
      Time.now.utc.strftime(FORMAT)
    end

    # Parse a stored timestamp back into a Time (UTC). The trailing "Z" marks
    # UTC, so parse as ISO 8601 rather than as local time.
    def parse(text)
      Time.iso8601(text).utc
    end

    # Compact UTC stamp for filenames, e.g. "20260715-173012" (SPEC 20.1).
    def file_stamp
      Time.now.utc.strftime("%Y%m%d-%H%M%S")
    end
  end
end
