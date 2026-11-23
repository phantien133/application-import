module ApplicationImport
  module Transformers
    # type: normalize — cleans String attributes, operations applied in order.
    #   attributes: [ email, name ]   with: [ strip, downcase ]   (strip downcase upcase squish)
    # Non-String values are left alone.
    class Normalize < Base
      OPERATIONS = %w[ strip downcase upcase squish ].freeze

      def call(attributes, _row)
        options[:attributes].each_with_object({}) do |key, changed|
          value = attributes[key]
          changed[key] = options[:with].reduce(value) { |text, operation| text.public_send(operation) } if value.is_a?(String)
        end
      end
    end
  end
end
