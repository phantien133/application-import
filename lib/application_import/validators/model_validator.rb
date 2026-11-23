module ApplicationImport
  module Validators
    class ModelValidator < RowValidator
      def call(row, result)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
