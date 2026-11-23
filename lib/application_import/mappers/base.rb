module ApplicationImport
  module Mappers
    # Base of mappers: turns a row's attributes into the attributes the rest of the
    # import works with (validators, handler, record), e.g. renaming file columns to
    # model attributes. One mapper per definition, declared with `mapper:`:
    #   mapper:
    #     class: Imports::UserMapper    # other keys -> options
    # One instance per run, built with the definition, options, the run's context and
    # logger. Runs for each row after the transformers, before handler.map_row.
    #
    # #call(attributes, row) returns the new attributes Hash (it replaces the row's).
    # Its Symbol keys that are not declared columns are assigned to the record like
    # generated keys (when the model can set them). Report problems with row.add_error
    # or by raising Errors::RowError.
    class Base
      include Logging

      attr_reader :definition, :options, :context

      def initialize(definition, options = {}, context: {}, logger: ApplicationImport.logger)
        @definition = definition
        @options = options
        @context = context
        @logger = logger
      end

      def call(attributes, row)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
