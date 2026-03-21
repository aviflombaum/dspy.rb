# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM, '#build_messages' do
  # We test the private build_messages method via a minimal mock setup
  # to verify attachment partitioning logic

  let(:lm) do
    # Use a stub adapter that won't make real API calls
    lm = DSPy::LM.allocate
    lm.instance_variable_set(:@provider, 'anthropic')
    lm.instance_variable_set(:@model, 'claude-sonnet-4-20250514')
    lm.instance_variable_set(:@schema_format, :json)
    lm.instance_variable_set(:@data_format, :json)
    lm
  end

  let(:signature_class) do
    Class.new(DSPy::Signature) do
      description "Test signature"

      input do
        const :question, String, description: "A question"
      end

      output do
        const :answer, String, description: "An answer"
      end
    end
  end

  let(:document_signature_class) do
    Class.new(DSPy::Signature) do
      description "Extract data from document"

      input do
        const :document, DSPy::Document, description: "The document"
        const :company_name, String, description: "Company name"
      end

      output do
        const :answer, String, description: "Extracted data"
      end
    end
  end

  let(:image_signature_class) do
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

  def build_messages_for(lm, inference_module, input_values)
    lm.send(:build_messages, inference_module, input_values)
  end

  def make_inference_module(sig_class)
    mod = double('inference_module')
    prompt = DSPy::Prompt.from_signature(sig_class)
    allow(mod).to receive(:signature_class).and_return(sig_class)
    allow(mod).to receive(:prompt).and_return(prompt)
    mod
  end

  context 'with text-only inputs' do
    it 'builds standard text messages' do
      inference_module = make_inference_module(signature_class)
      messages = build_messages_for(lm, inference_module, { question: "What is Ruby?" })

      expect(messages.length).to eq(2) # system + user
      expect(messages[1].content).to be_a(String)
      expect(messages[1].content).to include("What is Ruby?")
    end
  end

  context 'with document inputs' do
    it 'partitions document from text inputs and builds multimodal message' do
      inference_module = make_inference_module(document_signature_class)
      document = DSPy::Document.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')

      messages = build_messages_for(lm, inference_module, {
        document: document,
        company_name: "Acme Corp"
      })

      expect(messages.length).to eq(2) # system + user
      user_message = messages[1]

      # User message should be multimodal
      expect(user_message.multimodal?).to be true

      # Should contain document and text parts
      content = user_message.content
      document_parts = content.select { |item| item[:type] == 'document' }
      text_parts = content.select { |item| item[:type] == 'text' }

      expect(document_parts.length).to eq(1)
      expect(document_parts[0][:document]).to eq(document)
      expect(text_parts.length).to eq(1)

      # Text part should contain company_name but NOT the document object
      expect(text_parts[0][:text]).to include("Acme Corp")
      expect(text_parts[0][:text]).not_to include("DSPy::Document")
      expect(text_parts[0][:text]).not_to include("#<")
    end
  end

  context 'with image inputs' do
    it 'partitions image from text inputs and builds multimodal message' do
      inference_module = make_inference_module(image_signature_class)
      image = DSPy::Image.new(url: 'https://example.com/image.jpg')

      messages = build_messages_for(lm, inference_module, {
        image: image,
        question: "What is in this image?"
      })

      expect(messages.length).to eq(2)
      user_message = messages[1]

      expect(user_message.multimodal?).to be true

      content = user_message.content
      image_parts = content.select { |item| item[:type] == 'image' }
      text_parts = content.select { |item| item[:type] == 'text' }

      expect(image_parts.length).to eq(1)
      expect(image_parts[0][:image]).to eq(image)
      expect(text_parts.length).to eq(1)
      expect(text_parts[0][:text]).to include("What is in this image?")
      expect(text_parts[0][:text]).not_to include("DSPy::Image")
    end
  end
end
