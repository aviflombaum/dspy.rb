# frozen_string_literal: true

require 'base64'
require 'uri'

module DSPy
  class Document
    attr_reader :url, :base64, :data, :path, :content_type, :cache

    SUPPORTED_FORMATS = %w[
      application/pdf
      text/plain
      text/csv
      text/html
      text/markdown
    ].freeze

    MAX_SIZE_BYTES = 32 * 1024 * 1024 # 32MB limit

    # Provider capability registry for document support
    PROVIDER_CAPABILITIES = {
      'anthropic' => {
        sources: %w[url base64 data],
        supported_types: %w[application/pdf text/plain text/csv text/html],
        supports_cache_control: true
      },
      'gemini' => {
        sources: %w[base64 data],
        supported_types: %w[application/pdf text/plain],
        supports_cache_control: false
      },
      'openai' => {
        sources: [],
        supported_types: [],
        supports_cache_control: false
      }
    }.freeze

    def initialize(url: nil, base64: nil, data: nil, path: nil, content_type: nil, cache: false)
      @cache = cache

      validate_input!(url, base64, data, path)

      if url
        raise ArgumentError, "content_type is required when using url" unless content_type
        @url = url
        @content_type = content_type
      elsif base64
        raise ArgumentError, "content_type is required when using base64" unless content_type
        @base64 = base64
        @content_type = content_type
        validate_size!(Base64.decode64(base64).bytesize)
      elsif data
        raise ArgumentError, "content_type is required when using data" unless content_type
        @data = data
        @content_type = content_type
        validate_size!(data.size)
      elsif path
        raise ArgumentError, "content_type is required when using path" unless content_type
        @path = path
        @content_type = content_type
      end

      validate_content_type!
    end

    def to_anthropic_format
      result = if url
        {
          type: 'document',
          source: {
            type: 'url',
            url: @url
          }
        }
      elsif base64
        {
          type: 'document',
          source: {
            type: 'base64',
            media_type: @content_type,
            data: @base64
          }
        }
      elsif data
        {
          type: 'document',
          source: {
            type: 'base64',
            media_type: @content_type,
            data: to_base64
          }
        }
      end

      result[:cache_control] = { type: 'ephemeral' } if @cache && result
      result
    end

    def to_gemini_format
      if url
        raise NotImplementedError, "Gemini does not support document URLs. Use base64 or data instead."
      elsif base64
        {
          inline_data: {
            mime_type: @content_type,
            data: @base64
          }
        }
      elsif data
        {
          inline_data: {
            mime_type: @content_type,
            data: to_base64
          }
        }
      end
    end

    def to_base64
      return @base64 if @base64
      return Base64.strict_encode64(@data.pack('C*')) if @data
      nil
    end

    def validate!
      validate_content_type!

      if @base64
        validate_size!(Base64.decode64(@base64).bytesize)
      elsif @data
        validate_size!(@data.size)
      end
    end

    def validate_for_provider!(provider)
      capabilities = PROVIDER_CAPABILITIES[provider]

      unless capabilities
        raise DSPy::LM::IncompatibleImageFeatureError,
              "Unknown provider '#{provider}'. Supported providers: #{PROVIDER_CAPABILITIES.keys.join(', ')}"
      end

      if capabilities[:sources].empty?
        raise DSPy::LM::IncompatibleImageFeatureError,
              "#{provider} does not support document input."
      end

      current_source = if @url
                         'url'
                       elsif @base64
                         'base64'
                       elsif @data
                         'data'
                       elsif @path
                         'path'
                       end

      unless capabilities[:sources].include?(current_source)
        case provider
        when 'gemini'
          if current_source == 'url'
            raise DSPy::LM::IncompatibleImageFeatureError,
                  "Gemini doesn't support document URLs. Please provide base64 or raw data instead."
          end
        else
          raise DSPy::LM::IncompatibleImageFeatureError,
                "#{provider} doesn't support '#{current_source}' source for documents."
        end
      end
    end

    private

    def validate_input!(url, base64, data, path)
      inputs = [url, base64, data, path].compact

      if inputs.empty?
        raise ArgumentError, "Must provide either url, base64, data, or path"
      elsif inputs.size > 1
        raise ArgumentError, "Only one of url, base64, data, or path can be provided"
      end
    end

    def validate_content_type!
      unless SUPPORTED_FORMATS.include?(@content_type)
        raise ArgumentError, "Unsupported document format: #{@content_type}. Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
      end
    end

    def validate_size!(size_bytes)
      if size_bytes > MAX_SIZE_BYTES
        raise ArgumentError, "Document size exceeds 32MB limit (got #{size_bytes} bytes)"
      end
    end
  end
end
