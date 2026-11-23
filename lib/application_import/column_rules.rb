module ApplicationImport
  # Checks a cast value against its column options; returns [ code, message ] pairs.
  #   required             -> required        (nil value)
  #   min_length / max_length (strings) -> too_short / too_long
  #   min / max            -> too_small / too_big (numbers, dates, times)
  #   format               -> invalid_format  (regexp, or email)
  #   inclusion            -> not_included    (compared as strings)
  # Only required applies to nil.
  module ColumnRules
    module_function

    def errors(column, value)
      return column.required? ? [ [ :required, "#{column.header} is required" ] ] : [] if value.nil?

      options = column.options
      [
        *lengths(column, value, options), *bounds(column, value, options),
        *format(column, value, options), *inclusion(column, value, options)
      ]
    end

    def lengths(column, value, options)
      return [] unless value.is_a?(String)

      length = value.length
      errors = []
      if options[:min_length] && length < options[:min_length]
        errors << [ :too_short, "#{column.header} is too short (minimum is #{options[:min_length]} characters)" ]
      end
      if options[:max_length] && length > options[:max_length]
        errors << [ :too_long, "#{column.header} is too long (maximum is #{options[:max_length]} characters)" ]
      end
      errors
    end

    def bounds(column, value, options)
      errors = []
      errors << [ :too_small, "#{column.header} must be greater than or equal to #{options[:min]}" ] if options[:min] && value < options[:min]
      errors << [ :too_big, "#{column.header} must be less than or equal to #{options[:max]}" ] if options[:max] && value > options[:max]
      errors
    end

    def format(column, value, options)
      return [] if options[:format].nil? || options[:format].match?(value.to_s)

      [ [ :invalid_format, "#{column.header} has an invalid format" ] ]
    end

    def inclusion(column, value, options)
      allowed = options[:inclusion]
      return [] if allowed.nil? || allowed.map(&:to_s).include?(value.to_s)

      [ [ :not_included, "#{column.header} must be one of: #{allowed.join(", ")}" ] ]
    end
  end
end
