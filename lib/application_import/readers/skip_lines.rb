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
    class SkipLines
      def initialize(pattern, quote_char)
        @pattern = pattern
        @quote = quote_char
        @buffer = +""
        @inside = false
      end

      # Filters the complete lines of `text` (plus what was buffered), keeping the last
      # partial line for the next call.
      def filter(text)
        @buffer << text
        lines = @buffer.split(/(?<=\n)/)
        @buffer = (lines.last&.end_with?("\n") ? +"" : lines.pop.to_s.dup)
        lines.map { |line| process(line) }.join
      end

      def flush
        rest = @buffer.empty? ? "" : process(@buffer)
        @buffer = +""
        rest
      end

      private

      def process(line)
        return line.end_with?("\n") ? "\n" : "" if !@inside && @pattern.match?(line.chomp)

        @inside ^= line.count(@quote).odd?
        line
      end
    end
  end
end
