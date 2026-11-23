module ApplicationImport
  # Global settings, built lazily on first use (see ApplicationImport.configuration):
  #   1. built-in defaults (config_path: config/imports, no definition defaults)
  #   2. SETTINGS_FILE when it exists (flat, or scoped by shared/<env> keys)
  #   3. ApplicationImport.configure { |config| ... } overrides
  # `defaults` are deep-merged under every definition YAML (definition values win).
  class Configuration
    SETTINGS_FILE = "config/imports/_config.yml".freeze
    KEYS = %w[ config_path defaults ].freeze
    DEFAULT_KEYS = %w[ handler file output on_error ].freeze
    ENV_KEYS = %w[ shared development test production ].freeze

    attr_reader :config_path, :defaults
    attr_writer :logger, :cache_definitions

    def initialize
      self.config_path = "config/imports"
      self.defaults = {}
    end

    # Set with `configure { |config| config.logger = ... }`; defaults to Rails.logger
    # (read on each call so a swapped Rails.logger is picked up).
    # Cache loaded definitions: set with configure; by default on when code is not
    # reloaded, except in the test environment (specs change definitions on disk).
    def cache_definitions?
      return @cache_definitions unless @cache_definitions.nil?

      !Rails.application.config.enable_reloading && !Rails.env.test?
    end

    def logger
      @logger || Rails.logger
    end

    # Relative paths resolve against Rails.root.
    def config_path=(path)
      @config_path = Rails.root.join(path.to_s)
    end

    def defaults=(value)
      raise Errors::ConfigError, "defaults must be a mapping" unless value.is_a?(Hash)

      value = value.deep_stringify_keys
      unknown = value.keys - DEFAULT_KEYS
      raise Errors::ConfigError, "defaults has unknown keys: #{unknown.join(", ")}" if unknown.any?

      @defaults = Ractor.make_shareable(value)
    end

    # Reads SETTINGS_FILE if present; a missing file keeps the built-in defaults.
    def load_settings
      path = Rails.root.join(SETTINGS_FILE)
      Rails.logger&.debug { "[ApplicationImport] settings #{path.file? ? "loaded from #{path}" : "file absent, built-in defaults"}" }
      path.file? ? load_file(path) : self
    end

    def load_file(path)
      path = Rails.root.join(path.to_s)
      raise Errors::ConfigError, "import settings not found: #{path}" unless path.file?

      apply(scoped(YAML.safe_load_file(path) || {}, path))
    rescue Psych::Exception => e
      raise Errors::ConfigError, "invalid YAML in #{path}: #{e.message}"
    end

    def apply(settings)
      raise Errors::ConfigError, "import settings must be a mapping" unless settings.is_a?(Hash)

      settings = settings.deep_stringify_keys
      unknown = settings.keys - KEYS
      raise Errors::ConfigError, "import settings have unknown keys: #{unknown.join(", ")}" if unknown.any?

      self.config_path = settings["config_path"] if settings.key?("config_path")
      self.defaults = settings["defaults"] if settings.key?("defaults")
      self
    end

    def with_defaults(config)
      return config if defaults.empty? || !config.is_a?(Hash)

      defaults.deep_merge(config.deep_stringify_keys)
    end

    private

    # Flat settings, or only environment sections (shared + the current env merged);
    # mixing both, or a section that is not a mapping, is an error. Empty sections are {}.
    def scoped(settings, path)
      raise Errors::ConfigError, "import settings must be a mapping: #{path}" unless settings.is_a?(Hash)

      sections = settings.keys & (ENV_KEYS + [ Rails.env ])
      return settings if sections.empty?

      flat = settings.keys - sections
      raise Errors::ConfigError, "import settings mix flat keys (#{flat.join(", ")}) with environment sections: #{path}" if flat.any?

      section(settings, "shared", path).deep_merge(section(settings, Rails.env, path))
    end

    def section(settings, name, path)
      value = settings[name] || {}
      raise Errors::ConfigError, "import settings section #{name} must be a mapping: #{path}" unless value.is_a?(Hash)

      value
    end
  end
end
