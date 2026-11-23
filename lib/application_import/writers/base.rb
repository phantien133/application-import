module ApplicationImport
  module Writers
    # Base of the writers. #call(rows) writes the kept rows and returns how many were
    # written.
    #
    # A row that cannot be written gets a not_saved error and on_failure (the Runner)
    # returns its on_error action: abort stops the writer. Writing never halts from
    # inside a transaction: the Runner halts once the writer returned (#aborted?).
    #
    # With output.transaction (default true) the whole write runs in one transaction
    # (requires_new, so it nests as a savepoint): an abort rolls it back
    # (ActiveRecord::Rollback) and nothing counts as written. Each record / batch also
    # runs in its own savepoint, so a database error on one does not break the others.
    class Base
      include Logging

      attr_reader :definition, :result

      def initialize(definition, result:, on_failure:, logger: ApplicationImport.logger)
        @definition = definition
        @result = result
        @on_failure = on_failure
        @logger = logger
        @aborted = false
      end

      def call(rows)
        return 0 if rows.empty?

        transaction? ? within_transaction { write(rows) } : write(rows)
      end

      def aborted?
        @aborted
      end

      private

      def write(rows)
        raise NotImplementedError, "#{self.class.name}#write"
      end

      def output
        definition.output
      end

      def model
        output[:model] || raise(Errors::ConfigError, "#{definition.name}: output.model is required to write records")
      end

      def transaction?
        output.fetch(:transaction, true)
      end

      def within_transaction
        written = 0
        model.transaction(requires_new: true) do
          written = yield
          raise ActiveRecord::Rollback if aborted?
        end
        aborted? ? 0 : written
      end

      def savepoint(&)
        model.transaction(requires_new: true, &)
      end

      def failed(row, message, details: nil)
        row.add_error(code: :not_saved, message:, details:)
        @aborted = true if @on_failure.call(row) == :abort
      end

      def record_of(row)
        row.record || raise(Errors::ConfigError, "#{definition.name}: row #{row.line} has no record to write")
      end
    end
  end
end
