# frozen_string_literal: true

module JM
  # Validation/coercion of user-supplied enum and priority values.
  module Parse
    module_function

    def type(value)
      unless TYPES.include?(value)
        raise ArgError, "unknown type: #{value} (one of: #{TYPES.join(", ")})"
      end

      value
    end

    def state(value)
      unless STATES.include?(value)
        raise ArgError, "unknown state: #{value} (one of: #{STATES.join(", ")})"
      end

      value
    end

    # A named alias (SPEC 12) or a plain integer.
    def priority(value)
      return PRIORITY_ALIASES[value] if PRIORITY_ALIASES.key?(value)

      Integer(value, 10)
    rescue ArgumentError, TypeError
      raise ArgError, "invalid priority: #{value} " \
                      "(integer or #{PRIORITY_ALIASES.keys.join("/")})"
    end

    # Relative durations ("1d", "2h", "30m", "1w") or an ISO date/time, resolved
    # to a storage timestamp cutoff for --since (SPEC 14.5).
    def since(value, now: Time.now.utc)
      if (m = value.match(/\A(\d+)([wdhm])\z/))
        n = m[1].to_i
        seconds = { "w" => 604_800, "d" => 86_400, "h" => 3600, "m" => 60 }[m[2]]
        (now - (n * seconds)).strftime(Clock::FORMAT)
      else
        Time.iso8601(value).utc.strftime(Clock::FORMAT)
      end
    rescue ArgumentError
      raise ArgError, "invalid --since: #{value} (e.g. 1d, 2h, 30m, or a date)"
    end

    # A backdated timestamp for --at (SPEC 14.6). Coarse dates are padded to the
    # earliest instant so an unknown day/time still yields a valid, sortable
    # storage stamp: 2026 -> 2026-01-01T00:00:00Z, 2026-01 -> ...-01T00:00:00Z.
    def at(value)
      str = value.to_s.strip
      normalized =
        if (m = str.match(/\A(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?\z/))
          format("%s-%s-%sT00:00:00Z", m[1], m[2] || "01", m[3] || "01")
        else
          str
        end
      Time.iso8601(normalized).utc.strftime(Clock::FORMAT)
    rescue ArgumentError
      raise ArgError, "invalid --at: #{value} " \
                      "(e.g. 2026, 2026-01, 2026-01-20, or a full ISO 8601 timestamp)"
    end
  end
end
