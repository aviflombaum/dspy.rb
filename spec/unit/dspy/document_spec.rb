# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe DSPy::Document do
  describe '#initialize' do
    context 'with URL' do
      it 'creates a document from a URL' do
        url = 'https://example.com/report.pdf'
        document = described_class.new(url: url, content_type: 'application/pdf')

        expect(document.url).to eq(url)
        expect(document.base64).to be_nil
        expect(document.data).to be_nil
        expect(document.content_type).to eq('application/pdf')
      end
    end

    context 'with base64 data' do
      it 'creates a document from base64 string' do
        base64_data = Base64.strict_encode64('fake_pdf_data')
        document = described_class.new(base64: base64_data, content_type: 'application/pdf')

        expect(document.base64).to eq(base64_data)
        expect(document.url).to be_nil
        expect(document.data).to be_nil
        expect(document.content_type).to eq('application/pdf')
      end

      it 'requires content_type when using base64' do
        base64_data = Base64.strict_encode64('fake_pdf_data')
        expect {
          described_class.new(base64: base64_data)
        }.to raise_error(ArgumentError, /content_type is required/)
      end
    end

    context 'with byte data' do
      it 'creates a document from byte array' do
        data = 'fake_pdf_data'.bytes
        document = described_class.new(data: data, content_type: 'application/pdf')

        expect(document.data).to eq(data)
        expect(document.url).to be_nil
        expect(document.base64).to be_nil
        expect(document.content_type).to eq('application/pdf')
      end

      it 'requires content_type when using data' do
        data = 'fake_pdf_data'.bytes
        expect {
          described_class.new(data: data)
        }.to raise_error(ArgumentError, /content_type is required/)
      end
    end

    context 'with file path' do
      it 'creates a document from a file path' do
        path = '/tmp/test_document.pdf'
        document = described_class.new(path: path, content_type: 'application/pdf')

        expect(document.path).to eq(path)
        expect(document.url).to be_nil
        expect(document.base64).to be_nil
        expect(document.data).to be_nil
        expect(document.content_type).to eq('application/pdf')
      end

      it 'requires content_type when using path' do
        expect {
          described_class.new(path: '/tmp/test.pdf')
        }.to raise_error(ArgumentError, /content_type is required/)
      end
    end

    context 'with invalid inputs' do
      it 'raises error when no input provided' do
        expect {
          described_class.new(content_type: 'application/pdf')
        }.to raise_error(ArgumentError, /Must provide either url, base64, data, or path/)
      end

      it 'raises error when multiple inputs provided' do
        expect {
          described_class.new(url: 'https://example.com/doc.pdf', base64: 'abc123', content_type: 'application/pdf')
        }.to raise_error(ArgumentError, /Only one of url, base64, data, or path can be provided/)
      end
    end

    context 'content type validation' do
      it 'accepts valid document content types' do
        valid_types = [
          'application/pdf',
          'text/plain',
          'text/csv',
          'text/html',
          'text/markdown'
        ]

        valid_types.each do |content_type|
          expect {
            described_class.new(url: 'https://example.com/doc', content_type: content_type)
          }.not_to raise_error
        end
      end

      it 'raises error for unsupported content types' do
        expect {
          described_class.new(url: 'https://example.com/doc', content_type: 'image/png')
        }.to raise_error(ArgumentError, /Unsupported document format/)
      end
    end

    context 'cache control' do
      it 'accepts cache option' do
        document = described_class.new(
          url: 'https://example.com/doc.pdf',
          content_type: 'application/pdf',
          cache: true
        )

        expect(document.cache).to eq(true)
      end

      it 'defaults cache to false' do
        document = described_class.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
        expect(document.cache).to eq(false)
      end
    end
  end

  describe '#to_anthropic_format' do
    context 'with URL' do
      it 'returns Anthropic document URL format' do
        document = described_class.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
        result = document.to_anthropic_format

        expect(result).to eq({
          type: 'document',
          source: {
            type: 'url',
            url: 'https://example.com/doc.pdf'
          }
        })
      end

      it 'includes cache_control when cache is enabled' do
        document = described_class.new(
          url: 'https://example.com/doc.pdf',
          content_type: 'application/pdf',
          cache: true
        )
        result = document.to_anthropic_format

        expect(result).to eq({
          type: 'document',
          source: {
            type: 'url',
            url: 'https://example.com/doc.pdf'
          },
          cache_control: { type: 'ephemeral' }
        })
      end
    end

    context 'with base64 data' do
      it 'returns Anthropic document base64 format' do
        base64_data = Base64.strict_encode64('fake_pdf_data')
        document = described_class.new(base64: base64_data, content_type: 'application/pdf')
        result = document.to_anthropic_format

        expect(result).to eq({
          type: 'document',
          source: {
            type: 'base64',
            media_type: 'application/pdf',
            data: base64_data
          }
        })
      end
    end

    context 'with byte data' do
      it 'converts to base64 and returns Anthropic format' do
        data = 'fake_pdf_data'
        document = described_class.new(data: data.bytes, content_type: 'application/pdf')
        result = document.to_anthropic_format

        expected_base64 = Base64.strict_encode64(data)
        expect(result).to eq({
          type: 'document',
          source: {
            type: 'base64',
            media_type: 'application/pdf',
            data: expected_base64
          }
        })
      end
    end
  end

  describe '#to_base64' do
    it 'returns base64 data when available' do
      base64_data = Base64.strict_encode64('fake_pdf_data')
      document = described_class.new(base64: base64_data, content_type: 'application/pdf')

      expect(document.to_base64).to eq(base64_data)
    end

    it 'converts byte data to base64' do
      data = 'fake_pdf_data'
      document = described_class.new(data: data.bytes, content_type: 'application/pdf')

      expect(document.to_base64).to eq(Base64.strict_encode64(data))
    end

    it 'returns nil for URL-based documents' do
      document = described_class.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')

      expect(document.to_base64).to be_nil
    end
  end

  describe '#validate!' do
    it 'validates supported content types' do
      valid_types = ['application/pdf', 'text/plain', 'text/csv', 'text/html', 'text/markdown']

      valid_types.each do |content_type|
        expect {
          described_class.new(base64: 'abc123', content_type: content_type)
        }.not_to raise_error
      end
    end

    it 'raises error for unsupported content types' do
      expect {
        described_class.new(base64: 'abc123', content_type: 'application/zip')
      }.to raise_error(ArgumentError, /Unsupported document format/)
    end

    it 'validates document size limits' do
      # 33MB of data (over 32MB limit)
      large_data = 'x' * (33 * 1024 * 1024)

      expect {
        described_class.new(data: large_data.bytes, content_type: 'application/pdf')
      }.to raise_error(ArgumentError, /Document size exceeds 32MB limit/)
    end
  end

  describe '#validate_for_provider!' do
    it 'validates for anthropic provider' do
      document = described_class.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
      expect { document.validate_for_provider!('anthropic') }.not_to raise_error
    end

    it 'raises error for unknown provider' do
      document = described_class.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
      expect {
        document.validate_for_provider!('unknown_provider')
      }.to raise_error(DSPy::LM::IncompatibleImageFeatureError, /Unknown provider/)
    end

    it 'raises error for providers that do not support documents' do
      document = described_class.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
      expect {
        document.validate_for_provider!('openai')
      }.to raise_error(DSPy::LM::IncompatibleImageFeatureError, /does not support document input/)
    end

    it 'raises error when source type is not supported by provider' do
      document = described_class.new(url: 'https://example.com/doc.pdf', content_type: 'application/pdf')
      expect {
        document.validate_for_provider!('gemini')
      }.to raise_error(DSPy::LM::IncompatibleImageFeatureError, /doesn't support document URLs/)
    end
  end
end
