module ApplicationImport
  # Row transformers (see Transformers::Base).
  module Transformers
    class << self
      # nil, a blank String or an empty collection; false and 0 are values.
      def missing?(value)
        value.nil? || (value.is_a?(String) && value.strip.empty?) || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
