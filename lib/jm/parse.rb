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
  end
end
