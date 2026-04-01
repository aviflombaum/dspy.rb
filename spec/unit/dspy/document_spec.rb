# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe DSPy::Document do
  describe '#initialize' do
    context 'with URL' do
      it 'creates a document from a URL' do
        url = 'https://example.com/report.pdf'
        doc = described_class.new(url: url)

        expect(doc.url).to eq(url)
        expect(doc.base64).to be_nil
        expect(doc.data).to be_nil
        expect(doc.content_type).to eq('application/pdf')
      end

      it 'infers content type from URL extension' do
        expect(described_class.new(url: 'https://example.com/report.pdf').content_type).to eq('application/pdf')
      end

      it 'defaults to application/pdf for unknown extensions' do
        expect(described_class.new(url: 'https://example.com/report').content_type).to eq('application/pdf')
      end
    end

    context 'with base64 data' do
      it 'creates a document from base64 string' do
        base64_data = Base64.strict_encode64('fake_pdf_data')
        doc = described_class.new(base64: base64_data, content_type: 'application/pdf')

        expect(doc.base64).to eq(base64_data)
        expect(doc.url).to be_nil
        expect(doc.data).to be_nil
        expect(doc.content_type).to eq('application/pdf')
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
        doc = described_class.new(data: data, content_type: 'application/pdf')

        expect(doc.data).to eq(data)
        expect(doc.url).to be_nil
        expect(doc.base64).to be_nil
        expect(doc.content_type).to eq('application/pdf')
      end

      it 'requires content_type when using data' do
        data = 'fake_pdf_data'.bytes
        expect {
          described_class.new(data: data)
        }.to raise_error(ArgumentError, /content_type is required/)
      end
    end

    context 'with invalid inputs' do
      it 'raises error when no input provided' do
        expect {
          described_class.new
        }.to raise_error(ArgumentError, /Must provide either url, base64, or data/)
      end

      it 'raises error when multiple inputs provided' do
        expect {
          described_class.new(url: 'https://example.com/report.pdf', base64: 'abc123')
        }.to raise_error(ArgumentError, /Only one of url, base64, or data can be provided/)
      end

      it 'raises error for unsupported content types' do
        expect {
          described_class.new(base64: 'abc123', content_type: 'text/plain')
        }.to raise_error(ArgumentError, /Unsupported document format/)
      end
    end

    context 'with size validation' do
      it 'validates document size limits for base64' do
        large_data = 'x' * (33 * 1024 * 1024)
        large_base64 = Base64.strict_encode64(large_data)

        expect {
          described_class.new(base64: large_base64, content_type: 'application/pdf')
        }.to raise_error(ArgumentError, /Document size exceeds 32MB limit/)
      end

      it 'validates document size limits for byte data' do
        large_data = 'x' * (33 * 1024 * 1024)

        expect {
          described_class.new(data: large_data.bytes, content_type: 'application/pdf')
        }.to raise_error(ArgumentError, /Document size exceeds 32MB limit/)
      end
    end
  end

  describe '#to_openai_format' do
    context 'with base64 data' do
      it 'returns OpenAI file format' do
        base64_data = Base64.strict_encode64('fake_pdf_data')
        doc = described_class.new(base64: base64_data, content_type: 'application/pdf')
        result = doc.to_openai_format

        expect(result).to eq({
          type: 'file',
          file: {
            file_data: "data:application/pdf;base64,#{base64_data}"
          }
        })
      end
    end

    context 'with byte data' do
      it 'converts to base64 and returns file format' do
        data = 'fake_pdf_data'
        doc = described_class.new(data: data.bytes, content_type: 'application/pdf')
        result = doc.to_openai_format

        expected_base64 = Base64.strict_encode64(data)
        expect(result).to eq({
          type: 'file',
          file: {
            file_data: "data:application/pdf;base64,#{expected_base64}"
          }
        })
      end
    end

    context 'with URL' do
      it 'converts URL to base64 format since OpenAI does not support PDF URLs' do
        doc = described_class.new(url: 'https://example.com/report.pdf')

        expect {
          doc.to_openai_format
        }.to raise_error(NotImplementedError, /URL fetching for OpenAI not yet implemented/)
      end
    end
  end

  describe '#to_anthropic_format' do
    context 'with URL' do
      it 'returns Anthropic document URL format' do
        url = 'https://example.com/report.pdf'
        doc = described_class.new(url: url)
        result = doc.to_anthropic_format

        expect(result).to eq({
          type: 'document',
          source: {
            type: 'url',
            url: url
          }
        })
      end
    end

    context 'with base64 data' do
      it 'returns Anthropic document base64 format' do
        base64_data = Base64.strict_encode64('fake_pdf_data')
        doc = described_class.new(base64: base64_data, content_type: 'application/pdf')
        result = doc.to_anthropic_format

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
        doc = described_class.new(data: data.bytes, content_type: 'application/pdf')
        result = doc.to_anthropic_format

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

  describe '#to_gemini_format' do
    context 'with base64 data' do
      it 'returns Gemini inline_data format' do
        base64_data = Base64.strict_encode64('fake_pdf_data')
        doc = described_class.new(base64: base64_data, content_type: 'application/pdf')
        result = doc.to_gemini_format

        expect(result).to eq({
          inline_data: {
            mime_type: 'application/pdf',
            data: base64_data
          }
        })
      end
    end

    context 'with URL' do
      it 'raises error since Gemini does not support PDF URLs' do
        doc = described_class.new(url: 'https://example.com/report.pdf')

        expect {
          doc.to_gemini_format
        }.to raise_error(NotImplementedError, /URL fetching for Gemini not yet implemented/)
      end
    end
  end

  describe '#to_base64' do
    it 'returns base64 data when available' do
      base64_data = Base64.strict_encode64('fake_pdf_data')
      doc = described_class.new(base64: base64_data, content_type: 'application/pdf')

      expect(doc.to_base64).to eq(base64_data)
    end

    it 'converts byte data to base64' do
      data = 'fake_pdf_data'
      doc = described_class.new(data: data.bytes, content_type: 'application/pdf')

      expect(doc.to_base64).to eq(Base64.strict_encode64(data))
    end

    it 'returns nil for URL-based documents' do
      doc = described_class.new(url: 'https://example.com/report.pdf')

      expect(doc.to_base64).to be_nil
    end
  end

  describe '#validate_for_provider!' do
    it 'accepts base64 for all providers' do
      doc = described_class.new(base64: 'abc123', content_type: 'application/pdf')

      %w[openai anthropic gemini].each do |provider|
        expect { doc.validate_for_provider!(provider) }.not_to raise_error
      end
    end

    it 'accepts URL for anthropic' do
      doc = described_class.new(url: 'https://example.com/report.pdf')

      expect { doc.validate_for_provider!('anthropic') }.not_to raise_error
    end

    it 'rejects URL for openai' do
      doc = described_class.new(url: 'https://example.com/report.pdf')

      expect {
        doc.validate_for_provider!('openai')
      }.to raise_error(DSPy::LM::IncompatibleDocumentFeatureError, /OpenAI doesn't support document URLs/)
    end

    it 'rejects URL for gemini' do
      doc = described_class.new(url: 'https://example.com/report.pdf')

      expect {
        doc.validate_for_provider!('gemini')
      }.to raise_error(DSPy::LM::IncompatibleDocumentFeatureError, /Gemini doesn't support document URLs/)
    end

    it 'raises error for unknown providers' do
      doc = described_class.new(base64: 'abc123', content_type: 'application/pdf')

      expect {
        doc.validate_for_provider!('unknown')
      }.to raise_error(DSPy::LM::IncompatibleDocumentFeatureError, /Unknown provider/)
    end
  end
end
