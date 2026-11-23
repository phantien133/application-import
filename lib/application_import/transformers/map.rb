module ApplicationImport
  module Transformers
    # type: map — replaces values through a table.
    #   attribute: role
    #   values: { "Quản trị": admin, "Thành viên": member }
    #   to: role_code          (default: the attribute itself)
    #   case_sensitive: false  (default; surrounding spaces ignored too)
    #   strict: false          (true: a value not in the table -> row error not_mapped)
    # Blank values are left alone.
    class Map < Base
      def call(attributes, row)
        key = options[:attribute]
        value = attributes[key]
        return if value.blank?

        found = table.fetch(normalize(value)) { return not_found(row, key, value) }
        { options.fetch(:to, key) => found }
      end

      private

      def table
        @table ||= options[:values].to_h { |from, to| [ normalize(from), to ] }
      end

      def normalize(value)
        text = value.to_s.strip
        options[:case_sensitive] ? text : text.downcase
      end

      def not_found(row, key, value)
        return unless options[:strict]

        row.add_error(code: :not_mapped, column: key, message: "#{key} #{value.inspect} is not one of: #{options[:values].keys.join(", ")}")
        nil
      end
    end
  end
end
