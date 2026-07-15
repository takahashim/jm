# frozen_string_literal: true

module JM
  module Commands
    # `jm tag add|remove|list` (SPEC 14.12).
    class Tag < Command
      private

      def perform(args)
        sub = args.shift
        case sub
        when "add" then add(args)
        when "remove" then remove(args)
        when "list" then list(args)
        else
          raise ArgError, "usage: jm tag <add|remove|list> ..."
        end
      end

      def add(args)
        id = item_id(args.shift)
        names = args
        raise ArgError, "no tags given" if names.empty?

        names.each { |name| tags.add(id, name) }
        report(id)
      end

      def remove(args)
        id = item_id(args.shift)
        names = args
        raise ArgError, "no tags given" if names.empty?

        names.each { |name| tags.remove(id, name) }
        report(id)
      end

      def report(id)
        current = tags.for_item(id)
        if @output.json?
          @output.json({ "item" => PublicId.format(id), "tags" => current })
        else
          @output.line("#{PublicId.format(id)} tags: #{current.join(", ")}")
        end
      end

      def list(_args)
        rows = tags.all_with_counts
        if @output.json?
          @output.json(rows.map { |r| { "name" => r["name"], "count" => r["count"] } },
                       list_key: "tags")
        elsif rows.empty?
          @output.line("(no tags)")
        else
          rows.each { |r| @output.line(format("%-20s %d", r["name"], r["count"])) }
        end
      end
    end
  end
end
