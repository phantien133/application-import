module ApplicationImport
  # One writer per output.mode, called by Handler#write (Runner step write_rows).
  module Writers
    WRITERS = {
      raw: "ApplicationImport::Writers::Raw",
      save: "ApplicationImport::Writers::Save",
      bulk: "ApplicationImport::Writers::Bulk"
    }.freeze

    class << self
      def for(definition, result:, on_failure:, logger: ApplicationImport.logger)
        mode = definition.output[:mode] || :raw
        WRITERS.fetch(mode) { raise Errors::ConfigError, "no writer for output.mode #{mode}" }
          .constantize.new(definition, result:, on_failure:, logger:)
      end
    end
  end
end
