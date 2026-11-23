module ApplicationImport
  module Mappers
    # type: rename — renames attribute keys, e.g. to match the model's attributes.
    #   attributes: { email: user_email, joined_on: created_at }
    #   only: false   (true: keep only the renamed attributes)
    class Rename < Base
      def call(attributes, _row)
        renames = options[:attributes]
        renamed = renames.each_with_object({}) { |(from, to), mapped| mapped[to] = attributes[from] if attributes.key?(from) }
        options[:only] ? renamed : attributes.except(*renames.keys).merge(renamed)
      end
    end
  end
end
