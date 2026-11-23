module ApplicationImport
  module Readers
    class EncodingGate
      # Writes decoded UTF-8 text to the tempfile: rejects NUL, tracks lines and
      # whether there is any content, and optionally turns CRLF / lone CR into LF
      # (a CR at the end of a chunk waits for the next one).
      class Output
        class NulError < StandardError; end

        attr_reader :lines

        def initialize(file, normalize_newlines)
          @file = file
          @normalize = normalize_newlines
          @pending_cr = ""
          @lines = 0
          @content = false
          @finishing = false
        end

        def write(text)
          text = normalize(text) if @normalize
          raise NulError if text.include?("\0")

          @lines += text.count("\n")
          @content ||= text.match?(/\S/)
          @file.write(text)
        end

        def finish
          @finishing = true
          write("") unless @pending_cr.empty?
          @file.flush
        end

        def content?
          @content
        end

        private

        def normalize(text)
          text = @pending_cr + text
          @pending_cr = (text.end_with?("\r") && !@finishing) ? "\r" : ""
          text = text.chop unless @pending_cr.empty?
          text.gsub(/\r\n?/, "\n")
        end
      end
    end
  end
end
