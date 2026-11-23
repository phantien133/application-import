module ApplicationImport
  module Readers
    class EncodingGate
      # Decodes byte chunks of a source encoding into UTF-8 text, keeping multi-byte
      # characters split across chunks intact. Raises Invalid with the text decoded
      # before the bad byte.
      class Decoder
        class Invalid < StandardError
          attr_reader :prefix

          def initialize(prefix, undefined: false)
            super("invalid byte sequence")
            @prefix = prefix
            @undefined = undefined
          end

          def undefined?
            @undefined
          end
        end

        attr_reader :encoding

        class << self
          def for(encoding)
            (encoding == Encoding::UTF_8) ? Utf8.new(encoding) : Converter.new(encoding)
          end
        end

        def initialize(encoding)
          @encoding = encoding
        end

        # UTF-8 in, UTF-8 out: validate, carrying an incomplete trailing sequence over.
        class Utf8 < Decoder
          def initialize(encoding)
            super
            @carry = "".b
          end

          def decode(bytes)
            buffer = @carry + bytes
            @carry = incomplete_tail(buffer)
            valid(buffer.byteslice(0, buffer.bytesize - @carry.bytesize))
          end

          def finish
            valid(@carry.tap { @carry = "".b })
          end

          private

          def valid(bytes)
            text = bytes.force_encoding(Encoding::UTF_8)
            return text if text.valid_encoding?

            raise Invalid, text.each_char.take_while(&:valid_encoding?).join
          end

          # Bytes at the end that start a character not complete yet (at most 3).
          def incomplete_tail(buffer)
            (1..[ 3, buffer.bytesize ].min).each do |back|
              byte = buffer.getbyte(-back)
              next if byte & 0xC0 == 0x80 # continuation byte

              return (sequence_length(byte) > back) ? buffer.byteslice(-back, back) : "".b
            end
            "".b
          end

          def sequence_length(lead)
            if lead >= 0xF0 then 4
            elsif lead >= 0xE0 then 3
            elsif lead >= 0xC0 then 2
            else 1
            end
          end
        end

        # Any other encoding: Encoding::Converter with partial input.
        class Converter < Decoder
          ERRORS = %i[ invalid_byte_sequence undefined_conversion incomplete_input ].freeze

          def initialize(encoding)
            super
            @converter = Encoding::Converter.new(encoding, Encoding::UTF_8)
          end

          def decode(bytes)
            convert(bytes.dup, Encoding::Converter::PARTIAL_INPUT)
          end

          def finish
            convert(+"", 0)
          end

          private

          def convert(source, flags)
            output = +""
            result = @converter.primitive_convert(source, output, nil, nil, flags)
            output.force_encoding(Encoding::UTF_8)
            raise Invalid.new(output, undefined: result == :undefined_conversion) if ERRORS.include?(result)

            output
          end
        end
      end
    end
  end
end
