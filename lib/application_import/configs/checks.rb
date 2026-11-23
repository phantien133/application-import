module ApplicationImport
  module Configs
    module Checks
      private

      def add_error(path, message)
        @errors << "#{path} #{message}"
        nil
      end

      def check_keys(hash, allowed, path)
        unknown = hash.keys - allowed
        add_error(path, "has unknown keys: #{unknown.join(", ")}") if unknown.any?
      end

      def mapping(value, path)
        return {} if value.nil?
        return value if value.is_a?(Hash)

        add_error(path, "must be a mapping") || {}
      end

      def one_of(value, allowed, path)
        return value.to_s.to_sym if allowed.include?(value.to_s)

        add_error(path, "must be one of #{allowed.join(", ")}")
      end

      def class_name(value, path)
        return if value.nil?
        return value.to_s if value.is_a?(String) && value.present?

        add_error(path, "must be a class name")
      end

      def integer(value, path, min: 1)
        return value if value.is_a?(Integer) && value >= min

        add_error(path, "must be an integer >= #{min}")
      end

      def boolean(value, path)
        return value if [ true, false ].include?(value)

        add_error(path, "must be true or false")
      end

      def names(value, path)
        list = Array.wrap(value)
        return list.map(&:to_s) if list.any? && list.all? { |item| item.is_a?(String) || item.is_a?(Symbol) }

        add_error(path, "must be a non-empty list of names") || []
      end

      def check_columns(keys, column_keys, path)
        unknown = keys - column_keys
        add_error(path, "references unknown columns: #{unknown.join(", ")}") if unknown.any?
      end

      def regexp(value, path)
        return if value.nil?

        Regexp.new(value.to_s, timeout: Constants::REGEXP_TIMEOUT)
      rescue RegexpError => e
        add_error(path, "is not a valid regexp: #{e.message}")
      end
    end
  end
end
