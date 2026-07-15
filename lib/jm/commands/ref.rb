# frozen_string_literal: true

module JM
  module Commands
    # `jm ref add|list|remove` (SPEC 10). Commit refs resolve to a full SHA and
    # file refs are stored relative to the repository (SPEC 10.3 / 10.4).
    class Ref < Command
      private

      def perform(args)
        sub = args.shift
        case sub
        when "add" then add(args)
        when "list" then list(args)
        when "remove" then remove(args)
        else
          raise ArgError, "usage: jm ref <add|list|remove> ..."
        end
      end

      def add(args)
        opts = {}
        rest = parse(args, opts)
        id = item_id(rest.shift)
        kind = rest.shift
        value = rest.shift
        raise ArgError, "usage: jm ref add ID KIND VALUE [--repo NAME]" if kind.nil? || value.nil?
        raise ArgError, "too many arguments" unless rest.empty?

        items.get(id)
        repo = opts[:repo] ? repos.get_by_name(opts[:repo]) : nil
        value = transform_value(kind, value, repo)

        row = refs.add(item_id: id, kind: kind, value: value,
                       repository_id: repo && repo["id"], label: opts[:label])
        emit_added(id, row)
      end

      def parse(args, opts)
        parse_options(args) do |o|
          o.on("--repo NAME") { |v| opts[:repo] = v }
          o.on("--label L") { |v| opts[:label] = v }
        end
      end

      # commit -> full SHA; file -> repo-relative path; otherwise verbatim.
      # File paths are given relative to the current directory and stored
      # relative to the repository top level (SPEC 10.3 / 28.6).
      def transform_value(kind, value, repo)
        case kind
        when "commit"
          Git.resolve_commit(repo_dir(repo), value)
        when "file"
          base = repo&.fetch("path", nil) || Git.toplevel(Dir.pwd) || Dir.pwd
          Git.relativize(base, File.expand_path(value, Dir.pwd))
        else value
        end
      end

      def repo_dir(repo)
        repo && repo["path"] ? repo["path"] : Dir.pwd
      end

      def list(args)
        id = item_id(args.shift)
        rows = refs.list(id)
        if @output.json?
          @output.json(rows.map { |r| ref_hash(r) }, list_key: "references")
        elsif rows.empty?
          @output.line("(no references)")
        else
          rows.each { |r| @output.line(ref_line(r)) }
        end
      end

      def remove(args)
        id = item_id(args.shift)
        ref_id = Integer(args.shift.to_s, 10)
        refs.remove(id, ref_id)
        @output.line("Removed reference ##{ref_id} from #{PublicId.format(id)}") \
          unless @output.quiet?
      rescue ArgumentError
        raise ArgError, "usage: jm ref remove ID REF_ID"
      end

      def ref_line(row)
        repo = row["repository_id"] ? " @#{repos.get(row["repository_id"])["name"]}" : ""
        format("#%-4d %-8s %s%s", row["id"], row["kind"], row["value"], repo)
      end

      def ref_hash(row)
        h = row.reject { |k, _| k.is_a?(Integer) }
        h["repository"] = repos.get(row["repository_id"])["name"] if row["repository_id"]
        h
      end

      def emit_added(id, row)
        if @output.json?
          @output.json(ref_hash(row))
        else
          @output.line("Added #{row["kind"]} reference ##{row["id"]} to #{PublicId.format(id)}")
        end
      end
    end
  end
end
