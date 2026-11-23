module ApplicationImport
  class Runner
    # First checks of each row in Runner::Rows: cells beyond the headers
    # (file.extra_cells) and casting + column rules.
    module RowMapping
      private

      # Cells beyond the headers stay in row.raw; file.extra_cells decides:
      # warn (default) logs the first such row and a total, ignore says nothing,
      # reject is a file error that halts at once (like the file checker's).
      def check_extra_cells(row)
        extra = @header_map.extra_cells(row.raw)
        return if extra.empty?

        case definition.file[:extra_cells]
        when :ignore then nil
        when :reject then reject_extra_cells(row, extra)
        else note_extra_cells(row, extra)
        end
      end

      def reject_extra_cells(row, extra)
        result.add_file_error(:extra_cells, "line #{row.line} has #{extra.size} cells more than the headers",
          details: { line: row.line, cells: extra.to_h { |index, value| [ index + 1, value ] } })
        halt!
      end

      def note_extra_cells(row, extra)
        @extra_cell_rows = @extra_cell_rows.to_i + 1
        return unless @extra_cell_rows == 1

        warn("line #{row.line} has #{extra.size} cells more than the headers: kept in row.raw only (file.extra_cells: warn)")
      end

      def warn_extra_cells_total
        warn("#{@extra_cell_rows} rows have cells more than the headers") if @extra_cell_rows.to_i > 1
      end

      # One check for the whole row: every declared column is cast and checked against
      # its rules (errors of all columns are collected); kept unknown headers are left as is.
      def cast_row(row)
        definition.columns.each do |column|
          next unless row.attributes.key?(column.key)

          cast_column(row, column)
        end
      end

      def cast_column(row, column)
        key = column.key
        raw = row.attributes[key]
        value = row.attributes[key] = caster.call(column, raw)
        ColumnRules.errors(column, value).each { |code, message| row.add_error(code:, message:, column: key) }
      rescue Caster::Invalid => e
        row.add_error(code: :invalid_type, message: e.message, column: key, details: { value: raw })
      end

      def caster
        @caster ||= Caster.new(definition, logger:)
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
    end
  end
end
