# frozen_string_literal: true

module JM
  module Commands
    # `jm delete ID`: physically delete an item and its dependent rows via FK
    # cascade (SPEC 24). Requires confirmation unless --force; without a TTY and
    # without --force it errors rather than prompting (SPEC 14.1.1).
    class Delete < Command
      private

      def perform(args)
        force = false
        rest = parse_options(args) { |o| o.on("--force") { force = true } }
        id = item_id(rest.shift)
        raise ArgError, "too many arguments" unless rest.empty?

        row = items.get(id)
        confirm!(row) unless force

        db.db.execute("DELETE FROM items WHERE id = ?", [id])
        @output.line("Deleted #{PublicId.format(id)}") unless @output.quiet?
      end

      def confirm!(row)
        raise ArgError, "refusing to delete without --force (no TTY to confirm)" unless @stdin.tty?

        @output.stdout.print("Delete #{PublicId.format(row["id"])} \"#{row["title"]}\"? [y/N] ")
        answer = @stdin.gets.to_s.strip.downcase
        raise ArgError, "aborted" unless %w[y yes].include?(answer)
      end
    end
  end
end
