# frozen_string_literal: true

require "fileutils"

module JM
  module Commands
    # `jm backup`: snapshot the database with the SQLite online backup API into
    # a timestamped file next to the database (SPEC 20.1). Not a plain file copy.
    class Backup < Command
      private

      def perform(_args)
        source = db.db
        dir = File.join(File.dirname(@config.database_path), "backups")
        FileUtils.mkdir_p(dir)
        dest_path = File.join(dir, "jm-#{Clock.file_stamp}.sqlite3")

        copy(source, dest_path)
        emit(dest_path)
      end

      def copy(source, dest_path)
        dest = SQLite3::Database.new(dest_path)
        backup = SQLite3::Backup.new(dest, "main", source, "main")
        backup.step(-1)
        backup.finish
        dest.close
      end

      def emit(path)
        if @output.json?
          @output.json({ "backup" => path })
        else
          @output.line("Backed up to #{path}")
        end
      end
    end
  end
end
