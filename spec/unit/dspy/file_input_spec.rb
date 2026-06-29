# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'tempfile'

RSpec.describe DSPy::FileInput do
  describe '#initialize' do
    it 'creates a file input from a path and infers XLSX metadata' do
      Tempfile.create(['metrics', '.xlsx']) do |file|
        file.binmode
        file.write('xlsx-bytes')
        file.flush

        input = described_class.new(path: file.path)

        expect(input.path).to eq(file.path)
        expect(input.filename).to eq(File.basename(file.path))
        expect(input.content_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        expect(input.byte_size).to eq('xlsx-bytes'.bytesize)
      end
    end

    it 'creates a file input from base64 data' do
      base64_data = Base64.strict_encode64('xlsx-bytes')
      input = described_class.new(
        base64: base64_data,
        content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        filename: 'metrics.xlsx'
      )

      expect(input.base64).to eq(base64_data)
      expect(input.filename).to eq('metrics.xlsx')
      expect(input.content_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    end

    it 'raises for unsupported formats' do
      expect {
        described_class.new(base64: 'abc123', content_type: 'application/pdf', filename: 'report.pdf')
      }.to raise_error(ArgumentError, /Unsupported file format/)
    end
  end

  describe '#filename_with_extension' do
    it 'keeps filenames with supported extensions' do
      input = described_class.new(url: 'https://example.com/metrics.xlsx')

      expect(input.filename_with_extension).to eq('metrics.xlsx')
    end

    it 'derives a filename extension from content type for extensionless URLs' do
      input = described_class.new(
        url: 'https://example.com/download/123',
        content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      )

      expect(input.filename).to eq('123')
      expect(input.filename_with_extension).to eq('123.xlsx')
    end
  end

  describe '#to_base64' do
    it 'encodes inline data' do
      input = described_class.new(
        data: 'xlsx-bytes'.bytes,
        content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        filename: 'metrics.xlsx'
      )

      expect(Base64.decode64(input.to_base64)).to eq('xlsx-bytes')
    end
  end

  describe '#validate_for_provider!' do
    let(:input) do
      described_class.new(
        data: 'xlsx-bytes'.bytes,
        content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        filename: 'metrics.xlsx'
      )
    end

    it 'accepts openai' do
      expect { input.validate_for_provider!('openai') }.not_to raise_error
    end

    it 'rejects non-openai providers' do
      expect {
        input.validate_for_provider!('anthropic')
      }.to raise_error(DSPy::LM::IncompatibleFileInputFeatureError, /OpenAI-backed adapters/)
    end
  end
end
