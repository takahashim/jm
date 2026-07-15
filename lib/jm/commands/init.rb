# frozen_string_literal: true

module JM
  module Commands
    # Create the database (if needed) and apply pending migrations. This is one
    # of the only commands allowed to change the schema (SPEC 18.2).
    class Init
      def initialize(output:, config:, env: ENV, stdin: $stdin)
        @output = output
        @config = config
        @env = env
        @stdin = stdin
      end

      def run(_args)
        path = @config.database_path
        existed = File.exist?(path)

        db = Database.setup(path)
        db.close

        if @output.json?
          @output.json({ "path" => path, "created" => !existed })
        elsif existed
          @output.line("Database ready at #{path}")
        else
          @output.line("Initialized database at #{path}")
        end
      end
    end
  end
end
