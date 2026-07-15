# frozen_string_literal: true

module JM
  module Commands
    # `jm repo add|list|show|edit|remove|link|unlink` (SPEC 8, 14.10).
    class Repo < Command
      private

      def perform(args)
        sub = args.shift
        dispatch = {
          "add" => :add, "list" => :list, "show" => :show, "edit" => :edit,
          "remove" => :remove, "link" => :link, "unlink" => :unlink
        }
        method = dispatch[sub]
        raise ArgError, "usage: jm repo <#{dispatch.keys.join("|")}> ..." if method.nil?

        send(method, args)
      end

      def add(args)
        name = args.shift
        path = args.shift
        raise ArgError, "usage: jm repo add NAME PATH" if name.nil? || path.nil?
        raise ArgError, "repository already exists: #{name}" if repos.find_by_name(name)

        row = repos.create(**detect(File.expand_path(path)), name: name)
        emit_repo(row, verb: "Added")
      end

      # Fill path/remote/default_branch from Git when available (SPEC 8.2).
      def detect(path)
        return { path: path } unless Git.repository?(path)

        { path: Git.toplevel(path) || path,
          remote_url: Git.remote_url(path),
          default_branch: Git.default_branch(path) }
      end

      def list(_args)
        rows = repos.list
        if @output.json?
          @output.json(rows.map { |r| repo_hash(r) }, list_key: "repositories")
        elsif rows.empty?
          @output.line("(no repositories)")
        else
          rows.each { |r| @output.line(format("%-20s %s", r["name"], r["path"])) }
        end
      end

      def show(args)
        row = repos.get_by_name(args.shift)
        if @output.json?
          @output.json(repo_hash(row))
        else
          %w[name path remote_url default_branch created_at updated_at].each do |k|
            @output.line("#{k}: #{row[k]}")
          end
        end
      end

      def edit(args)
        name = args.shift
        row = repos.get_by_name(name)
        fields = {}
        parse_options(args) do |o|
          o.on("--path P") { |v| fields["path"] = File.expand_path(v) }
          o.on("--remote-url U") { |v| fields["remote_url"] = v }
          o.on("--default-branch B") { |v| fields["default_branch"] = v }
        end
        raise ArgError, "nothing to edit" if fields.empty?

        emit_repo(repos.update(row["id"], fields), verb: "Updated")
      end

      def remove(args)
        row = repos.get_by_name(args.shift)
        repos.remove(row["id"])
        @output.line("Removed repository #{row["name"]} (items kept)") unless @output.quiet?
      end

      def link(args)
        id = item_id(args.shift)
        repo = repos.get_by_name(args.shift)
        items.get(id)
        repos.link(id, repo["id"])
        @output.line("Linked #{PublicId.format(id)} to #{repo["name"]}") unless @output.quiet?
      end

      def unlink(args)
        id = item_id(args.shift)
        repo = repos.get_by_name(args.shift)
        repos.unlink(id, repo["id"])
        @output.line("Unlinked #{PublicId.format(id)} from #{repo["name"]}") unless @output.quiet?
      end

      def repo_hash(row)
        row.reject { |k, _| k.is_a?(Integer) }
      end

      def emit_repo(row, verb:)
        if @output.json?
          @output.json(repo_hash(row))
        else
          @output.line("#{verb} repository #{row["name"]}")
        end
      end
    end
  end
end
