module ApplicationImport
  class Runner
    include Constants
    include Logging

    attr_reader :definition, :source, :context, :handler, :result

    def initialize(definition, source, context: {}, logger: ApplicationImport.logger)
      @definition = definition
      @source = source
      @logger = logger
      @context = context.dup.freeze
      @handler = definition.handler_class.new(definition, @context)
      @result = Result.new
    end

    def call
      catch(HALT) { run_steps }
      result
    ensure
      handler.after_import(result)
    end

    private

    def run_steps
      step { validate_file }
      step { process }
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

    def validate_file
      file_checker.call(source, result)
      run_validators(:file, source)
      handler.validate_file(source, result)
      halt! if result.file_errors?
    end

    def file_checker
      definition.file_checker_class.new(definition, logger:)
    end

    def process
      raise NotImplementedError, "#{self.class.name}#process"
    end

    def run_validators(stage, subject)
      validators(stage).each { |validator| validator.call(subject, result) }
    end

    def validators(stage)
      @validators ||= definition.validators.transform_values do |specs|
        specs.map { |spec| spec[:class].new(definition, spec[:options]) }
      end
      @validators.fetch(stage)
    end

    def halt!
      result.halt!
      throw HALT
    end
  end
end
