module ApplicationImport
  Column = Data.define(:key, :headers, :type, :options) do
    def header
      headers.first
    end

    def header_patterns
      options[:header_patterns] || []
    end

    def required?
      options[:required] == true
    end
  end
end
