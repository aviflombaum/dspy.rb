# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Document Message Support' do
  describe DSPy::LM::Message do
    describe 'with document content' do
      context 'with multimodal content array containing a document' do
        it 'creates a message with document content' do
          doc = DSPy::Document.new(url: 'https://example.com/report.pdf')
          content_array = [
            { type: 'text', text: 'Summarize this document.' },
            { type: 'document', document: doc }
          ]

          message = described_class.new(
            role: described_class::Role::User,
            content: content_array
          )

          expect(message.content).to eq(content_array)
          expect(message.multimodal?).to be true
        end
      end

      describe '#to_openai_format' do
        it 'formats document content for OpenAI' do
          base64_data = Base64.strict_encode64('fake_pdf_data')
          doc = DSPy::Document.new(base64: base64_data, content_type: 'application/pdf')
          content_array = [
            { type: 'text', text: 'Summarize this document.' },
            { type: 'document', document: doc }
          ]

          message = described_class.new(
            role: described_class::Role::User,
            content: content_array
          )

          result = message.to_openai_format

          expect(result[:role]).to eq('user')
          expect(result[:content]).to be_an(Array)
          expect(result[:content][0]).to eq({ type: 'text', text: 'Summarize this document.' })
          expect(result[:content][1]).to eq({
            type: 'file',
            file: {
              file_data: "data:application/pdf;base64,#{base64_data}"
            }
          })
        end
      end

      describe '#to_anthropic_format' do
        it 'formats document content for Anthropic with URL' do
          url = 'https://example.com/report.pdf'
          doc = DSPy::Document.new(url: url)
          content_array = [
            { type: 'text', text: 'Summarize this document.' },
            { type: 'document', document: doc }
          ]

          message = described_class.new(
            role: described_class::Role::User,
            content: content_array
          )

          result = message.to_anthropic_format

          expect(result[:role]).to eq('user')
          expect(result[:content]).to be_an(Array)
          expect(result[:content][0]).to eq({ type: 'text', text: 'Summarize this document.' })
          expect(result[:content][1]).to eq({
            type: 'document',
            source: {
              type: 'url',
              url: url
            }
          })
        end

        it 'formats document content for Anthropic with base64' do
          base64_data = Base64.strict_encode64('fake_pdf_data')
          doc = DSPy::Document.new(base64: base64_data, content_type: 'application/pdf')
          content_array = [
            { type: 'text', text: 'Summarize this document.' },
            { type: 'document', document: doc }
          ]

          message = described_class.new(
            role: described_class::Role::User,
            content: content_array
          )

          result = message.to_anthropic_format

          expect(result[:role]).to eq('user')
          expect(result[:content][1]).to eq({
            type: 'document',
            source: {
              type: 'base64',
              media_type: 'application/pdf',
              data: base64_data
            }
          })
        end
      end

      describe 'mixed media content' do
        it 'handles messages with both images and documents' do
          image = DSPy::Image.new(base64: 'abc123', content_type: 'image/jpeg')
          doc = DSPy::Document.new(url: 'https://example.com/report.pdf')
          content_array = [
            { type: 'text', text: 'Compare the chart with the report.' },
            { type: 'image', image: image },
            { type: 'document', document: doc }
          ]

          message = described_class.new(
            role: described_class::Role::User,
            content: content_array
          )

          result = message.to_anthropic_format

          expect(result[:content].size).to eq(3)
          expect(result[:content][0][:type]).to eq('text')
          expect(result[:content][1][:type]).to eq('image')
          expect(result[:content][2][:type]).to eq('document')
        end
      end
    end
  end

  describe DSPy::LM::MessageBuilder do
    describe '#user_with_document' do
      it 'builds a multimodal message with a document' do
        builder = described_class.new
        doc = DSPy::Document.new(url: 'https://example.com/report.pdf')

        builder.user_with_document('Summarize this document.', doc)

        messages = builder.messages
        expect(messages.size).to eq(1)
        expect(messages[0].multimodal?).to be true
        expect(messages[0].content.size).to eq(2)
        expect(messages[0].content[0]).to eq({ type: 'text', text: 'Summarize this document.' })
        expect(messages[0].content[1]).to eq({ type: 'document', document: doc })
      end
    end

    describe '#user_with_documents' do
      it 'builds a multimodal message with multiple documents' do
        builder = described_class.new
        doc1 = DSPy::Document.new(url: 'https://example.com/report1.pdf')
        doc2 = DSPy::Document.new(url: 'https://example.com/report2.pdf')

        builder.user_with_documents('Compare these documents.', [doc1, doc2])

        messages = builder.messages
        expect(messages.size).to eq(1)
        expect(messages[0].content.size).to eq(3) # 1 text + 2 documents
      end
    end
  end
end
