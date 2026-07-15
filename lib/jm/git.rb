# frozen_string_literal: true

require "open3"

module JM
  # Thin best-effort wrapper over the `git` CLI (SPEC 24). Auto-detection
  # methods return nil outside a repo; explicit resolution raises GitError.
  module Git
    module_function

    def repository?(dir)
      run(dir, "rev-parse", "--is-inside-work-tree").first&.strip == "true"
    end

    def toplevel(dir)
      out, ok = run(dir, "rev-parse", "--show-toplevel")
      ok ? out.strip : nil
    end

    def remote_url(dir)
      out, ok = run(dir, "config", "--get", "remote.origin.url")
      ok && !out.strip.empty? ? out.strip : nil
    end

    # Best-effort default branch from origin/HEAD, else the current branch.
    def default_branch(dir)
      out, ok = run(dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
      return out.strip.sub(%r{\Aorigin/}, "") if ok && !out.strip.empty?

      out, ok = run(dir, "rev-parse", "--abbrev-ref", "HEAD")
      ok && !out.strip.empty? ? out.strip : nil
    end

    # Resolve a ref (e.g. "HEAD", short SHA) to a full commit SHA. Raises on
    # failure so a bad ref is not silently stored (SPEC 10.4 / 24.1).
    def resolve_commit(dir, ref)
      out, ok = run(dir, "rev-parse", "--verify", "#{ref}^{commit}")
      raise GitError, "cannot resolve commit #{ref.inspect} in #{dir}" unless ok

      out.strip
    end

    # Make an absolute path relative to `base` (a repo top level), for
    # move-resilient file refs (SPEC 10.3). Both sides are canonicalized so
    # symlinked roots (e.g. macOS /var -> /private/var) still match. Returns the
    # path unchanged when it is not under base.
    def relativize(base, absolute_path)
      root = canonical(base)
      abs = canonical(absolute_path)
      return absolute_path unless abs.start_with?("#{root}/")

      abs[(root.length + 1)..]
    end

    # Resolve symlinks; if the path itself is missing, resolve its parent and
    # re-append the basename so non-existent files still canonicalize.
    def canonical(path)
      File.realpath(path)
    rescue Errno::ENOENT
      File.join(canonical(File.dirname(path)), File.basename(path))
    end

    def run(dir, *)
      out, status = Open3.capture2e("git", "-C", dir.to_s, *)
      [out, status.success?]
    rescue SystemCallError => e
      raise GitError, "failed to run git: #{e.message}"
    end
  end
end
