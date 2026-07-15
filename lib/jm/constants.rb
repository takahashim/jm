# frozen_string_literal: true

module JM
  # Item types (SPEC 5.3). Validated to catch typos; extend here to add one.
  TYPES = %w[task bug design decision research idea question verification note].freeze

  # Item states (SPEC 5.4).
  STATES = %w[inbox open active blocked done archived].freeze

  # Business-order ranking for list sorting; not alphabetical (SPEC 14.5).
  STATE_RANK = {
    "inbox" => 0,
    "active" => 1,
    "blocked" => 2,
    "open" => 3,
    "done" => 4,
    "archived" => 5
  }.freeze

  # States shown by default in `jm list` (SPEC 14.5).
  DEFAULT_LIST_STATES = %w[inbox open active blocked].freeze

  # Named priority aliases (SPEC 12).
  PRIORITY_ALIASES = {
    "lowest" => -20,
    "low" => -10,
    "normal" => 0,
    "high" => 10,
    "highest" => 20
  }.freeze

  # Fallback defaults for new items (config [defaults] overrides these).
  DEFAULT_TYPE = "note"
  DEFAULT_STATE = "inbox"
  DEFAULT_PRIORITY = 0

  # Relation names accepted from users (SPEC 9). blocks/child_of are input
  # aliases normalized to their stored inverse.
  RELATION_INPUTS = %w[depends_on blocks parent_of child_of relates_to].freeze

  # Stored (normalized) relation names.
  STORED_RELATIONS = %w[depends_on parent_of relates_to].freeze

  # Display name of a stored relation when viewed from the target side (SPEC 9.3).
  RELATION_INVERSE = {
    "depends_on" => "blocks",
    "parent_of" => "child_of",
    "relates_to" => "relates_to"
  }.freeze
end
