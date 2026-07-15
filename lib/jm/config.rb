# frozen_string_literal: true

module JM
  # Resolves configuration from environment variables and an optional
  # config.toml. Environment variables take precedence over the file (SPEC 21).
  #
  # tomlrb is loaded lazily so that the tool still runs (e.g. `jm init`) before
  # `bundle install` has provided the gem; without it, the config file is simply
  # ignored.
  class Config
    def self.load(env: ENV)
      new(env: env)
    end

    def initialize(env: ENV)
      @env = env
      @file = read_config_file
    end

    # Absolute path to the SQLite database (SPEC 18.1).
    def database_path
      path = @env["JM_DATABASE"] || @file["database"] || default_database_path
      File.expand_path(path)
    end

    # Editor resolution order (SPEC 15): JM_EDITOR > config.editor > VISUAL >
    # EDITOR > platform default.
    def editor
      @env["JM_EDITOR"] || @file["editor"] || @env["VISUAL"] || @env["EDITOR"] ||
        default_editor
    end

    def defaults
      @file["defaults"] || {}
    end

    private

    def default_database_path
      File.join(data_home, "jm", "jm.sqlite3")
    end

    def config_file_path
      File.join(config_home, "jm", "config.toml")
    end

    def data_home
      @env["XDG_DATA_HOME"] || File.join(Dir.home, ".local", "share")
    end

    def config_home
      @env["XDG_CONFIG_HOME"] || File.join(Dir.home, ".config")
    end

    def default_editor
      # Reasonable cross-platform fallback; overridable via env/config.
      @env["OS"]&.include?("Windows") ? "notepad" : "vi"
    end

    def read_config_file
      path = config_file_path
      return {} unless File.exist?(path)

      require "tomlrb"
      Tomlrb.load_file(path)
    rescue LoadError
      # tomlrb not installed yet; run without a config file.
      {}
    end
  end
end
