module ApplicationImport
  class Definition
    attr_reader :name, :handler_class, :file, :columns, :validators, :output, :on_error

    class << self
      def normalize_name(name)
        return name.to_sym if (name.is_a?(String) || name.is_a?(Symbol)) && Constants::NAME_FORMAT.match?(name.to_s)

        raise Errors::ConfigError, "invalid import name: #{name.inspect}"
      end

      def load(name)
        path = Pathname(ApplicationImport.configuration.config_path).join("#{normalize_name(name)}.yml")
        raise Errors::ConfigError, "import config not found: #{path}" unless path.file?

        new(name, YAML.safe_load_file(path) || {})
      rescue Psych::Exception => e
        raise Errors::ConfigError, "invalid YAML in #{path}: #{e.message}"
      end
    end

    def initialize(name, config)
      @name = self.class.normalize_name(name)
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

    def max_rows
      file[:max_rows]
    end
  end
end
