# frozen_string_literal: true

module JM
  module Commands
    # Set an item's priority (SPEC 12): `jm priority ID <value|alias>`.
    class Priority < Command
      private

      # No OptionParser here: the value may be a negative number ("-5"), which
      # OptionParser would treat as an option flag.
      def perform(args)
        id = item_id(args[0])
        value = args[1]
        raise ArgError, "usage: jm priority ID <value|alias>" if value.nil?
        raise ArgError, "too many arguments" if args.length > 2

        items.get(id)
        row = items.update(id, "priority" => Parse.priority(value))
        emit(row)
      end

      def emit(row)
        if @output.json?
          @output.json(ItemView.new(row).to_h)
        else
          @output.line("#{PublicId.format(row["id"])} priority #{row["priority"]}")
        end
      end
    end
  end
end
