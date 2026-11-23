module ApplicationImport
  CONFIGURATION_LOCK = Mutex.new
  DEFINITIONS = Concurrent::Map.new

  class << self
    def configuration
      @configuration || CONFIGURATION_LOCK.synchronize { @configuration ||= Configuration.new }
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      CONFIGURATION_LOCK.synchronize { @configuration = Configuration.new }
    end

    def definition(name)
      return Definition.load(name) unless cache_definitions?

      DEFINITIONS.compute_if_absent(Definition.normalize_name(name)) { Definition.load(name) }
    end

    def clear_definitions!
      DEFINITIONS.clear
    end

    def cache_definitions?
      !Rails.application.config.enable_reloading
    end

    def run(definition_or_name, file, filename: nil, context: {}, runner: nil)
      definition = definition_or_name.is_a?(Definition) ? definition_or_name : definition(definition_or_name)
      ClassResolver.resolve!(runner, base: Runner, default: Runner, error: Errors::InvalidRunnerError).new(definition, Source.build(file, filename:), context:).call
    end
  end
end
