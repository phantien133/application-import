module ApplicationImport
  # Default file-level checks, driven by the definition's `file` section:
  #   formats      -> :invalid_format when the extension is not listed
  #   name_pattern -> :invalid_name when the filename does not match
  #   max_size     -> :too_large when the file is bigger (bytes)
  # A check whose setting is not configured is skipped with a warning.
  # Every failing check is recorded; the Runner halts on any file error.
  class FileChecker
    include Logging

    CHECKS = %i[ formats name_pattern max_size ].freeze

    attr_reader :definition

    def initialize(definition, logger: ApplicationImport.logger)
      @definition = definition
      @logger = logger
    end

    def call(source, result)
      CHECKS.each { |check| run_check(check, source, result) }
      result
    end

    private

    def run_check(check, source, result)
      rule = definition.file[check]
      return warn("file.#{check} is not configured, skipping the #{check} check") if rule.nil?

      send(:"check_#{check}", rule, source, result)
    end

    def check_formats(formats, source, result)
      format = source.extension
      return if formats.map(&:to_s).include?(format)

      result.add_file_error(:invalid_format,
        "file format #{format.presence || "(none)"} is not allowed, expected one of: #{formats.join(", ")}",
        details: { format:, allowed: formats.map(&:to_s) })
    end

    def check_name_pattern(pattern, source, result)
      return if pattern.match?(source.filename)

      result.add_file_error(:invalid_name, "filename #{source.filename} does not match #{pattern.source}",
        details: { filename: source.filename, pattern: pattern.source })
    end

    def check_max_size(max_size, source, result)
      size = source.size
      return if size <= max_size

      result.add_file_error(:too_large, "file size #{size} bytes exceeds the maximum of #{max_size} bytes",
        details: { size:, max_size: })
    end
  end
end
