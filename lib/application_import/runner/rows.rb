module ApplicationImport
  class Runner
    # The row pipeline of the Runner.
    #
    # process streams the reader; for each data row:
    #   build (header map) -> map (handler.map_row, handler.build_record)
    #   -> row checks (row validators, handler.validate_row; each row on its own)
    #   -> rows checks (rows validators, handler.validate_rows; across rows, called per
    #      row in file order with the run's cache: a Hash, empty at start, shared by every
    #      rows check of this run, e.g. for seen keys or preloaded lookups; the caller's
    #      context stays read-only)
    #   on_error.row_errors: first (default) stops the row after the first check that
    #   reports errors; all runs every check of the row and collects its errors. Then the
    #   errors are settled at once: recorded in the result, on_error applied (abort
    #   halts, skip drops the row, allow keeps it; the worst action wins).
    # verify then runs once on the kept rows (verify validators, handler.verify), and
    # write_rows writes them (handler.write with the writer for output.mode).
    #
    # Checks report with row.add_error or by raising Errors::RowError (its row, or the
    # row of its line) / Errors::RowsError (every row of its lines).
    module Rows
      SEVERITY = { allow: 0, skip: 1, abort: 2 }.freeze

      # Rows kept so far (skipped ones are dropped), in file order.
      def rows
        @rows_by_line.values.reject(&:skipped?)
      end

      private

      def process
        reader.each { |raw| process_row(raw) }
        info("processed #{result.stats[:total]} rows from #{source.filename}")
      end

      def process_row(raw)
        row = build_row(raw)
        row_checks(row).each do |check|
          check.call
          break if row.errors? && !definition.on_error.collect_all?
        end
        settle_all(row)
      end

      # The steps of one row, in order; each may report errors on the row.
      def row_checks(row)
        [ -> { map_row(row) }, *row_stage(row), *rows_stage(row) ]
      end

      def row_stage(row)
        checks = validators(:row).map { |validator| -> { guard(row) { validator.call(row, result) } } }
        checks << -> { guard(row) { handler.validate_row(row, result) } }
      end

      def rows_stage(row)
        checks = validators(:rows).map { |validator| -> { guard(row) { validator.call(row, result, cache) } } }
        checks << -> { guard(row) { handler.validate_rows(row, result, cache) } }
      end

      # A custom reader that never calls on_headers gets its headers mapped at the first row.
      def build_row(raw)
        map_headers(Array(reader.headers)) unless @header_map
        result.increment(:total)
        row = Row.new(line: raw.line, attributes: @header_map.attributes(raw.values), raw: raw.values)
        @rows_by_line[row.line] = row
      end

      def map_row(row)
        row.attributes = handler.map_row(row.attributes, row)
        row.record = handler.build_record(row.attributes, row)
      end

      def verify
        kept = rows
        validators(:verify).each { |validator| guard { validator.call(kept, result) } }
        guard { handler.verify(kept, result) }
        settle_all
      end

      # Writers come next (output.mode raw / save / bulk). Not named `import` on purpose:
      # activerecord-import adds Model.import, and the step must not be mistaken for it.
      def write_rows
        raise NotImplementedError, "#{self.class.name}#write_rows"
      end

      # Turns raised row errors into errors on the rows they concern.
      def guard(row = nil)
        yield
      rescue Errors::RowError => e
        target(e.line, row).add_error(code: e.code, message: e.message, column: e.column)
      rescue Errors::RowsError => e
        add_rows_error(e, row)
      end

      def add_rows_error(error, row)
        details = { lines: error.lines, columns: error.columns }
        error.lines.each do |line|
          target(line, row).add_error(code: error.code, message: error.message, column: error.columns.first, details:)
        end
      end

      def target(line, row)
        @rows_by_line[line] || row || raise(ArgumentError, "no row on line #{line}")
      end

      # Settles the given row first, then any other row that got new errors.
      def settle_all(row = nil)
        settle(row) if row
        @rows_by_line.each_value { |other| settle(other) unless other.equal?(row) }
      end

      def settle(row)
        errors = row.take_new_errors
        return if errors.empty?

        result.increment(:invalid) if errors.size == row.errors.size
        errors.each { |error| result.add_error(error) }
        case row_action(errors)
        when :abort then halt!
        when :skip then row.skip!
        end
      end

      def row_action(errors)
        errors.map { |error| definition.on_error.action_for(error.code) }.max_by { |action| SEVERITY.fetch(action) }
      end
    end
  end
end
