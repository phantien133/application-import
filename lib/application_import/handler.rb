module ApplicationImport
  class Handler
    attr_reader :definition, :context

    def initialize(definition, context = {})
      @definition = definition
      @context = context
    end

    def validate_file(source, result); end

    def map_row(attributes, _raw)
      attributes
    end

    def validate_row(row, result); end

    def validate_rows(row, result); end

    def verify(rows, result); end

    def transform(rows)
      rows.map(&:attributes)
    end

    def write(records, writer)
      writer.call(records)
    end

    def after_import(result); end
  end
end
