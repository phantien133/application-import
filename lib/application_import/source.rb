module ApplicationImport
  # Uniform read access to an import file, whatever form it arrives in:
  # a path (String/Pathname), an uploaded file (responds to #tempfile and
  # #original_filename) or any readable IO (File, Tempfile, StringIO).
  Source = Data.define(:filename, :path, :io) do
    class << self
      def build(file, filename: nil)
        case file
        when Source then file
        when String, Pathname then from_path(Pathname(file), filename)
        else uploaded?(file) ? from_upload(file, filename) : from_io(file, filename)
        end
      end

      private

      def uploaded?(file)
        file.respond_to?(:tempfile) && file.respond_to?(:original_filename)
      end

      def from_path(path, filename)
        raise ArgumentError, "import file not found: #{path}" unless path.file?

        new(filename: filename || path.basename.to_s, path: path.to_s, io: nil)
      end

      def seekable?(file)
        return false unless file.respond_to?(:rewind) && file.respond_to?(:size)
        return true unless file.is_a?(IO)

        file.stat.file?
      rescue IOError, SystemCallError
        false
      end

      def from_upload(file, filename)
        from_path(Pathname(file.tempfile.path), filename || file.original_filename)
      end

      # The file is read twice (size check, then reading): pipes and sockets cannot be.
      def from_io(file, filename)
        raise ArgumentError, "unsupported import file: #{file.class}" unless file.respond_to?(:read)
        raise ArgumentError, "import file must be seekable (a file or StringIO), got #{file.class}" unless seekable?(file)

        path = file.respond_to?(:path) ? file.path : nil
        name = filename || (path && File.basename(path))
        raise ArgumentError, "filename: is required for #{file.class}" if name.blank?

        new(filename: name, path:, io: file)
      end
    end

    def initialize(filename:, path: nil, io: nil)
      raise ArgumentError, "path or io is required" if path.nil? && io.nil?

      super(filename: filename.to_s, path: path&.to_s, io:)
    end

    # NUL bytes (rejected by FileChecker as invalid_name) are ignored here.
    def extension
      File.extname(filename.delete("\0")).delete_prefix(".").downcase
    end

    def size
      io ? io.size : File.size(path)
    end

    # Yields a binary IO positioned at the start. Files opened from a path are closed afterwards;
    # a caller-supplied IO is rewound and left open.
    def open(&)
      return File.open(path, "rb", &) unless io

      io.rewind
      yield io
    end
  end
end
