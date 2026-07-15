# frozen_string_literal: true

module JM
  # Resolves the author of a write (SPEC 5.6): --by option, then JM_AUTHOR,
  # then nil (a direct human action).
  module Author
    module_function

    def resolve(env, by_option = nil)
      value = by_option || env["JM_AUTHOR"]
      value = value.to_s.strip
      value.empty? ? nil : value
    end
  end
end
