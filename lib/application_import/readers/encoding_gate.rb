module ApplicationImport
  module Readers
    # Reads the whole source and returns its content as valid UTF-8, or raises a
    # FileError before any row is parsed:
    #   - a BOM (UTF-8, UTF-16LE/BE) wins over the configured encoding and is stripped
    #   - otherwise the bytes must be valid in file.encoding (default UTF-8)
    #   - the content is transcoded to UTF-8; unmappable characters are rejected
    #   - NUL bytes are rejected (UTF-16 without BOM, or a binary file)
    #   - content that is empty or whitespace only is rejected
    # The file is held in memory once; bound it with file.max_size.
    class EncodingGate
      include Logging

      BOMS = {
        "\xEF\xBB\xBF".b => Encoding::UTF_8,
        "\xFF\xFE".b => Encoding::UTF_16LE,
        "\xFE\xFF".b => Encoding::UTF_16BE
      }.freeze

      Text = Data.define(:content, :encoding, :bom)

      attr_reader :definition

      def initialize(definition, logger: ApplicationImport.logger)
        @definition = definition
        @logger = logger
      end

      def call(source)
        bytes = source.open(&:read).to_s.b
        bom, encoding = detect_bom(bytes)
        text = bytes.byteslice((bom&.bytesize || 0)..).force_encoding(encoding)
        content = to_utf8(text)
        raise file_error("file is empty", :empty_file) if content.strip.empty?

        Text.new(content:, encoding:, bom: !bom.nil?)
      end

      private

      def configured_encoding
        Encoding.find(definition.file[:encoding] || Constants::DEFAULT_ENCODING)
      end

      def detect_bom(bytes)
        bom, encoding = BOMS.find { |mark, _| bytes.start_with?(mark) }
        return [ nil, configured_encoding ] unless bom

        if encoding != configured_encoding
          warn("file has a #{encoding} BOM, ignoring the configured encoding #{configured_encoding}")
        end
        [ bom, encoding ]
      end

      def to_utf8(text)
        encoding = text.encoding
        raise invalid("#{encoding} needs a BOM to be read", encoding) if encoding.dummy?
        raise invalid("file is not valid #{encoding}#{line_hint(text)}", encoding) unless text.valid_encoding?

        content = (encoding == Encoding::UTF_8) ? text : text.encode(Encoding::UTF_8)
        raise invalid("file contains NUL bytes (UTF-16 without BOM or a binary file?)", encoding) if content.include?("\0")

        content
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
        raise invalid("file cannot be converted from #{encoding} to UTF-8: #{e.message}", encoding)
      end

      def line_hint(text)
        return "" unless text.encoding.ascii_compatible?

        line = text.each_line.with_index(1).find { |content, _| !content.valid_encoding? }&.last
        line ? " (first invalid byte on line #{line})" : ""
      end

      def invalid(message, encoding)
        warn("rejected: #{message}")
        file_error("#{message} [encoding: #{encoding}]", :invalid_encoding)
      end

      def file_error(message, code)
        Errors::FileError.new(message, code:)
      end
    end
  end
end
