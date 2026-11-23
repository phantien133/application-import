module ApplicationImport
  # Runs one import: validate_file -> open_reader -> read_headers -> process -> verify
  # -> write_rows, then close_reader and handler.after_import whatever happened.
  # The row pipeline (process / verify / write_rows) lives in Runner::Rows.
  class Runner
    include Constants
    include Logging
    include Rows
    include Lifecycle
    include RowMapping

    attr_reader :definition, :source, :context, :handler, :result, :cache

    def initialize(definition, source, context: {}, logger: ApplicationImport.logger)
      @definition = definition
      @source = source
      @logger = logger
      @context = context.dup.freeze
      @handler = definition.handler_class.new(definition, @context)
      @result = Result.new
      @rows_by_line = {}
      @pending_rows = Set.new.compare_by_identity
      @cache = {}
    end

    # definition.reader_class: file.reader, or the built-in reader for file.format.
    def reader
      @reader ||= definition.reader_class.new(definition, source, logger:)
    end

    # Returns the result. Any exception escaping the steps (a bug in custom code, a
    # library or database error, an interrupt) first marks the result failed with an
    # unexpected_error file error, so close_reader, the summary log and
    # handler.after_import all see the real outcome; it is then re-raised.
    def call
      catch(HALT) { run_steps }
      result
    rescue Exception => e # rubocop:disable Lint/RescueException -- recorded, then re-raised
      fail_unexpectedly(e)
      raise
    ensure
      finish
    end

    private

    def run_steps
      step { validate_file }
      step { open_reader }
      step { read_headers }
      step { process }
      step { verify }
      step { write_rows }
    end

    def step
      yield
    rescue Errors::FileError, Errors::RowError, Errors::RowsError => e
      handle_error(e)
    end

    def handle_error(error)
      result.add_exception(error)
      action = error_action(error)
      halt! if action == :abort
      action
    end

    def error_action(error)
      return :abort if error.is_a?(Errors::FileError)

      definition.on_error.action_for(error.code)
    end

    # The file checker's errors halt at once: file validators and handler.validate_file
    # only run on a file that passed the built-in checks (format, name, size).
    def validate_file
      file_checker.call(source, result)
      halt! if result.file_errors?

      run_validators(:file, source)
      handler.validate_file(source, result)
      halt! if result.file_errors?
    end

    def file_checker
      definition.file_checker_class.new(definition, logger:)
    end

    # Headers are checked before the first data row. A reader that knows them up front
    # returns them from #read_headers (mapped now); a streaming reader (CSV) reports them
    # through on_headers when process reaches the header row. Header errors halt.
    def read_headers
      headers = reader.read_headers
      return map_headers(headers) if headers

      reader.on_headers { |streamed| map_headers(streamed) }
    end

    def map_headers(headers)
      @header_map = HeaderMapper.new(definition, logger:).call(headers, result)
      halt! if result.file_errors?
    end

    def run_validators(stage, subject)
      validators(stage).each { |validator| validator.call(subject, result) }
    end

    def mapper
      spec = definition.mapper
      @mapper ||= spec && spec[:class].new(definition, spec[:options], context:, logger:)
    end

    def transformers
      @transformers ||= definition.transformers.map { |spec| spec[:class].new(definition, spec[:options], context:, logger:) }
    end

    def validators(stage)
      @validators ||= definition.validators.transform_values do |specs|
        specs.map { |spec| spec[:class].new(definition, spec[:options], context:, logger:) }
      end
      @validators.fetch(stage)
    end

    def halt!
      result.halt!
      throw HALT
    end
  end
end
