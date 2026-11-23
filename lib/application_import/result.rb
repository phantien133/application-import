module ApplicationImport
  class Result
    include Constants

    attr_reader :records, :errors, :stats

    # dry_run: the run's database changes were rolled back (stats say what would have
    # been written).
    def initialize(dry_run: false)
      @records = []
      @errors = []
      @stats = EMPTY_STATS.dup
      @halted = false
      @dry_run = dry_run
    end

    def dry_run?
      @dry_run
    end

    def add_error(error)
      errors << error
      self
    end

    def add_file_error(code, message, details: nil)
      add_error(ErrorEntry.for_file(code, message, details:))
    end

    def add_row_error(line:, code:, message:, column: nil, details: nil)
      add_error(ErrorEntry.new(line:, column:, code:, message:, details:))
    end

    def add_exception(error)
      case error
      when Errors::RowsError then add_rows_exception(error)
      when Errors::RowError
        add_row_error(line: error.line, column: error.column, code: error.code, message: error.message)
      when Errors::FileError then add_file_error(error.code, error.message)
      else raise ArgumentError, "unsupported error: #{error.class}"
      end
    end

    def add_rows_exception(error)
      add_row_error(line: error.lines.first, column: error.columns.first, code: error.code, message: error.message,
        details: { lines: error.lines, columns: error.columns })
    end

    def add_records(new_records)
      records.concat(new_records)
      self
    end

    def increment(key, by = 1)
      stats[key] += by
      self
    end

    def file_errors?
      errors.any?(&:file_level?)
    end

    def halt!
      @halted = true
      self
    end

    def halted?
      @halted
    end

    def status
      return FAILED if halted?

      errors.empty? ? COMPLETED : COMPLETED_WITH_ERRORS
    end

    def success?
      status == COMPLETED
    end

    def failed?
      status == FAILED
    end

    def to_h
      { status:, dry_run: dry_run?, stats:, errors: errors.map(&:to_h), records: }
    end
  end
end
