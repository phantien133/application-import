module ApplicationImport
  class Runner
    # The row pipeline of the Runner.
    #
    # process streams the reader; for each data row:
    #   build (header map) -> cast (types + column rules, one check for all columns)
    #   -> transformers (one check each, generated attributes merged)
    #   -> map (mapper, handler.map_row, handler.build_record)
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
    #
    # Memory: every row read stays until the end (verify and write need the kept rows,
    # line lookups need all); skipped rows drop their record.
    module Rows
      # Rows kept so far (skipped ones are dropped), in file order.
      def rows
        @rows_by_line.values.reject(&:skipped?)
      end

      private

      def process
        reader.each { |raw| process_row(raw) }
        warn_extra_cells_total
        info("processed #{result.stats[:total]} rows from #{source.filename}")
      end

      def process_row(raw)
        row = build_row(raw)
        row_checks(row).each do |check|
          check.call
          break if stop_row?(row)
        end
        settle_all(row)
        stream(row) if streaming?
      end

      # row_errors: first stops the row at the first check reporting an error that is
      # not allowed (skip or abort); allowed errors let the row go on (it is written).
      def stop_row?(row)
        return false if definition.on_error.collect_all? || !row.errors?

        row.errors.any? { |error| definition.on_error.action_for(error.code) != :allow }
      end

      # The steps of one row, in order; each may report errors on the row.
      def row_checks(row)
        [ -> { check_extra_cells(row) }, -> { guard(Caster) { cast_row(row) } }, *transformer_checks(row),
          -> { map_row(row) }, *row_stage(row), *rows_stage(row) ]
      end

      # mapper (if any) -> handler.map_row -> handler.build_record; errors raised by the
      # mapper or the handler are attributed to them.
      def map_row(row)
        guard((mapper || handler).class) do
          apply_mapper(row) if mapper
          row.attributes = handler.map_row(row.attributes, row)
          row.record = handler.build_record(row.attributes, row)
        end
      end

      def apply_mapper(row)
        mapped = mapper.call(row.attributes, row)
        raise TypeError, "#{mapper.class.name}#call must return a Hash" unless mapped.is_a?(Hash)

        row.attributes = mapped
        row.generated_keys.concat(mapped.keys.grep(Symbol) - column_keys).uniq!
      end

      def column_keys
        @column_keys ||= definition.columns.map(&:key)
      end

      # cache: the same Hash the rows checks filled, e.g. keys collected for one query.
      # It may hold data of rows skipped later: filter by `rows` when it matters.
      # Not a step with output.stream: rows are already written.
      def verify
        kept = rows
        validators(:verify).each { |validator| guard(validator.class) { validator.call(kept, result, cache) } }
        guard(handler.class) { handler.verify(kept, result, cache) }
        settle_all
      end

      # Writes the kept rows with handler.write and the writer for output.mode. Not named
      # `import` on purpose: activerecord-import adds Model.import. A write failure is a
      # not_saved row error settled without halting inside the writer's transaction;
      # an abort halts once the writer returned.
      def write_rows
        write_batch(streaming? ? unwritten_rows : rows)
      end

      def write_batch(batch)
        written = handler.write(batch, writer)
        result.increment(:written, written)
        batch.each(&:release!) if streaming?
        halt! if writer.aborted?
      end

      def writer
        @writer ||= Writers.for(definition, result:, logger:, on_failure: ->(row) { settle(row, halt: false) })
      end

      # Turns raised row errors into errors on the rows of their lines, in every stage.
      # A line where no data row starts is a bug in the code that raised it:
      # Errors::UnknownLineError (source = that class), never attached elsewhere.
      def guard(source = nil)
        yield
      rescue Errors::RowError => e
        target(e.line, source).add_error(code: e.code, message: e.message, column: e.column)
      rescue Errors::RowsError => e
        add_rows_error(e, source)
      end

      def add_rows_error(error, source)
        details = { lines: error.lines, columns: error.columns }
        targets = error.lines.map { |line| target(line, source) }
        targets.each { |row| row.add_error(code: error.code, message: error.message, column: error.columns.first, details:) }
      end

      def target(line, source)
        @rows_by_line[line] || raise(Errors::UnknownLineError.new(line:, source: source&.name))
      end
    end
  end
end
