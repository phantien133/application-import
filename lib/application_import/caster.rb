module ApplicationImport
  # Casts cell values for a run: blank values (nil, whitespace) become nil, other values
  # go to the column's caster — its `caster` option (a Casters::Base subclass) or the
  # built-in one for its type. One caster instance per column per run.
  # A value that cannot be cast raises Caster::Invalid with a message naming the column.
  class Caster
    class Invalid < StandardError; end

    # Explicit table (no dynamic dispatch on the type name); must cover COLUMN_TYPES.
    BUILT_IN = {
      string: "ApplicationImport::Casters::StringCaster",
      integer: "ApplicationImport::Casters::IntegerCaster",
      decimal: "ApplicationImport::Casters::DecimalCaster",
      boolean: "ApplicationImport::Casters::BooleanCaster",
      date: "ApplicationImport::Casters::DateCaster",
      datetime: "ApplicationImport::Casters::DatetimeCaster"
    }.freeze

    class << self
      def caster_class(column)
        column.options[:caster] || BUILT_IN.fetch(column.type) do
          raise Errors::ConfigError, "column #{column.key}: unknown type #{column.type.inspect}"
        end.constantize
      end
    end

    attr_reader :definition, :logger

    def initialize(definition, logger: ApplicationImport.logger)
      @definition = definition
      @logger = logger
      @casters = {}
    end

    # Only errors of the cast itself become invalid values; a caster that cannot be
    # built (a bug) raises as is.
    def call(column, value)
      return if blank?(value)

      caster = caster_for(column)
      begin
        caster.call(value)
      rescue ArgumentError, TypeError, RangeError
        raise Invalid, "#{column.header} must be #{caster.type_name}"
      end
    end

    def caster_for(column)
      @casters[column.key] ||= self.class.caster_class(column).new(column, definition:, logger:)
    end

    private

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
