# frozen_string_literal: true

require 'base64'
require 'uri'

module DSPy
  class Document
    attr_reader :url, :base64, :data, :content_type

    SUPPORTED_FORMATS = %w[application/pdf].freeze
    MAX_SIZE_BYTES = 32 * 1024 * 1024 # 32MB limit

    PROVIDER_CAPABILITIES = {
      'openai' => {
        sources: %w[base64 data]
      },
      'anthropic' => {
        sources: %w[url base64 data]
      },
      'gemini' => {
        sources: %w[base64 data]
      }
    }.freeze

    def initialize(url: nil, base64: nil, data: nil, content_type: nil)
      validate_input!(url, base64, data)

      if url
        @url = url
        @content_type = content_type || infer_content_type_from_url(url)
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
      end

      validate_content_type!
    end

    def to_openai_format
      if url
        raise NotImplementedError, "URL fetching for OpenAI not yet implemented. Use base64 or data instead."
      elsif base64
        {
          type: 'file',
          file: {
            file_data: "data:#{content_type};base64,#{base64}"
          }
        }
      elsif data
        {
          type: 'file',
          file: {
            file_data: "data:#{content_type};base64,#{to_base64}"
          }
        }
      end
    end

    def to_anthropic_format
      if url
        {
          type: 'document',
          source: {
            type: 'url',
            url: url
          }
        }
      elsif base64
        {
          type: 'document',
          source: {
            type: 'base64',
            media_type: content_type,
            data: base64
          }
        }
      elsif data
        {
          type: 'document',
          source: {
            type: 'base64',
            media_type: content_type,
            data: to_base64
          }
        }
      end
    end

    def to_gemini_format
      if url
        raise NotImplementedError, "URL fetching for Gemini not yet implemented. Use base64 or data instead."
      elsif base64
        {
          inline_data: {
            mime_type: content_type,
            data: base64
          }
        }
      elsif data
        {
          inline_data: {
            mime_type: content_type,
            data: to_base64
          }
        }
      end
    end

    def to_base64
      return base64 if base64
      return Base64.strict_encode64(data.pack('C*')) if data
      nil
    end

    def validate_for_provider!(provider)
      capabilities = PROVIDER_CAPABILITIES[provider]

      unless capabilities
        raise DSPy::LM::IncompatibleDocumentFeatureError,
              "Unknown provider '#{provider}'. Supported providers: #{PROVIDER_CAPABILITIES.keys.join(', ')}"
      end

      current_source = if url
                         'url'
                       elsif base64
                         'base64'
                       elsif data
                         'data'
                       end

      unless capabilities[:sources].include?(current_source)
        case provider
        when 'openai'
          if current_source == 'url'
            raise DSPy::LM::IncompatibleDocumentFeatureError,
                  "OpenAI doesn't support document URLs. Please provide base64 or raw data instead."
          end
        when 'gemini'
          if current_source == 'url'
            raise DSPy::LM::IncompatibleDocumentFeatureError,
                  "Gemini doesn't support document URLs. Please provide base64 or raw data instead."
          end
        end
      end
    end

    private

    def validate_input!(url, base64, data)
      inputs = [url, base64, data].compact

      if inputs.empty?
        raise ArgumentError, "Must provide either url, base64, or data"
      elsif inputs.size > 1
        raise ArgumentError, "Only one of url, base64, or data can be provided"
      end
    end

    def validate_content_type!
      unless SUPPORTED_FORMATS.include?(content_type)
        raise ArgumentError, "Unsupported document format: #{content_type}. Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
      end
    end

    def validate_size!(size_bytes)
      if size_bytes > MAX_SIZE_BYTES
        raise ArgumentError, "Document size exceeds 32MB limit (got #{size_bytes} bytes)"
      end
    end

    def infer_content_type_from_url(url)
      extension = File.extname(URI.parse(url).path).downcase

      case extension
      when '.pdf'
        'application/pdf'
      else
        'application/pdf'
      end
    end
  end
end
