module ApplicationImport
  module Validators
    # Checks across rows: called for each row in file order. `cache` is the run's Hash
    # shared by every rows check (keep state under your own key, e.g. cache[:my_check]).
    class RowsValidator < Base
      def call(row, result, cache)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
