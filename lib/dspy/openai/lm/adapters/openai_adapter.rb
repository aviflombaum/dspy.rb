# frozen_string_literal: true

require 'openai'
require_relative '../schema_converter'
require 'dspy/lm/vision_models'
require 'dspy/lm/adapter'

module DSPy
  module OpenAI
    module LM
      module Adapters
        class OpenAIAdapter < DSPy::LM::Adapter
          def initialize(model:, api_key:, structured_outputs: false)
            super(model: model, api_key: api_key)
            validate_api_key!(api_key, 'openai')
            @client = ::OpenAI::Client.new(api_key: api_key)
            @structured_outputs_enabled = structured_outputs
          end

          def chat(messages:, signature: nil, response_format: nil, &block)
            normalized_messages = normalize_messages(messages)

            if contains_files?(normalized_messages)
              return chat_with_file_inputs(
                messages: normalized_messages,
                signature: signature,
                response_format: response_format,
                &block
              )
            end

            # Validate vision support if images are present
            if contains_images?(normalized_messages)
              DSPy::LM::VisionModels.validate_vision_support!('openai', model)
            end

            if contains_media?(normalized_messages)
              normalized_messages = format_multimodal_messages(normalized_messages, 'openai')
            end

            # Handle O1 model restrictions - convert system messages to user messages
            if o1_model?(model)
              normalized_messages = handle_o1_messages(normalized_messages)
            end

            request_params = default_request_params.merge(
              messages: normalized_messages
            )

            # Add temperature based on model capabilities  
            unless o1_model?(model)
              temperature = case model
                            when /^gpt-5/, /^gpt-4o/
                              1.0 # GPT-5 and GPT-4o models only support default temperature of 1.0
                            else
                              0.0 # Near-deterministic for other models (0.0 no longer universally supported)
                            end
              request_params[:temperature] = temperature
            end

            # Add response format if provided by strategy
            if response_format
              request_params[:response_format] = response_format
            elsif @structured_outputs_enabled && signature && supports_structured_outputs?
              # Legacy behavior for backward compatibility
              response_format = DSPy::OpenAI::LM::SchemaConverter.to_openai_format(signature)
              request_params[:response_format] = response_format
            end

            # Add streaming if block provided
            if block_given?
              request_params[:stream] = proc do |chunk, _bytesize|
                block.call(chunk) if chunk.dig("choices", 0, "delta", "content")
              end
            end

            begin
              response = @client.chat.completions.create(**request_params)

              if response.respond_to?(:error) && response.error
                raise DSPy::LM::AdapterError, "OpenAI API error: #{response.error}"
              end

              choice = response.choices.first
              message = choice.message
              content = message.content
              usage = response.usage

              # Handle structured output refusals
              if message.respond_to?(:refusal) && message.refusal
                raise DSPy::LM::AdapterError, "OpenAI refused to generate output: #{message.refusal}"
              end

              # Convert usage data to typed struct
              usage_struct = DSPy::LM::UsageFactory.create('openai', usage)

              # Create typed metadata
              metadata = DSPy::LM::ResponseMetadataFactory.create('openai', {
                model: model,
                response_id: response.id,
                created: response.created,
                structured_output: @structured_outputs_enabled && signature && supports_structured_outputs?,
                system_fingerprint: response.system_fingerprint,
                finish_reason: choice.finish_reason
              })

              DSPy::LM::Response.new(
                content: content,
                usage: usage_struct,
                metadata: metadata
              )
            rescue StandardError => e
              # Check for specific error types and messages
              error_msg = e.message.to_s

              # Try to parse error body if it looks like JSON
              error_body = if error_msg.start_with?('{')
                             JSON.parse(error_msg) rescue nil
                           elsif e.respond_to?(:response) && e.response
                             e.response[:body] rescue nil
                           end

              # Check for specific image-related errors
              if error_msg.include?('image_parse_error') || error_msg.include?('unsupported image')
                raise DSPy::LM::AdapterError, "Image processing failed: #{error_msg}. Ensure your image is a valid PNG, JPEG, GIF, or WebP format and under 5MB."
              elsif error_msg.include?('rate') && error_msg.include?('limit')
                raise DSPy::LM::AdapterError, "OpenAI rate limit exceeded: #{error_msg}. Please wait and try again."
              elsif error_msg.include?('authentication') || error_msg.include?('API key') || error_msg.include?('Unauthorized')
                raise DSPy::LM::AdapterError, "OpenAI authentication failed: #{error_msg}. Check your API key."
              elsif error_body && error_body.dig('error', 'message')
                raise DSPy::LM::AdapterError, "OpenAI API error: #{error_body.dig('error', 'message')}"
              else
                # Generic error handling
                raise DSPy::LM::AdapterError, "OpenAI adapter error: #{e.message}"
              end
            end
          end

          protected

          # Allow subclasses to override request params (add headers, etc)
          def default_request_params
            {
              model: model
            }
          end

          private

          def chat_with_file_inputs(messages:, signature: nil, response_format: nil, &block)
            validate_openai_file_input_support!(messages, streaming: block_given?)

            response = create_file_input_response(
              messages: messages,
              signature: signature,
              response_format: response_format
            )

            build_responses_lm_response(
              response,
              structured_output: responses_structured_output?(response_format, signature)
            )
          rescue DSPy::LM::Error
            raise
          rescue StandardError => e
            handle_openai_responses_error(e)
          end

          def create_file_input_response(messages:, signature: nil, response_format: nil)
            response = @client.responses.create(
              **build_file_input_request_params(
                messages: messages,
                signature: signature,
                response_format: response_format
              )
            )

            if response.respond_to?(:error) && response.error
              raise DSPy::LM::AdapterError, "OpenAI API error: #{response.error}"
            end

            response
          end

          def build_file_input_request_params(messages:, signature: nil, response_format: nil)
            request_params = default_request_params.merge(
              input: to_responses_input(messages)
            )

            temperature = responses_temperature
            request_params[:temperature] = temperature unless temperature.nil?

            text_config = responses_text_config(response_format, signature)
            request_params[:text] = text_config if text_config

            request_params
          end

          def responses_temperature
            return nil if o1_model?(model)

            case model
            when /^gpt-5/, /^gpt-4o/
              1.0
            else
              0.0
            end
          end

          def build_responses_lm_response(response, structured_output:)
            DSPy::LM::Response.new(
              content: openai_responses_content(response),
              usage: DSPy::LM::UsageFactory.create(
                'openai',
                response.respond_to?(:usage) ? response.usage : nil
              ),
              metadata: responses_metadata(response, structured_output: structured_output)
            )
          end

          def responses_metadata(response, structured_output:)
            DSPy::LM::ResponseMetadataFactory.create('openai', {
              model: response.respond_to?(:model) ? response.model.to_s : model,
              response_id: response.respond_to?(:id) ? response.id : nil,
              created: response.respond_to?(:created_at) ? response.created_at&.to_i : nil,
              structured_output: structured_output,
              finish_reason: response.respond_to?(:status) ? response.status : nil
            })
          end

          def responses_structured_output?(response_format, signature)
            !!response_format || (@structured_outputs_enabled && signature && supports_structured_outputs?)
          end

          def handle_openai_responses_error(error)
            error_msg = error.message.to_s
            error_body = extract_openai_error_body(error, error_msg)

            if error_msg.include?('rate') && error_msg.include?('limit')
              raise DSPy::LM::AdapterError, "OpenAI rate limit exceeded: #{error_msg}. Please wait and try again."
            elsif error_msg.include?('authentication') || error_msg.include?('API key') || error_msg.include?('Unauthorized')
              raise DSPy::LM::AdapterError, "OpenAI authentication failed: #{error_msg}. Check your API key."
            elsif error_body && error_body.dig('error', 'message')
              raise DSPy::LM::AdapterError, "OpenAI API error: #{error_body.dig('error', 'message')}"
            else
              raise DSPy::LM::AdapterError, "OpenAI Responses adapter error: #{error.message}"
            end
          end

          def extract_openai_error_body(error, error_msg = error.message.to_s)
            if error_msg.start_with?('{')
              JSON.parse(error_msg) rescue nil
            elsif error.respond_to?(:response) && error.response
              error.response[:body] rescue nil
            end
          end

          def validate_openai_file_input_support!(messages, streaming:)
            unless supports_responses_file_inputs?
              raise DSPy::LM::IncompatibleFileInputFeatureError,
                    "DSPy::FileInput requires an adapter with OpenAI Responses input_file support."
            end

            if streaming
              raise DSPy::LM::IncompatibleFileInputFeatureError,
                    "DSPy::FileInput does not support streaming responses yet. Call without a streaming block."
            end

            if contains_images?(messages) || contains_documents?(messages)
              raise DSPy::LM::IncompatibleFileInputFeatureError,
                    "DSPy::FileInput cannot be mixed with DSPy::Image or DSPy::Document in this release."
            end

            each_file_input(messages) { |file| file.validate_for_provider!('openai') }
          end

          def supports_responses_file_inputs?
            true
          end

          def to_responses_input(messages)
            messages.map do |message|
              content = message[:content]
              formatted_content = if content.is_a?(Array)
                content.map do |item|
                  case item[:type]
                  when 'text'
                    { type: :input_text, text: item[:text].to_s }
                  when 'file'
                    format_file_for_responses(item[:file])
                  else
                    item
                  end
                end
              else
                content.to_s
              end

              {
                role: message[:role].to_s.to_sym,
                content: formatted_content
              }
            end
          end

          def format_file_for_responses(file)
            if file.url
              {
                type: :input_file,
                file_url: file.url,
                filename: file.filename_with_extension
              }
            else
              {
                type: :input_file,
                file_data: file.to_base64,
                filename: file.filename_with_extension
              }
            end
          end

          def responses_text_config(response_format, signature)
            format = response_format
            if format.nil? && @structured_outputs_enabled && signature && supports_structured_outputs?
              format = DSPy::OpenAI::LM::SchemaConverter.to_openai_format(signature)
            end

            responses_format = to_responses_text_format(format)
            responses_format ? { format: responses_format } : nil
          end

          def to_responses_text_format(response_format)
            return nil unless response_format

            type = response_format[:type] || response_format['type']
            case type.to_s
            when 'json_schema'
              json_schema = response_format[:json_schema] || response_format['json_schema'] || {}
              {
                type: :json_schema,
                name: hash_fetch(json_schema, :name),
                strict: hash_fetch(json_schema, :strict),
                schema: hash_fetch(json_schema, :schema)
              }
            when 'json_object'
              { type: :json_object }
            when 'text'
              { type: :text }
            else
              response_format
            end
          end

          def hash_fetch(hash, key)
            return hash[key] if hash.key?(key)

            hash[key.to_s]
          end

          def openai_responses_content(response)
            return response.output_text.to_s if response.respond_to?(:output_text)

            response.output.filter_map do |item|
              next unless item.respond_to?(:type) && item.type == :message
              next unless item.respond_to?(:content)

              item.content.filter_map do |content|
                content.text if content.respond_to?(:type) && content.type == :output_text && content.respond_to?(:text)
              end
            end.join
          end

          def supports_structured_outputs?
            DSPy::OpenAI::LM::SchemaConverter.supports_structured_outputs?(model)
          end

          # Check if model is an O1 reasoning model (includes O1, O3, O4 series)
          def o1_model?(model_name)
            model_name.match?(/^o[134](-.*)?$/)
          end

          # Handle O1 model message restrictions
          def handle_o1_messages(messages)
            messages.map do |msg|
              # Convert system messages to user messages for O1 models
              if msg[:role] == 'system'
                {
                  role: 'user',
                  content: "Instructions: #{msg[:content]}"
                }
              else
                msg
              end
            end
          end
        end
      end
    end
  end
end
