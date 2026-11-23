module ApplicationImport
  class FileValidator
    attr_reader :definition

    def initialize(definition)
      @definition = definition
    end

    def call(source, result)
      raise NotImplementedError, "#{self.class.name}#call"
    end
  end
end
