# frozen_string_literal: true

require_relative 'message'

module DSPy
  class LM
    class MessageBuilder
      extend T::Sig
      
      sig { returns(T::Array[Message]) }
      attr_reader :messages

      def initialize
        @messages = []
      end

      sig { params(content: T.any(String, T.untyped)).returns(MessageBuilder) }
      def system(content)
        @messages << Message.new(
          role: Message::Role::System,
          content: content.to_s
        )
        self
      end

      sig { params(content: T.any(String, T.untyped)).returns(MessageBuilder) }
      def user(content)
        @messages << Message.new(
          role: Message::Role::User,
          content: content.to_s
        )
        self
      end

      sig { params(content: T.any(String, T.untyped)).returns(MessageBuilder) }
      def assistant(content)
        @messages << Message.new(
          role: Message::Role::Assistant,
          content: content.to_s
        )
        self
      end
      
      sig { params(text: String, image: DSPy::Image).returns(MessageBuilder) }
      def user_with_image(text, image)
        content_array = [
          { type: 'text', text: text },
          { type: 'image', image: image }
        ]
        
        @messages << Message.new(
          role: Message::Role::User,
          content: content_array
        )
        self
      end
      
      sig { params(text: String, images: T::Array[DSPy::Image]).returns(MessageBuilder) }
      def user_with_images(text, images)
        content_array = [{ type: 'text', text: text }]
        images.each do |image|
          content_array << { type: 'image', image: image }
        end

        @messages << Message.new(
          role: Message::Role::User,
          content: content_array
        )
        self
      end

      sig { params(text: String, document: DSPy::Document).returns(MessageBuilder) }
      def user_with_document(text, document)
        content_array = [
          { type: 'document', document: document },
          { type: 'text', text: text }
        ]

        @messages << Message.new(
          role: Message::Role::User,
          content: content_array
        )
        self
      end

      sig { params(text: String, documents: T::Array[DSPy::Document]).returns(MessageBuilder) }
      def user_with_documents(text, documents)
        content_array = []
        documents.each do |document|
          content_array << { type: 'document', document: document }
        end
        content_array << { type: 'text', text: text }

        @messages << Message.new(
          role: Message::Role::User,
          content: content_array
        )
        self
      end

      sig { params(text: String, attachments: T::Array[T.any(DSPy::Image, DSPy::Document)]).returns(MessageBuilder) }
      def user_with_attachments(text, attachments)
        content_array = []
        attachments.each do |attachment|
          case attachment
          when DSPy::Document
            content_array << { type: 'document', document: attachment }
          when DSPy::Image
            content_array << { type: 'image', image: attachment }
          end
        end
        content_array << { type: 'text', text: text }

        @messages << Message.new(
          role: Message::Role::User,
          content: content_array
        )
        self
      end

      # For backward compatibility, allow conversion to hash array
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def to_h
        @messages.map(&:to_h)
      end
    end
  end
end