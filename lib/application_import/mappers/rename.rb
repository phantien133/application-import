module ApplicationImport
  module Mappers
    # type: rename — renames attribute keys, e.g. to match the model's attributes.
    #   attributes: { email: user_email, Phone: phone }
    #   only: false   (true: keep only the renamed attributes)
    # A source name matches a declared column / generated key (Symbol) or, failing that,
    # a header kept by unknown_headers keep / assign (String key, e.g. "Phone"): renaming
    # such a header is the explicit way to send it to the record.
    class Rename < Base
      def call(attributes, _row)
        renamed = {}
        sources = []
        options[:attributes].each do |from, to|
          source = source_key(attributes, from)
          next if source.nil?

          sources << source
          renamed[to] = attributes[source]
        end
        options[:only] ? renamed : attributes.except(*sources).merge(renamed)
      end

      private

      def source_key(attributes, from)
        return from if attributes.key?(from)

        from.to_s if attributes.key?(from.to_s)
      end
    end
  end
end
