# frozen_string_literal: true

module JM
  module Commands
    # `jm link A relation B` (SPEC 14.9). Input aliases and cycle checks are
    # handled by the store.
    class Link < Command
      private

      def perform(args)
        raise ArgError, "usage: jm link A <relation> B" unless args.length == 3

        a = item_id(args[0])
        relation = args[1]
        b = item_id(args[2])
        items.get(a)
        items.get(b)
        relations.add(a, b, relation)

        @output.line("Linked #{PublicId.format(a)} #{relation} #{PublicId.format(b)}") \
          unless @output.quiet?
      end
    end

    # `jm unlink A relation B`.
    class Unlink < Command
      private

      def perform(args)
        raise ArgError, "usage: jm unlink A <relation> B" unless args.length == 3

        a = item_id(args[0])
        relation = args[1]
        b = item_id(args[2])
        relations.remove(a, b, relation)

        @output.line("Unlinked #{PublicId.format(a)} #{relation} #{PublicId.format(b)}") \
          unless @output.quiet?
      end
    end

    # `jm links ID` lists an item's relations in both directions (SPEC 9.3).
    class Links < Command
      private

      def perform(args)
        raise ArgError, "usage: jm links ID" unless args.length == 1

        id = item_id(args[0])
        items.get(id)
        edges = relations.described_for(id).map do |e|
          { "relation" => e["relation"], "id" => PublicId.format(e["other_id"]),
            "title" => items.get(e["other_id"])["title"] }
        end
        emit(edges)
      end

      def emit(edges)
        if @output.json?
          @output.json(edges, list_key: "relations")
        elsif edges.empty?
          @output.line("(no relations)")
        else
          edges.each do |e|
            @output.line(format("%-12s %-9s %s", e["relation"], e["id"], e["title"]))
          end
        end
      end
    end
  end
end
