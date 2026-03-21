# frozen_string_literal: true

module DSPy
  class LM
    module DocumentModels
      # Anthropic document-capable models
      ANTHROPIC_DOCUMENT_MODELS = [
        'claude-3-5-sonnet',
        'claude-3-5-haiku',
        'claude-sonnet-4',
        'claude-opus-4',
        'claude-haiku-4'
      ].freeze

      # Gemini document-capable models
      GEMINI_DOCUMENT_MODELS = [
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
        'gemini-2.0-flash',
        'gemini-2.0-flash-lite',
        'gemini-1.5-pro',
        'gemini-1.5-flash',
        'gemini-1.5-flash-8b'
      ].freeze

      def self.supports_documents?(provider, model)
        case provider.to_s.downcase
        when 'anthropic'
          ANTHROPIC_DOCUMENT_MODELS.any? { |m| model.include?(m) }
        when 'gemini'
          GEMINI_DOCUMENT_MODELS.any? { |m| model.include?(m) }
        else
          false
        end
      end

      def self.validate_document_support!(provider, model)
        unless supports_documents?(provider, model)
          if provider.to_s.downcase == 'openai'
            raise ArgumentError, "OpenAI does not support native document input. Consider extracting text from the document first."
          else
            raise ArgumentError, "Model #{model} does not support document input. Document-capable models for #{provider}: #{document_models_for(provider).join(', ')}"
          end
        end
      end

      def self.document_models_for(provider)
        case provider.to_s.downcase
        when 'anthropic'
          ANTHROPIC_DOCUMENT_MODELS
        when 'gemini'
          GEMINI_DOCUMENT_MODELS
        else
          []
        end
      end
    end
  end
end
