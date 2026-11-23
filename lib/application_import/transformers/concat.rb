module ApplicationImport
  module Transformers
    # type: concat — joins attributes into a new one, skipping blank values.
    #   from: [ first_name, last_name ]   to: full_name   separator: " " (default)
    # All blank -> nil.
    class Concat < Base
      def call(attributes, _row)
        parts = options[:from].map { |key| attributes[key] }.compact_blank.map(&:to_s)
        { options[:to] => parts.presence&.join(options.fetch(:separator, " ")) }
      end
    end
  end
end
