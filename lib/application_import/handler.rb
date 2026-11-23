module ApplicationImport
  # Per-import hooks called by the Runner. Every hook has a working default, so a
  # definition needs no handler of its own; subclass and override only what differs.
  #
  # Order (see Runner::Rows), streaming each data row:
  #   map_row -> build_record -> (row validators) -> validate_row
  #   -> (rows validators) -> validate_rows
  # then once the whole file is read, on the kept rows: (verify validators) -> verify
  # -> write; after_import always runs last.
  #
  # Validation hooks report problems with row.add_error(code:, message:, column:) or by
  # raising Errors::RowError / Errors::RowsError; the Runner applies on_error to them.
  class Handler
    attr_reader :definition, :context

    def initialize(definition, context = {})
      @definition = definition
      @context = context
    end

    # Before reading: extra checks on the file itself. Add file errors to the result.
    def validate_file(source, result); end

    # Cast attributes of one row -> attributes to build the record from.
    def map_row(attributes, _row)
      attributes
    end

    # The record to validate and write: a new output.model with the declared columns
    # assigned (only those the model can set), or nil without output.model.
    # Attributes of kept unknown headers (String keys) are never assigned here, so a
    # file cannot set arbitrary model attributes; use them in an override if needed.
    def build_record(attributes, _row)
      model = definition.output[:model]
      return unless model

      record = model.new
      record.assign_attributes(assignable(record, attributes))
      record
    end

    # Checks of one row on its own.
    def validate_row(row, result); end

    # Checks across rows, called for each row in file order right after validate_row.
    # `cache` is a Hash for this run, empty at start and shared with the rows validators:
    # keep what you need from previous rows there (e.g. cache[:emails] ||= Set.new).
    # The caller's context (#context) is read-only input.
    def validate_rows(row, result, cache); end

    # Empty on purpose: the place for import-wide checks of your own (e.g. totals,
    # references between rows or to the database) before anything is written.
    def verify(rows, result); end

    # Writes the kept rows with the writer for output.mode; returns the written count.
    def write(rows, writer)
      writer.call(rows)
    end

    def after_import(result); end

    private

    def assignable(record, attributes)
      definition.columns.each_with_object({}) do |column, assignable|
        key = column.key
        assignable[key] = attributes[key] if attributes.key?(key) && record.respond_to?("#{key}=")
      end
    end
  end
end
