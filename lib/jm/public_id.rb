# frozen_string_literal: true

module JM
  # Conversion between the internal integer id and the human-facing public id
  # "JM-000042" (SPEC 5.2). The public id is always derived from the integer id;
  # it is never stored.
  module PublicId
    PREFIX = "JM-"
    WIDTH = 6

    module_function

    # Format an integer id as the standard public id, e.g. 42 -> "JM-000042".
    # Ids wider than WIDTH are not padded and simply grow.
    def format(id)
      "#{PREFIX}#{id.to_s.rjust(WIDTH, "0")}"
    end

    # Normalize a user-supplied id string to an internal integer id.
    # Accepts "42", "JM-42", "dm-42", "JM-000042" (SPEC 5.2). The JM- prefix is
    # case-insensitive; leading zeros are ignored. Raises ArgError otherwise.
    def normalize(input)
      raise ArgError, "empty id" if input.nil?

      s = input.to_s.strip
      s = s[PREFIX.length..] if s.downcase.start_with?(PREFIX.downcase)

      unless /\A\d+\z/.match?(s)
        raise ArgError, "invalid id: #{input.inspect} (expected e.g. 42 or JM-42)"
      end

      Integer(s, 10)
    end
  end
end
