module ApplicationImport
  module Transformers
    # Base of transformers: classes you write to generate attributes from the attributes
    # a row already has (e.g. full_name from first / last name, a slug, a lookup id).
    # Declared in the definition like custom validators:
    #   transformers:
    #     - class: Imports::FullNameTransformer
    #       separator: " "                     # any other key -> options
    # One instance per run and entry, built with the definition, the options (keys
    # symbolized), the run's context (read-only) and logger.
    #
    # They run for each row after cast + column rules and before handler.map_row, in the
    # order declared. #call(attributes, row) returns a Hash merged into the row's
    # attributes (nil for nothing). Symbol keys the model can set are assigned to the
    # record like declared columns. Report problems with row.add_error or by raising
    # Errors::RowError (on_error applies; row_errors: first stops the row there).
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
