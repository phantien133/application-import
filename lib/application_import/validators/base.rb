module ApplicationImport
  module Validators
    # Base of every validator (built-in or custom). One instance per run and stage
    # entry, built with the definition, the options from YAML (keys symbolized, minus
    # type/class), the run's context (read-only caller input) and logger.
    #
    # Stage signatures (subclass the stage base):
    #   FileValidator#call(source, result)        add file errors to the result
    #   RowValidator#call(row, result)            one row on its own
    #   RowsValidator#call(row, result, cache)    each row in file order, across rows
    #   VerifyValidator#call(rows, result, cache) once on the kept rows (cache of the rows checks)
    # Report with row.add_error(code:, message:, column:) or by raising
    # Errors::RowError / Errors::RowsError.
    class Base
      include Logging

      attr_reader :definition, :options, :context

      def initialize(definition, options = {}, context: {}, logger: ApplicationImport.logger)
        @definition = definition
        @options = options
        @context = context
        @logger = logger
      end

      def call(*)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
