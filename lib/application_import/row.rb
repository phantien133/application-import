module ApplicationImport
  # A data row through the pipeline. process builds it with the header-mapped
  # attributes, casts them, transforms / maps them, builds the record and validates.
  # Errors are collected on the row; the Runner records the new ones in the result and
  # applies on_error (take_new_errors).
  # pending: a Set (by identity) shared by the run's rows; add_error puts the row in it
  # so the Runner settles only rows that got new errors, wherever they were raised.
  class Row
    attr_reader :line, :raw, :errors, :generated_keys
    attr_accessor :attributes, :record

    def initialize(line:, attributes:, raw:, record: nil, pending: nil)
      @line = line
      @attributes = attributes
      @raw = raw
      @record = record
      @errors = []
      @generated_keys = []
      @recorded = 0
      @skipped = false
      @pending = pending
    end

    def add_error(code:, message:, column: nil, details: nil)
      errors << ErrorEntry.new(line:, column:, code: code.to_sym, message:, details:)
      @pending&.add(self)
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

    # Written in stream mode: the record is released, the row stays for line lookups.
    def release!
      @record = nil
      self
    end

    # A skipped row is never written: its record is released (memory); line, raw,
    # attributes and errors stay for error reporting and later line lookups.
    def skip!
      @skipped = true
      @record = nil
      self
    end

    def skipped?
      @skipped
    end

    def to_h
      { line:, attributes:, raw:, record:, errors:, generated_keys:, skipped: skipped? }
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
