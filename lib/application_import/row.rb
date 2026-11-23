module ApplicationImport
  # A data row through the pipeline. read_file builds it with the header-mapped
  # attributes; process casts them, lets the handler map them, builds the record and
  # validates. Errors are collected on the row; the Runner records the new ones in the
  # result and applies on_error (take_new_errors).
  class Row
    attr_reader :line, :raw, :errors
    attr_accessor :attributes, :record

    def initialize(line:, attributes:, raw:, record: nil)
      @line = line
      @attributes = attributes
      @raw = raw
      @record = record
      @errors = []
      @recorded = 0
      @skipped = false
    end

    def add_error(code:, message:, column: nil, details: nil)
      errors << ErrorEntry.new(line:, column:, code: code.to_sym, message:, details:)
      self
    end

    # Errors added since the last call.
    def take_new_errors
      new_errors = errors.drop(@recorded)
      @recorded = errors.size
      new_errors
    end

    def errors?
      errors.any?
    end

    def skip!
      @skipped = true
      self
    end

    def skipped?
      @skipped
    end

    def to_h
      { line:, attributes:, raw:, record:, errors:, skipped: skipped? }
    end

    def ==(other)
      other.is_a?(Row) && other.to_h == to_h
    end
    alias_method :eql?, :==

    def hash
      to_h.hash
    end
  end
end
