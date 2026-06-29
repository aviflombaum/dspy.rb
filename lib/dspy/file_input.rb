# frozen_string_literal: true

require 'base64'
require 'uri'

module DSPy
  class FileInput
    attr_reader :path, :url, :base64, :data, :content_type, :filename

    CONTENT_TYPES_BY_EXTENSION = {
      '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.xls' => 'application/vnd.ms-excel'
    }.freeze
    EXTENSIONS_BY_CONTENT_TYPE = CONTENT_TYPES_BY_EXTENSION.invert.freeze
    SUPPORTED_FORMATS = CONTENT_TYPES_BY_EXTENSION.values.uniq.freeze

    def initialize(path: nil, url: nil, base64: nil, data: nil, content_type: nil, filename: nil)
      validate_input!(path, url, base64, data)

      @path = path
      @url = url
      @base64 = base64
      @data = data
      @filename = filename || infer_filename(path: path, url: url, content_type: content_type)
      @content_type = content_type || infer_content_type_from_filename(@filename)

      validate_content_type!
    end

    def validate_for_provider!(provider)
      return true if provider == 'openai'

      raise DSPy::LM::IncompatibleFileInputFeatureError,
            "DSPy::FileInput is currently supported only for OpenAI-backed adapters."
    end

    def to_base64
      return base64 if base64

      Base64.strict_encode64(to_binary)
    end

    def filename_with_extension
      extension = File.extname(filename.to_s).downcase
      return filename if CONTENT_TYPES_BY_EXTENSION.key?(extension)

      inferred_extension = EXTENSIONS_BY_CONTENT_TYPE[content_type]
      return filename unless inferred_extension

      basename = File.basename(filename.to_s, File.extname(filename.to_s))
      basename = 'attachment' if basename.empty?
      "#{basename}#{inferred_extension}"
    end

    def byte_size
      return File.size(path) if path
      return Base64.decode64(base64).bytesize if base64
      return data.bytesize if data.is_a?(String)
      return data.size if data

      nil
    end

    private

    def validate_input!(path, url, base64, data)
      inputs = [path, url, base64, data].compact

      if inputs.empty?
        raise ArgumentError, "Must provide either path, url, base64, or data"
      elsif inputs.size > 1
        raise ArgumentError, "Only one of path, url, base64, or data can be provided"
      end

      raise ArgumentError, "File path does not exist: #{path}" if path && !File.file?(path)
    end

    def validate_content_type!
      return if SUPPORTED_FORMATS.include?(content_type)

      raise ArgumentError,
            "Unsupported file format: #{content_type}. Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
    end

    def infer_filename(path:, url:, content_type:)
      return File.basename(path) if path

      if url
        basename = File.basename(URI.parse(url).path)
        return basename unless basename.empty?
      end

      extension = EXTENSIONS_BY_CONTENT_TYPE.fetch(content_type, '.bin')
      "attachment#{extension}"
    end

    def infer_content_type_from_filename(name)
      extension = File.extname(name.to_s).downcase
      content_type = CONTENT_TYPES_BY_EXTENSION[extension]
      return content_type if content_type

      raise ArgumentError, "Could not infer supported file type from filename: #{name}"
    end

    def to_binary
      return File.binread(path) if path
      return Base64.decode64(base64) if base64
      return data.b if data.is_a?(String)
      return data.pack('C*') if data

      raise ArgumentError, "File input has no binary content"
    end
  end
end
