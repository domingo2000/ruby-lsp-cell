# typed: false
# frozen_string_literal: true

require "ruby_lsp/addon"
require "ruby_lsp/internal"

require_relative "code_lens"
require_relative "../cell/version"

RubyLsp::Addon.depend_on_ruby_lsp!("~> 0.24.0")

module RubyLsp
  module Cell
    #
    # Addon for Ruby LSP Cell Context
    #
    class Addon < ::RubyLsp::Addon
      extend T::Sig

      sig { void }
      def initialize
        super
        @global_state = T.let(nil, T.nilable(RubyLsp::GlobalState))
        @message_queue = T.let(nil, T.nilable(Thread::Queue))
        @settings = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        @enabled = T.let(nil, T.nilable(T::Boolean))
        @default_view_filename = T.let(nil, T.nilable(String))
      end

      sig { params(global_state: RubyLsp::GlobalState, message_queue: Thread::Queue).void }
      def activate(global_state, message_queue)
        return unless are_required_libraries_installed?

        @message_queue = message_queue
        @global_state = global_state
        @settings = @global_state.settings_for_addon(name) || {}
        @enabled = @settings.fetch(:enabled, true)
        @default_view_filename = @settings.fetch(:defaultViewFileName, "show.erb")
      end

      sig { void }
      def deactivate; end

      sig { returns(String) }
      def name
        "Ruby LSP Cell"
      end

      sig do
        params(
          response_builder: ResponseBuilders::CollectionResponseBuilder,
          uri: URI::Generic,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def create_code_lens_listener(response_builder, uri, dispatcher)
        CodeLens.new(
          response_builder,
          uri,
          dispatcher,
          T.must(@global_state),
          enabled: T.must(@enabled),
          default_view_filename: T.must(@default_view_filename),
        )
      end

      sig { returns(String) }
      def version
        RubyLsp::Cell::VERSION
      end

      def are_required_libraries_installed?
        Bundler.definition.specs.any? do |spec|
          spec.name == "cells"
        end
      rescue Bundler::GemNotFound
        false
      end
    end
  end
end
