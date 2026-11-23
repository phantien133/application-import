module ApplicationImport
  CONFIGURATION_LOCK = Mutex.new
  DEFINITIONS = Concurrent::Map.new

  class << self
    def configuration
      @configuration || CONFIGURATION_LOCK.synchronize { @configuration ||= Configuration.new.load_settings }
    end

    def logger
      configuration.logger
    end

    def configure
      yield configuration
      clear_definitions!
    end

    # Drops the configuration; the next access rebuilds it (re-reading the settings file).
    def reset_configuration!
      CONFIGURATION_LOCK.synchronize { @configuration = nil }
      clear_definitions!
    end

    # `source` is an import name (config_path/<name>.yml) or a definition file path
    # (Pathname, or a String ending in .yml/.yaml; relative to Rails.root).
    # Loads outside the cache's lock (YAML IO, class resolution, schema reads must not
    # serialize other loads or deadlock on a nested call); the first stored wins.
    def definition(source)
      return Definition.load(source) unless cache_definitions?

      key = Definition.locate(source).last.to_s
      DEFINITIONS.fetch(key) { DEFINITIONS.put_if_absent(key, Definition.load(source)) || DEFINITIONS[key] }
    end

    def clear_definitions!
      DEFINITIONS.clear
    end

    def cache_definitions?
      configuration.cache_definitions?
    end

    # `logger:` overrides the configured logger for this run only.
    # dry_run: every step runs, writes included, then the changes are rolled back.
    def run(definition_or_name, file, filename: nil, context: {}, runner: nil, logger: nil, dry_run: false)
      definition = definition_or_name.is_a?(Definition) ? definition_or_name : definition(definition_or_name)
      runner_class = ClassResolver.resolve!(runner, base: Runner, default: Runner, error: Errors::InvalidRunnerError)
      runner_class.new(definition, Source.build(file, filename:), context:, logger: logger || self.logger, dry_run:).call
    end
  end
end
