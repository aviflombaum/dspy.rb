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
      base64_data = Base64.strict_encode64('a,b,c')
      input = described_class.new(
        base64: base64_data,
        content_type: 'text/csv',
        filename: 'metrics.csv'
      )

      expect(input.base64).to eq(base64_data)
      expect(input.filename).to eq('metrics.csv')
      expect(input.content_type).to eq('text/csv')
    end

    it 'raises for unsupported formats' do
      expect {
        described_class.new(base64: 'abc123', content_type: 'application/pdf', filename: 'report.pdf')
      }.to raise_error(ArgumentError, /Unsupported file format/)
    end
  end

  describe '#to_openai_responses_input_file' do
    it 'returns an OpenAI Responses input_file part for inline files' do
      input = described_class.new(
        data: 'xlsx-bytes'.bytes,
        content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        filename: 'metrics.xlsx'
      )

      expect(input.to_openai_responses_input_file).to eq({
        type: 'input_file',
        filename: 'metrics.xlsx',
        file_data: "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,#{Base64.strict_encode64('xlsx-bytes')}"
      })
    end

    it 'returns an OpenAI Responses input_file part for URLs' do
      input = described_class.new(url: 'https://example.com/metrics.xlsx')

      expect(input.to_openai_responses_input_file).to eq({
        type: 'input_file',
        file_url: 'https://example.com/metrics.xlsx'
      })
    end
  end

  describe '#to_openai_chat_file_part' do
    it 'returns an OpenAI Chat Completions file part for inline files' do
      input = described_class.new(
        data: 'xlsx-bytes'.bytes,
        content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        filename: 'metrics.xlsx'
      )

      expect(input.to_openai_chat_file_part).to eq({
        type: 'file',
        file: {
          filename: 'metrics.xlsx',
          file_data: "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,#{Base64.strict_encode64('xlsx-bytes')}"
        }
      })
    end

    it 'rejects URLs because Chat Completions does not support file URLs' do
      input = described_class.new(url: 'https://example.com/metrics.xlsx')

      expect {
        input.to_openai_chat_file_part
      }.to raise_error(DSPy::LM::IncompatibleDocumentFeatureError, /do not support file URLs/)
    end
  end

  describe '#validate_for_provider!' do
    let(:input) { described_class.new(data: 'a,b,c', content_type: 'text/csv', filename: 'metrics.csv') }

    it 'accepts openai' do
      expect { input.validate_for_provider!('openai') }.not_to raise_error
    end

    it 'rejects non-openai providers' do
      expect {
        input.validate_for_provider!('anthropic')
      }.to raise_error(DSPy::LM::IncompatibleDocumentFeatureError, /OpenAI via RubyLLM/)
    end
  end
end
