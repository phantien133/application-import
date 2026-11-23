module ApplicationImport
  module Transformers
    # type: default — sets a value when the attribute is blank.
    #   attribute: role   value: member
    class Default < Base
      def call(attributes, _row)
        key = options[:attribute]
        { key => options[:value] } if attributes[key].blank?
      end
    end
  end
end
