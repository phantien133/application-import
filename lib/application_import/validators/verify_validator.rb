module ApplicationImport
  module Validators
    class VerifyValidator < Base
      def call(rows, result, cache)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
