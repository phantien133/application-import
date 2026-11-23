module ApplicationImport
  ErrorEntry = Data.define(:line, :column, :code, :message, :details) do
    class << self
      def for_file(code, message, details: nil)
        new(code:, message:, details:)
      end
    end

    def initialize(code:, message:, line: nil, column: nil, details: nil)
      super(line:, column: column&.to_s, code:, message:, details:)
    end

    def file_level?
      line.nil?
    end

    def to_h
      super.compact
    end
  end
end
