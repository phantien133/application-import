module ApplicationImport
  class Handler
    attr_reader :definition, :context

    def initialize(definition, context = {})
      @definition = definition
      @context = context
    end

    def validate_file_meta(source, errors); end

    def map_row(attributes, _raw)
      attributes
    end

    def validate_row(row); end

    def validate_file(rows, errors); end

    def verify(rows, errors); end

    def transform(rows)
      rows.map(&:attributes)
    end

    def write(records, writer)
      writer.call(records)
    end

    def after_import(result); end
  end
end
