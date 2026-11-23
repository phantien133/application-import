module ApplicationImport
  module Readers
    # Streams the source, chunk by chunk, into a UTF-8 tempfile and yields it, or raises
    # a FileError before the caller parses a single row:
    #   - a BOM (UTF-8, UTF-16LE/BE) wins over the configured encoding and is stripped
    #   - otherwise the bytes must be valid in file.encoding (default UTF-8)
    #   - the content is transcoded to UTF-8; unmappable characters are rejected
    #   - NUL bytes are rejected (UTF-16 without BOM, or a binary file)
    #   - content that is empty or whitespace only is rejected
    #   - with normalize_newlines, CRLF and lone CR become LF (mixed line endings)
    # Memory stays at one chunk; the tempfile is removed when the block returns.
    class EncodingGate
      include Logging

      CHUNK_SIZE = 64 * 1024
      BOMS = {
        "\xEF\xBB\xBF".b => Encoding::UTF_8,
        "\xFF\xFE".b => Encoding::UTF_16LE,
        "\xFE\xFF".b => Encoding::UTF_16BE
      }.freeze

      # io: the UTF-8 content (rewound); encoding: the source encoding used; bom: BOM found.
      Text = Data.define(:io, :encoding, :bom)

      attr_reader :definition

      def initialize(definition, logger: ApplicationImport.logger, normalize_newlines: false, chunk_size: CHUNK_SIZE)
        @definition = definition
        @logger = logger
        @normalize_newlines = normalize_newlines
        @chunk_size = chunk_size
      end

      def normalize_newlines?
        @normalize_newlines
      end

      # Yields a Text whose io holds the checked UTF-8 content; returns the block value.
      def call(source)
        Tempfile.create([ "application_import", ".txt" ], binmode: true) do |file|
          encoding, bom = source.open { |input| transcode(input, file) }
          file.rewind
          file.set_encoding(Encoding::UTF_8)
          yield Text.new(io: file, encoding:, bom:)
        end
      end

      private

      def transcode(input, file)
        head = read_chunk(input)
        bom, encoding = detect_bom(head)
        raise invalid("#{encoding} needs a BOM to be read", encoding) if encoding.dummy?

        write(file, encoding, head.byteslice((bom&.bytesize || 0)..), input)
        [ encoding, !bom.nil? ]
      end

      def write(file, encoding, head, input)
        output = Output.new(file, normalize_newlines?)
        pump(Decoder.for(encoding), output, head, input)
        raise Errors::FileError.new("file is empty", code: :empty_file) unless output.content?
      rescue Output::NulError
        raise invalid("file contains NUL bytes (UTF-16 without BOM or a binary file?)", encoding)
      end

      def pump(decoder, output, chunk, input)
        loop do
          output.write(decoder.decode(chunk))
          chunk = read_chunk(input)
          break if chunk.empty?
        end
        output.write(decoder.finish)
        output.finish
      rescue Decoder::Invalid => e
        raise decode_error(e, output, decoder.encoding)
      end

      def read_chunk(input)
        input.read(@chunk_size).to_s.b
      end

      def detect_bom(bytes)
        configured = Encoding.find(definition.file[:encoding] || Constants::DEFAULT_ENCODING)
        bom, encoding = BOMS.find { |mark, _| bytes.start_with?(mark) }
        return [ nil, configured ] unless bom

        warn("file has a #{encoding} BOM, ignoring the configured encoding #{configured}") if encoding != configured
        [ bom, encoding ]
      end

      def decode_error(error, output, encoding)
        line = output.lines + error.prefix.count("\n") + 1
        reason = error.undefined? ? "cannot be converted from #{encoding} to UTF-8" : "is not valid #{encoding}"
        invalid("file #{reason} (first invalid byte on line #{line})", encoding)
      end

      def invalid(message, encoding)
        warn("rejected: #{message}")
        Errors::FileError.new("#{message} [encoding: #{encoding}]", code: :invalid_encoding)
      end
    end
  end
end
