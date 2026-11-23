module ApplicationImport
  class Runner
    # Records the rows' new errors in the result and applies on_error (action per code,
    # the worst wins; on_error.max_errors). Rows get pending through Row#add_error.
    module Settling
      SEVERITY = { allow: 0, skip: 1, abort: 2 }.freeze

      private

      # Settles only the rows that got new errors (Row#add_error marks them pending):
      # the given row first, then the others in line order. Every row's errors are
      # recorded before an abort halts.
      def settle_all(row = nil)
        rows = @pending_rows.to_a.sort_by(&:line)
        rows.unshift(rows.delete(row)) if row && rows.include?(row)
        actions = rows.map { |pending| settle(pending, halt: false) }
        halt! if actions.include?(:abort)
      end

      # Records the row's new errors and applies on_error; returns the action. With
      # halt: false an abort is only returned (the writer stops and the Runner halts).
      def settle(row, halt: true)
        @pending_rows.delete(row)
        errors = row.take_new_errors
        return if errors.empty?

        record_errors(row, errors)
        action = too_many_errors? ? :abort : row_action(errors)
        log_action(row, errors, action)
        halt! if action == :abort && halt
        row.skip! if action == :skip
        action
      end

      def log_action(row, errors, action)
        debug { "line #{row.line}: #{errors.map(&:code).join(", ")} -> #{action}" }
      end

      def record_errors(row, errors)
        result.increment(:invalid) if errors.size == row.errors.size
        errors.each { |error| result.add_error(error) }
        @row_error_count = @row_error_count.to_i + errors.size
      end

      # on_error.max_errors exceeded: recorded once as a file error; the import aborts.
      def too_many_errors?
        return false unless definition.on_error.too_many?(@row_error_count)
        return true if @too_many_errors

        @too_many_errors = true
        max = definition.on_error.max_errors
        result.add_file_error(:too_many_errors, "more than #{max} row errors, import stopped", details: { max_errors: max })
        true
      end

      def row_action(errors)
        errors.map { |error| definition.on_error.action_for(error.code) }.max_by { |action| SEVERITY.fetch(action) }
      end
    end
  end
end
