# frozen_string_literal: true

require "jm/version"

module JM
  # Version of the --json output contract exposed to coding agents (SPEC 16, 22).
  # Bump only on a breaking change to the JSON shape.
  JSON_SCHEMA_VERSION = 1
end

require "jm/errors"
require "jm/constants"
require "jm/clock"
require "jm/public_id"
require "jm/author"
require "jm/parse"
require "jm/config"
require "jm/output"
require "jm/database"
require "jm/editor"
require "jm/input_source"
require "jm/item_view"
require "jm/git"
require "jm/store/items"
require "jm/store/entries"
require "jm/store/tags"
require "jm/store/relations"
require "jm/store/repositories"
require "jm/store/references"
require "jm/store/revisions"
require "jm/store/search"
require "jm/queries"
require "jm/command"
require "jm/cli"
