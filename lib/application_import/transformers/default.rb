module ApplicationImport
  module Transformers
    # type: default — sets a value when the attribute is missing: nil, a blank String or
    # an empty collection (false and 0 are values, kept).
    #   attribute: role   value: member
    class Default < Base
      def call(attributes, _row)
        key = options[:attribute]
        { key => options[:value] } if Transformers.missing?(attributes[key])
      end
    end
  end
end
