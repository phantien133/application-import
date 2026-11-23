module ApplicationImport
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def definition(name)
      Definition.load(name)
    end

    def run(definition_or_name, file, filename: nil, context: {}, runner: nil)
      definition = definition_or_name.is_a?(Definition) ? definition_or_name : definition(definition_or_name)
      ClassResolver.resolve!(runner, base: Runner, default: Runner, error: Errors::InvalidRunnerError).new(definition, Source.build(file, filename:), context:).call
    end
  end
end
