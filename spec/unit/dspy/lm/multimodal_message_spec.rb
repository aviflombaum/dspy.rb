# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multimodal Message Support' do
  describe DSPy::LM::Message do
    describe 'with multimodal content' do
      context 'with text only (backward compatibility)' do
        it 'creates a message with string content' do
          message = described_class.new(
            role: described_class::Role::User,
            content: 'What is in this image?'
          )
          
          expect(message.content).to eq('What is in this image?')
          expect(message.to_h[:content]).to eq('What is in this image?')
        end
      end
      
      context 'with multimodal content array' do
        it 'creates a message with content array' do
          content_array = [
            { type: 'text', text: 'What is in this image?' },
            { type: 'image', image: DSPy::Image.new(url: 'https://example.com/image.jpg') }
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
        context 'with text content' do
          it 'returns standard format' do
            message = described_class.new(
              role: described_class::Role::User,
              content: 'Hello'
            )
            
            expect(message.to_openai_format).to eq({
              role: 'user',
              content: 'Hello'
            })
          end
        end
        
        context 'with multimodal content' do
          it 'formats content array for OpenAI' do
            image = DSPy::Image.new(url: 'https://example.com/image.jpg')
            content_array = [
              { type: 'text', text: 'What is in this image?' },
              { type: 'image', image: image }
            ]
            
            message = described_class.new(
              role: described_class::Role::User,
              content: content_array
            )
            
            result = message.to_openai_format
            
            expect(result[:role]).to eq('user')
            expect(result[:content]).to be_an(Array)
            expect(result[:content][0]).to eq({ type: 'text', text: 'What is in this image?' })
            expect(result[:content][1]).to eq({
              type: 'image_url',
              image_url: { url: 'https://example.com/image.jpg' }
            })
          end
        end
      end
      
      describe '#to_anthropic_format' do
        context 'with text content' do
          it 'returns standard format' do
            message = described_class.new(
              role: described_class::Role::User,
              content: 'Hello'
            )
            
            expect(message.to_anthropic_format).to eq({
              role: 'user',
              content: 'Hello'
            })
          end
        end
        
        context 'with multimodal content' do
          it 'formats content array for Anthropic' do
            image = DSPy::Image.new(base64: 'abc123', content_type: 'image/jpeg')
            content_array = [
              { type: 'text', text: 'What is in this image?' },
              { type: 'image', image: image }
            ]
            
            message = described_class.new(
              role: described_class::Role::User,
              content: content_array
            )
            
            result = message.to_anthropic_format
            
            expect(result[:role]).to eq('user')
            expect(result[:content]).to be_an(Array)
            expect(result[:content][0]).to eq({ type: 'text', text: 'What is in this image?' })
            expect(result[:content][1]).to eq({
              type: 'image',
              source: {
                type: 'base64',
                media_type: 'image/jpeg',
                data: 'abc123'
              }
            })
          end
        end
      end
    end

    describe 'with document content' do
      describe '#to_anthropic_format' do
        it 'formats document content array for Anthropic' do
          document = DSPy::Document.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
          content_array = [
            { type: 'document', document: document },
            { type: 'text', text: 'Extract KPIs from this document' }
          ]

          message = described_class.new(
            role: described_class::Role::User,
            content: content_array
          )

          result = message.to_anthropic_format

          expect(result[:role]).to eq('user')
          expect(result[:content]).to be_an(Array)
          expect(result[:content][0]).to eq({
            type: 'document',
            source: {
              type: 'url',
              url: 'https://example.com/doc.pdf'
            }
          })
          expect(result[:content][1]).to eq({ type: 'text', text: 'Extract KPIs from this document' })
        end
      end

      describe '#to_anthropic_format with mixed content' do
        it 'formats documents and images together' do
          document = DSPy::Document.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
          image = DSPy::Image.new(base64: 'abc123', content_type: 'image/jpeg')
          content_array = [
            { type: 'document', document: document },
            { type: 'image', image: image },
            { type: 'text', text: 'Analyze both' }
          ]

          message = described_class.new(
            role: described_class::Role::User,
            content: content_array
          )

          result = message.to_anthropic_format
          expect(result[:content].size).to eq(3)
          expect(result[:content][0][:type]).to eq('document')
          expect(result[:content][1][:type]).to eq('image')
          expect(result[:content][2][:type]).to eq('text')
        end
      end
    end
  end

  describe DSPy::LM::MessageBuilder do
    describe 'multimodal support' do
      it 'supports adding images to user messages' do
        builder = described_class.new
        image = DSPy::Image.new(url: 'https://example.com/image.jpg')

        builder.user_with_image('What is in this image?', image)

        messages = builder.messages
        expect(messages.size).to eq(1)
        expect(messages[0].multimodal?).to be true
        expect(messages[0].content).to be_an(Array)
      end

      it 'supports adding multiple images' do
        builder = described_class.new
        image1 = DSPy::Image.new(url: 'https://example.com/image1.jpg')
        image2 = DSPy::Image.new(url: 'https://example.com/image2.jpg')

        builder.user_with_images('Compare these images', [image1, image2])

        messages = builder.messages
        expect(messages.size).to eq(1)
        expect(messages[0].content.size).to eq(3) # 1 text + 2 images
      end

      it 'supports adding a single document' do
        builder = described_class.new
        document = DSPy::Document.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')

        builder.user_with_document('Extract data from this PDF', document)

        messages = builder.messages
        expect(messages.size).to eq(1)
        expect(messages[0].multimodal?).to be true
        expect(messages[0].content.size).to eq(2) # 1 document + 1 text
        expect(messages[0].content[0][:type]).to eq('document')
        expect(messages[0].content[1][:type]).to eq('text')
      end

      it 'supports adding multiple documents' do
        builder = described_class.new
        doc1 = DSPy::Document.new(url: 'https://example.com/doc1.pdf', content_type: 'application/pdf')
        doc2 = DSPy::Document.new(url: 'https://example.com/doc2.pdf', content_type: 'application/pdf')

        builder.user_with_documents('Compare these documents', [doc1, doc2])

        messages = builder.messages
        expect(messages.size).to eq(1)
        expect(messages[0].content.size).to eq(3) # 2 documents + 1 text
        expect(messages[0].content[0][:type]).to eq('document')
        expect(messages[0].content[1][:type]).to eq('document')
        expect(messages[0].content[2][:type]).to eq('text')
      end

      it 'supports mixed attachments via user_with_attachments' do
        builder = described_class.new
        document = DSPy::Document.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
        image = DSPy::Image.new(url: 'https://example.com/image.jpg')

        builder.user_with_attachments('Analyze these', [document, image])

        messages = builder.messages
        expect(messages.size).to eq(1)
        expect(messages[0].content.size).to eq(3) # 1 document + 1 image + 1 text
        expect(messages[0].content[0][:type]).to eq('document')
        expect(messages[0].content[1][:type]).to eq('image')
        expect(messages[0].content[2][:type]).to eq('text')
      end
    end
  end
end