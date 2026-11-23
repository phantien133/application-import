module ApplicationImport
  module Casters
    # Base of every column caster, built-in or custom. One instance per run and column.
    # Implement #call(value) -> the cast value; call invalid! (or raise ArgumentError /
    # TypeError) when the value cannot be cast: the row gets an invalid_type error.
    # Blank values (nil, whitespace) never reach a caster: they become nil.
    #
    # Use a custom caster on a column with `caster: Imports::PhoneCaster`; `type` then
    # only describes the result for the column rules (min / max bounds, lengths).
    class Base
      include Logging

      attr_reader :column, :definition

      def initialize(column, definition:, logger: ApplicationImport.logger)
        @column = column
        @definition = definition
        @logger = logger
      end

      def call(value)
        raise NotImplementedError, "#{self.class.name}#call"
      end

      # How the expected value is named in the invalid_type message.
      def type_name
        "valid"
      end

      def invalid!(message = "#{column.header} must be #{type_name}")
        raise Caster::Invalid, message
      end
    end
  end
end
