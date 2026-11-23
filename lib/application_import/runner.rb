module ApplicationImport
  class Runner
    include Constants

    attr_reader :definition, :source, :context, :handler, :result

    def initialize(definition, source, context: {})
      @definition = definition
      @source = source
      @context = context
      @handler = definition.handler_class.new(definition, context)
      @result = Result.new
    end

    def call
      catch(HALT) { run_steps }
      handler.after_import(result)
      result
    end

    private

    def run_steps
      validate_file
      process
    rescue Errors::FileError => e
      result.add_exception(e)
      halt!
    end

    def validate_file
      definition.file_validator_class.new(definition).call(source, result)
      handler.validate_file_meta(source, result)
      halt! if result.file_errors?
    end

    def process
      raise NotImplementedError, "#{self.class.name}#process"
    end

    def halt!
      result.halt!
      throw HALT
    end
  end
end
