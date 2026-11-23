module ApplicationImport
  class Definition
    attr_reader :name, :handler_class, :file, :columns, :transformers, :mapper, :validators, :output, :on_error

    class << self
      def normalize_name(name)
        return name.to_sym if (name.is_a?(String) || name.is_a?(Symbol)) && Constants::NAME_FORMAT.match?(name.to_s)

        raise Errors::ConfigError, "invalid import name: #{name.inspect}"
      end

      # Loads by import name (config_path/<name>.yml) or by explicit file path;
      # the name of a path-loaded definition is the file's basename.
      def load(source)
        name, path = locate(source)
        raise Errors::ConfigError, "import config not found: #{path}" unless path.file?

        build(name, YAML.safe_load_file(path) || {})
      rescue Psych::Exception => e
        raise Errors::ConfigError, "invalid YAML in #{path}: #{e.message}"
      end

      # Inline definition with the configured defaults applied.
      def build(name, config)
        new(name, ApplicationImport.configuration.with_defaults(config))
      end

      def locate(source)
        return locate_path(Rails.root.join(source.to_s)) if path?(source)

        name = normalize_name(source)
        [ name, ApplicationImport.configuration.config_path.join("#{name}.yml") ]
      end

      private

      def path?(source)
        source.is_a?(Pathname) || (source.is_a?(String) && Constants::YAML_EXTENSIONS.include?(File.extname(source)))
      end

      def locate_path(path)
        [ normalize_name(path.basename(path.extname).to_s), path ]
      end
    end

    SECTIONS = %i[ file columns transformers mapper validators output on_error ].freeze

    def initialize(name, config)
      @name = self.class.normalize_name(name)
      parsed = Configs::DefinitionParser.new(@name, config).parse
      @handler_class = parsed[:handler]
      SECTIONS.each { |section| instance_variable_set(:"@#{section}", parsed[section]) }
      freeze
    end

    def file_checker_class
      file[:checker]
    end

    # file.reader when configured, else the built-in reader for file.format.
    # file.reader when configured; else the built-in reader for the file's extension when
    # it is one of file.formats; else the one for file.format (csv by default).
    def reader_class(extension = nil)
      return file[:reader] if file[:reader]

      Readers.reader_class(format_for(extension) || file[:format])
    end

    def format_for(extension)
      file[:formats]&.find { |format| format.to_s == extension.to_s }
    end
  end
end
