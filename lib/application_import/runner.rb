module ApplicationImport
  class Runner
    include Constants

    attr_reader :definition, :source, :context, :handler, :result

    def initialize(definition, source, context: {})
      @definition = definition
      @source = source
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
      definition.file_checker_class.new(definition).call(source, result)
      run_validators(:file, source)
      handler.validate_file(source, result)
      halt! if result.file_errors?
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
