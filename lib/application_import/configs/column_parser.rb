module ApplicationImport
  module Configs
    class ColumnParser
      include Checks
      include Constants

      KEYS = (%w[ header aliases header_pattern type caster required max_length min_length min max format inclusion
        date_format ] + NumberFormat::KEYS).freeze
      KEY_FORMAT = /\A[a-z_][a-z0-9_]*\z/

      def initialize(config, errors)
        @config = config
        @errors = errors
      end

      def parse
        return add_error("columns", "must define at least one column") || [] if @config.blank?

        columns = mapping(@config, "columns").map { |key, options| parse_column(key.to_s, options) }
        check_duplicate_headers(columns)
        columns
      end

      private

      def parse_column(key, options)
        path = "columns.#{key}"
        add_error(path, "must be snake_case") unless KEY_FORMAT.match?(key)
        options = mapping(options, path)
        check_keys(options, KEYS, path)
        type = one_of(options.fetch("type", DEFAULT_COLUMN_TYPE), COLUMN_TYPES, "#{path}.type")
        Column.new(key: key.to_sym, headers: headers(key, options, path), type: type || :string,
          options: column_options(options, type, path))
      end

      def headers(key, options, path)
        header = options.fetch("header", key)
        add_error("#{path}.header", "must be a non-blank string") unless header.is_a?(String) && header.present?
        aliases = options.key?("aliases") ? names(options["aliases"], "#{path}.aliases") : []
        [ header.to_s.strip, *aliases.map(&:strip) ]
      end

      def column_options(options, type, path)
        parsed = {
          required: boolean(options.fetch("required", false), "#{path}.required"),
          caster: class_name(options["caster"], "#{path}.caster"),
          header_patterns: header_patterns(options["header_pattern"], "#{path}.header_pattern"),
          format: format(options["format"], "#{path}.format"),
          inclusion: inclusion(options["inclusion"], "#{path}.inclusion"),
          date_format: date_format(options["date_format"], type, "#{path}.date_format")
        }
        parsed.merge(typed_options(options, type, path)).compact
      end

      def lengths(options, type, path)
        lengths = %w[ min_length max_length ].filter_map do |key|
          next unless options.key?(key)

          add_error("#{path}.#{key}", "is only allowed on string columns") if type && type != :string
          [ key.to_sym, integer(options[key], "#{path}.#{key}", min: 0) ]
        end.to_h
        check_order(lengths[:min_length], lengths[:max_length], "#{path}.min_length")
        lengths
      end

      def bounds(options, type, path)
        bounds = %w[ min max ].filter_map do |key|
          [ key.to_sym, bound(options[key], type, "#{path}.#{key}") ] if options.key?(key)
        end.to_h
        check_order(bounds[:min], bounds[:max], "#{path}.min")
        bounds
      end

      def bound(value, type, path)
        case type
        when :integer then value.is_a?(Integer) ? value : add_error(path, "must be an integer")
        when :decimal then value.is_a?(Numeric) ? BigDecimal(value.to_s) : add_error(path, "must be a number")
        when :date, :datetime then temporal(value, type, path)
        when nil then nil
        else add_error(path, "is only allowed on integer, decimal, date and datetime columns")
        end
      end

      def temporal(value, type, path)
        (type == :date) ? Date.iso8601(value.to_s) : Time.zone.iso8601(value.to_s)
      rescue ArgumentError
        add_error(path, "must be an ISO 8601 #{type}")
      end

      def check_order(min, max, path)
        add_error(path, "must not be greater than the maximum") if min && max && min > max
      end

      def format(value, path)
        (value.to_s == EMAIL_FORMAT) ? URI::MailTo::EMAIL_REGEXP : regexp(value, path)
      end

      def inclusion(value, path)
        return if value.nil?
        return value if value.is_a?(Array) && value.any?

        add_error(path, "must be a non-empty list")
      end

      def date_format(value, type, path)
        return if value.nil?
        return add_error(path, "is only allowed on date and datetime columns") if type && %i[ date datetime ].exclude?(type)

        (value.is_a?(String) && value.present?) ? value : add_error(path, "must be a strptime format string")
      end

      # One regexp or a list; matched case-insensitively against the stripped header.
      def header_patterns(value, path)
        return if value.nil?

        names(value, path).filter_map do |source|
          Regexp.new(source, Regexp::IGNORECASE, timeout: REGEXP_TIMEOUT)
        rescue RegexpError => e
          add_error(path, "is not a valid regexp: #{e.message}")
        end.presence
      end

      # Options whose meaning depends on the column type.
      def typed_options(options, type, path)
        lengths(options, type, path).merge(bounds(options, type, path), number_format(options, type, path))
      end

      # Separators on integer (thousands only) and decimal columns.
      def number_format(options, type, path)
        format = NumberFormat.parse(options, path, @errors)
        allowed = { integer: %i[ thousands_separator ], decimal: %i[ decimal_separator thousands_separator ] }.fetch(type, [])
        (format.keys - allowed).each do |key|
          add_error("#{path}.#{key}", "is not allowed on #{type || "this"} columns")
        end
        format.slice(*allowed)
      end

      def check_duplicate_headers(columns)
        columns.flat_map(&:headers).group_by { |header| HeaderMapper.normalize(header) }.each do |header, list|
          add_error("columns", "header \"#{header}\" is used more than once") if list.size > 1
        end
      end
    end
  end
end
