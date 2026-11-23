module ApplicationImport
  # Checks a cast value against its column options; returns [ code, message ] pairs.
  #   required             -> required        (nil value)
  #   min_length / max_length (strings) -> too_short / too_long
  #   min / max            -> too_small / too_big (numbers, dates, times)
  #   format               -> invalid_format  (regexp, or email; matched on the file text)
  #   inclusion            -> not_included    (numbers compared as numbers, else as strings)
  # Only required applies to nil.
  # Rules check the value as read from the file (after cast, before transformers and the
  # mapper): they describe the file. Checks on transformed values belong in validators.
  module ColumnRules
    module_function

    # raw: the cell as read (format is matched on it, stripped); the cast value otherwise.
    def errors(column, value, raw: nil)
      return column.required? ? [ [ :required, "#{column.header} is required" ] ] : [] if value.nil?

      options = column.options
      text = raw.is_a?(String) ? raw.strip : value.to_s
      [
        *lengths(column, value, options), *bounds(column, value, options),
        *format(column, text, options), *inclusion(column, value, options)
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

    def format(column, text, options)
      return [] if options[:format].nil? || options[:format].match?(text)

      [ [ :invalid_format, "#{column.header} has an invalid format" ] ]
    end

    def inclusion(column, value, options)
      allowed = options[:inclusion]
      return [] if allowed.nil? || allowed.any? { |option| same?(option, value) }

      [ [ :not_included, "#{column.header} must be one of: #{allowed.join(", ")}" ] ]
    end

    # 1 and "1.0" match a decimal 1: numbers by value (BigDecimal("1").to_s is "1.0").
    def same?(option, value)
      return option.to_s == value.to_s unless value.is_a?(Numeric)

      number = BigDecimal(option.to_s, exception: false)
      !number.nil? && number == value
    end
  end
end
