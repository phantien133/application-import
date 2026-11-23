module ApplicationImport
  module Readers
    # Drops comment-like lines (file.csv.skip_lines) from the text before the CSV parser
    # sees it, line by line as the encoding gate writes it:
    #   - only lines that start a record are tested: a line inside a quoted value
    #     spanning several lines is data (quote_char counted to know it), so `^#` cannot
    #     drop part of a value;
    #   - a skipped line becomes an empty line, so line numbers stay right and its quote
    #     characters (e.g. `# don't "quote`) never reach the parser.
    # The pattern is matched against the line without its line break. Quote tracking
    # assumes RFC 4180 quoting (doubled quotes inside values); with liberal_parsing a
    # stray quote can make it think a value goes on.
    # A line is buffered until its end, up to LIMIT bytes: a longer line is decided on
    # its first LIMIT bytes and the rest passes (or is dropped) unbuffered, so a huge
    # line costs neither memory nor rescans.
    class SkipLines
      LIMIT = 65_536

      def initialize(pattern, quote_char)
        @pattern = pattern
        @quote = quote_char
        @buffer = +""
        @inside = false
        @mode = nil # nil: buffering a line start, :keep / :drop: the rest of a long line
      end

      # Filters the complete lines of `text` (plus what was buffered), keeping the last
      # partial line for the next call. Each byte is looked at once.
      def filter(text)
        out = +""
        start = 0
        while (newline = text.byteindex("\n", start))
          out << line_part(text.byteslice(start..newline), true)
          start = newline + 1
        end
        out << line_part(text.byteslice(start..), false) if start < text.bytesize
        out
      end

      def flush
        rest = (@mode.nil? && !@buffer.empty?) ? process(take_buffer) : ""
        @mode = nil
        rest
      end

      private

      # part: a piece of the current line; ends: it holds the line's end ("\n").
      def line_part(part, ends)
        case @mode
        when :keep then keep(part, ends)
        when :drop
          @mode = nil if ends
          ends ? "\n" : ""
        else buffer(part, ends)
        end
      end

      def keep(part, ends)
        @inside ^= part.count(@quote).odd?
        @mode = nil if ends
        part
      end

      def buffer(part, ends)
        @buffer << part
        return process(take_buffer) if ends
        return "" if @buffer.bytesize <= LIMIT

        decide_early(take_buffer)
      end

      def decide_early(start)
        if !@inside && @pattern.match?(start)
          @mode = :drop
          ""
        else
          @mode = :keep
          keep(start, false)
        end
      end

      def take_buffer
        line = @buffer
        @buffer = +""
        line
      end

      def process(line)
        return line.end_with?("\n") ? "\n" : "" if !@inside && @pattern.match?(line.chomp)

        @inside ^= line.count(@quote).odd?
        line
      end
    end
  end
end
