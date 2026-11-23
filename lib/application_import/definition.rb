module ApplicationImport
  class Definition
    attr_reader :name, :handler_class, :file, :columns, :validators, :output, :on_error

    class << self
      def load(name)
        path = Pathname(ApplicationImport.configuration.config_path).join("#{name}.yml")
        raise Errors::ConfigError, "import config not found: #{path}" unless path.file?

        new(name, YAML.safe_load_file(path) || {})
      rescue Psych::Exception => e
        raise Errors::ConfigError, "invalid YAML in #{path}: #{e.message}"
      end
    end

    def initialize(name, config)
      @name = name.to_sym
      parsed = Configs::DefinitionParser.new(@name, config).parse
      @handler_class = parsed[:handler]
      @file = parsed[:file]
      @columns = parsed[:columns]
      @validators = parsed[:validators]
      @output = parsed[:output]
      @on_error = parsed[:on_error]
      freeze
    end

    def file_validator_class
      file[:validator]
    end

    def abort_on_error?
      on_error == :abort
    end

    def max_rows
      file[:max_rows]
    end
  end
end
