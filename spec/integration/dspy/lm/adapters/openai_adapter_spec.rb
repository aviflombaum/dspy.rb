# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe DSPy::OpenAI::LM::Adapters::OpenAIAdapter do
  let(:model) { 'gpt-4' }
  let(:api_key) { 'test-api-key' }
  let(:mock_client) { double('OpenAI::Client') }
  let(:mock_chat) { double('OpenAI::Chat') }
  let(:mock_completions) { double('OpenAI::Completions') }
  let(:mock_responses) { double('OpenAI::Responses') }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:completions).and_return(mock_completions)
    allow(mock_client).to receive(:responses).and_return(mock_responses)
  end

  describe '#initialize' do
    it 'creates OpenAI client with api_key' do
      expect(OpenAI::Client).to receive(:new).with(api_key: api_key)
      
      described_class.new(model: model, api_key: api_key)
    end

    it 'stores model' do
      adapter = described_class.new(model: model, api_key: api_key)
      expect(adapter.model).to eq(model)
    end
  end

  describe '#chat' do
    let(:messages) do
      [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Hello' }
      ]
    end

    let(:spreadsheet_content_type) do
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    end

    let(:inline_file_input) do
      DSPy::FileInput.new(
        data: 'xlsx-bytes'.bytes,
        content_type: spreadsheet_content_type,
        filename: 'metrics.xlsx'
      )
    end

    let(:url_file_input) do
      DSPy::FileInput.new(
        url: 'https://example.com/download/123',
        content_type: spreadsheet_content_type
      )
    end
    
    let(:mock_response) do
      double('OpenAI::Response',
             id: 'resp-123',
             created: 1234567890,
             system_fingerprint: 'fp_123',
             choices: [
               double('Choice', 
                      message: double('Message', 
                                    content: 'Hello back!',
                                    refusal: nil),
                      finish_reason: 'stop')
             ],
             usage: double('Usage', 
                          total_tokens: 25,
                          to_h: { 'total_tokens' => 25 }))
    end

    it 'makes successful API call and returns normalized response' do
      expect(mock_completions).to receive(:create).with(
        model: model,
        messages: messages,
        temperature: 0.0
      ).and_return(mock_response)

      result = described_class.new(model: model, api_key: api_key).chat(messages: messages)

      expect(result).to be_a(DSPy::LM::Response)
      expect(result.content).to eq('Hello back!')
      expect(result.usage).to be_a(DSPy::LM::OpenAIUsage)
      expect(result.usage.total_tokens).to eq(25)
      expect(result.metadata).to be_a(DSPy::LM::OpenAIResponseMetadata)
      expect(result.metadata.provider).to eq('openai')
      expect(result.metadata.model).to eq(model)
      expect(result.metadata.response_id).to eq('resp-123')
      expect(result.metadata.created).to eq(1234567890)
    end

    it 'handles streaming with block' do
      block_called = false
      test_block = proc { |chunk| block_called = true }

      expect(mock_completions).to receive(:create).with(
        hash_including(stream: anything)
      ).and_return(mock_response)

      described_class.new(model: model, api_key: api_key).chat(messages: messages, &test_block)
    end

    it 'handles API errors gracefully' do
      allow(mock_completions).to receive(:create)
        .and_raise(StandardError, 'API Error')

      expect {
        described_class.new(model: model, api_key: api_key).chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /OpenAI adapter error: API Error/)
    end

    let(:mock_responses_usage) do
      double('OpenAI::Responses::ResponseUsage',
             to_h: { input_tokens: 10, output_tokens: 3, total_tokens: 13 })
    end

    let(:mock_responses_response) do
      double('OpenAI::Responses::Response',
             id: 'resp-file-123',
             created_at: 1234567890.0,
             model: model,
             status: :completed,
             output_text: 'Revenue: $1.2M',
             usage: mock_responses_usage,
             error: nil)
    end

    def file_messages_for(file, text: 'Extract revenue metrics.')
      [
        {
          role: 'user',
          content: [
            { type: 'text', text: text },
            { type: 'file', file: file }
          ]
        }
      ]
    end

    it 'sends inline file inputs through OpenAI Responses input_file' do
      file_messages = file_messages_for(inline_file_input)

      expect(mock_completions).not_to receive(:create)
      expect(mock_responses).to receive(:create).with(
        model: model,
        input: [
          {
            role: :user,
            content: [
              { type: :input_text, text: 'Extract revenue metrics.' },
              {
                type: :input_file,
                file_data: Base64.strict_encode64('xlsx-bytes'),
                filename: 'metrics.xlsx'
              }
            ]
          }
        ],
        temperature: 0.0
      ).and_return(mock_responses_response)

      described_class.new(model: model, api_key: api_key).chat(messages: file_messages)
    end

    it 'normalizes OpenAI Responses API responses' do
      allow(mock_responses).to receive(:create).and_return(mock_responses_response)

      result = described_class.new(model: model, api_key: api_key).chat(
        messages: file_messages_for(inline_file_input)
      )

      expect(result).to be_a(DSPy::LM::Response)
      expect(result.content).to eq('Revenue: $1.2M')
      expect(result.usage.input_tokens).to eq(10)
      expect(result.usage.output_tokens).to eq(3)
      expect(result.metadata.response_id).to eq('resp-file-123')
    end

    it 'sends URL file inputs through OpenAI Responses input_file' do
      file_messages = file_messages_for(url_file_input)

      expect(mock_responses).to receive(:create).with(
        model: model,
        input: [
          {
            role: :user,
            content: [
              { type: :input_text, text: 'Extract revenue metrics.' },
              {
                type: :input_file,
                file_url: 'https://example.com/download/123',
                filename: '123.xlsx'
              }
            ]
          }
        ],
        temperature: 0.0
      ).and_return(mock_responses_response)

      described_class.new(model: model, api_key: api_key).chat(messages: file_messages)
    end

    it 'maps structured output response_format to Responses text format' do
      file_messages = file_messages_for(inline_file_input)
      response_format = {
        type: 'json_schema',
        json_schema: {
          name: 'metrics',
          strict: false,
          schema: {
            type: 'object',
            properties: {
              revenue: { type: 'string' }
            }
          }
        }
      }

      expect(mock_responses).to receive(:create).with(
        hash_including(
          text: {
            format: {
              type: :json_schema,
              name: 'metrics',
              strict: false,
              schema: {
                type: 'object',
                properties: {
                  revenue: { type: 'string' }
                }
              }
            }
          }
        )
      ).and_return(mock_responses_response)

      described_class.new(model: model, api_key: api_key).chat(
        messages: file_messages,
        response_format: response_format
      )
    end

    it 'rejects streaming with file inputs for now' do
      file_messages = file_messages_for(inline_file_input)

      expect(mock_responses).not_to receive(:create)
      expect {
        described_class.new(model: model, api_key: api_key).chat(messages: file_messages) { |_| }
      }.to raise_error(
        DSPy::LM::IncompatibleFileInputFeatureError,
        /does not support streaming/
      )
    end
  end

  describe '#normalize_messages' do
    let(:messages) do
      [
        { role: 'system', content: 'System prompt' },
        { role: 'user', content: 'User message' }
      ]
    end

    it 'returns messages as-is for OpenAI format' do
      adapter = described_class.new(model: model, api_key: api_key)
      normalized = adapter.send(:normalize_messages, messages)
      expect(normalized).to eq(messages)
    end
  end
end
