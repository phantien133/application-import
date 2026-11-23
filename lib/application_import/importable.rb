module ApplicationImport
  module Importable
    extend ActiveSupport::Concern

    class_methods do
      def import_skip(*kinds)
        raise NotImplementedError, "#{name}.import_skip"
      end
    end
  end
end
