# frozen_string_literal: true

require "optparse"

module JM
  # Base class for commands that operate on an initialized database. Handles the
  # connection lifecycle and exposes thin helpers so subclasses stay focused on
  # "parse args -> call store -> render" (PLAN 2).
  class Command
    def initialize(output:, config:, env: ENV, stdin: $stdin)
      @output = output
      @config = config
      @env = env
      @stdin = stdin
    end

    def run(args)
      perform(args)
    ensure
      @db&.close
    end

    private

    def db
      @db ||= Database.open(@config.database_path)
    end

    def items
      @items ||= Store::Items.new(db)
    end

    def entries
      @entries ||= Store::Entries.new(db)
    end

    def tags
      @tags ||= Store::Tags.new(db)
    end

    def relations
      @relations ||= Store::Relations.new(db)
    end

    def repos
      @repos ||= Store::Repositories.new(db)
    end

    def refs
      @refs ||= Store::References.new(db)
    end

    # Shared read-model for list/show/search/stats (PLAN 2).
    def queries
      @queries ||= Queries.new(db)
    end

    def author(by_option = nil)
      Author.resolve(@env, by_option)
    end

    def editor
      Editor.new(config: @config, stdin: @stdin)
    end

    # Resolve body text from --message / --stdin / editor (SPEC 14.1.3).
    def resolve_body(message:, use_stdin:, editor_seed: nil)
      InputSource.resolve(
        message: message, use_stdin: use_stdin, stdin: @stdin,
        editor: editor_seed.nil? ? nil : editor, initial: editor_seed.to_s
      )
    end

    # Resolve an item id argument ("42", "JM-42", ...) to an internal id.
    def item_id(arg)
      raise ArgError, "missing item id" if arg.nil?

      PublicId.normalize(arg)
    end

    # Emit a single item as JSON or human detail.
    def show_item(row)
      view = ItemView.new(row)
      if @output.json?
        @output.json(view.to_h)
      else
        view.render(@output)
      end
    end

    # Parse options with OptionParser; returns the leftover positional args.
    def parse_options(args)
      parser = OptionParser.new
      yield parser
      parser.parse(args)
    rescue OptionParser::ParseError => e
      raise ArgError, e.message
    end
  end
end
