module ApplicationImport
  module Transformers
    # type: context — copies a value of the run's context into every row.
    #   key: user_id   to: created_by_id
    # A missing key gives nil.
    class Context < Base
      def call(_attributes, _row)
        key = options[:key]
        { options[:to] => context.fetch(key) { context[key.to_s] } }
      end
    end
  end
end
