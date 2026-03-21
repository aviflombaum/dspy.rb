# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Signature, 'attachment schema exclusion' do
  let(:document_signature) do
    Class.new(DSPy::Signature) do
      description "Extract data from document"

      input do
        const :document, DSPy::Document, description: "The document"
        const :company_name, String, description: "Company name"
        const :document_type, String, description: "Type of document"
      end

      output do
        const :answer, String, description: "Extracted data"
      end
    end
  end

  let(:image_signature) do
    Class.new(DSPy::Signature) do
      description "Analyze image"

      input do
        const :image, DSPy::Image, description: "The image"
        const :question, String, description: "Question about the image"
      end

      output do
        const :answer, String, description: "Analysis result"
      end
    end
  end

  let(:text_only_signature) do
    Class.new(DSPy::Signature) do
      description "Simple text"

      input do
        const :question, String, description: "A question"
      end

      output do
        const :answer, String, description: "An answer"
      end
    end
  end

  describe '#input_json_schema' do
    it 'excludes Document fields from the schema' do
      schema = document_signature.input_json_schema
      property_names = schema[:properties].keys

      expect(property_names).to contain_exactly(:company_name, :document_type)
      expect(property_names).not_to include(:document)
      expect(schema[:required]).not_to include('document')
    end

    it 'excludes Image fields from the schema' do
      schema = image_signature.input_json_schema
      property_names = schema[:properties].keys

      expect(property_names).to contain_exactly(:question)
      expect(property_names).not_to include(:image)
      expect(schema[:required]).not_to include('image')
    end

    it 'does not affect text-only signatures' do
      schema = text_only_signature.input_json_schema
      property_names = schema[:properties].keys

      expect(property_names).to contain_exactly(:question)
    end
  end
end
