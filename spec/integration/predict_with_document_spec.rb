# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require_relative '../support/test_documents'

RSpec.describe 'Predict with Document Integration', :vcr do
  let(:anthropic_model) { 'claude-sonnet-4-20250514' }

  describe 'document analysis via raw_chat' do
    it 'analyzes a PDF document via raw_chat', vcr: { cassette_name: 'predict_with_document/raw_chat_anthropic' } do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']

      lm = DSPy::LM.new("anthropic/#{anthropic_model}", api_key: ENV['ANTHROPIC_API_KEY'])

      base64_pdf = TestDocuments.create_base64_pdf(text: "Revenue: $1.2M. Growth: 15%.")
      doc = DSPy::Document.new(base64: base64_pdf, content_type: 'application/pdf')

      response = lm.raw_chat do |messages|
        messages.system("You are a financial analyst. Extract key metrics from documents.")
        messages.user_with_document("What are the key metrics in this document?", doc)
      end

      expect(response).to be_a(String)
      expect(response.length).to be > 0
    end
  end

  describe 'document analysis via Predict' do
    before do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
    end

    let(:document_summary_signature) do
      Class.new(DSPy::Signature) do
        description "Extract a summary from a document"

        input do
          const :document, DSPy::Document, description: "The document to summarize"
          const :focus, String, description: "What to focus on"
        end

        output do
          const :summary, String, description: "Document summary"
        end
      end
    end

    it 'extracts information from a PDF through Predict pipeline',
       vcr: { cassette_name: 'predict_with_document/predict_anthropic' } do
      DSPy.configure do |c|
        c.lm = DSPy::LM.new("anthropic/#{anthropic_model}", api_key: ENV['ANTHROPIC_API_KEY'], structured_outputs: false)
      end

      base64_pdf = TestDocuments.create_base64_pdf(text: "Q4 Revenue: $1.2M. Year-over-year growth: 15%. Active users: 50,000.")
      doc = DSPy::Document.new(base64: base64_pdf, content_type: 'application/pdf')

      predictor = DSPy::Predict.new(document_summary_signature)
      result = predictor.call(document: doc, focus: "financial metrics")

      expect(result.summary).to be_a(String)
      expect(result.summary.length).to be > 0
    end
  end
end
