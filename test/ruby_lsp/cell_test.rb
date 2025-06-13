# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class CellTest < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil ::RubyLsp::Cell::VERSION
    end

    def test_class
      uri = URI("file:///test_cell.rb")
      source = <<~RUBY
        module Cell
          class ViewModel; end
        end

        class TestCell < Cell::ViewModel; end
      RUBY

      with_server(source, uri) do |server, uri|
        server.process_message(
          {
            id: 1,
            method: "textDocument/codeLens",
            params: {
              textDocument: { uri: uri },
              position: { line: 0, character: 0 },
            },
          },
        )
        server.pop_response
        response = server.pop_response.response

        assert_equal 1, response.count

        assert_equal "file", response[0].data[:type]
        assert_equal "Go to show", response[0].command.title
        assert_equal ["file:///test/show.erb"], response[0].command.arguments[0]
        assert_equal 4, response[0].range.start.line
        assert_equal 4, response[0].range.end.line
      end
    end

    def test_no_cell_class
      uri = URI("file:///test_cell.rb")
      source = <<~RUBY
        class noCellClass
          def show
            render
          end
        end
      RUBY

      with_server(source, uri) do |server, uri|
        server.process_message(
          {
            id: 1,
            method: "textDocument/codeLens",
            params: {
              textDocument: { uri: uri },
              position: { line: 0, character: 0 },
            },
          },
        )

        server.pop_response
        response = server.pop_response.response

        assert_equal 0, response.count
      end
    end

    def test_missing_cell_ancestor
      uri = URI("file:///test_cell.rb")
      source = <<~RUBY
        class TestCell
          def show
            render
          end
        end
      RUBY

      with_server(source, uri) do |server, uri|
        server.process_message(
          {
            id: 1,
            method: "textDocument/codeLens",
            params: {
              textDocument: { uri: uri },
              position: { line: 0, character: 0 },
            },
          },
        )

        server.pop_response
        response = server.pop_response.response

        assert_equal 0, response.count
      end
    end

    def test_functions
      uri = URI("file:///test_cell.rb")
      source = <<~RUBY
        module Cell
          class ViewModel; end
        end

        class TestCell < Cell::ViewModel
          def edit
            render
          end

          def show
            render
          end

          def index
            render params
          end

          def destroy; end

          def new
            render_fake
          end
        end
      RUBY

      with_server(source, uri) do |server, uri|
        server.process_message(
          {
            id: 1,
            method: "textDocument/codeLens",
            params: {
              textDocument: { uri: uri },
              position: { line: 0, character: 0 },
            },
          },
        )
        server.pop_response
        response = server.pop_response.response

        assert_equal 4, response.count

        assert_equal "file", response[0].data[:type]
        assert_equal "Go to show", response[0].command.title
        assert_equal ["file:///test/show.erb"], response[0].command.arguments[0]
        assert_equal 4, response[0].range.start.line
        assert_equal 22, response[0].range.end.line

        assert_equal "file", response[1].data[:type]
        assert_equal "Go to edit", response[1].command.title
        assert_equal ["file:///test/edit.erb"], response[1].command.arguments[0]
        assert_equal 5, response[1].range.start.line
        assert_equal 7, response[1].range.end.line

        assert_equal "file", response[2].data[:type]
        assert_equal "Go to show", response[2].command.title
        assert_equal ["file:///test/show.erb"], response[2].command.arguments[0]
        assert_equal 9, response[2].range.start.line
        assert_equal 11, response[2].range.end.line

        assert_equal "file", response[3].data[:type]
        assert_equal "Go to index", response[3].command.title
        assert_equal ["file:///test/index.erb"], response[3].command.arguments[0]
        assert_equal 13, response[3].range.start.line
        assert_equal 15, response[3].range.end.line
      end
    end

    def test_addon_settings
      uri = URI("file:///test_cell.rb")
      source = <<~RUBY
        module Cell
          class ViewModel; end
        end

        class TestCell < Cell::ViewModel; end
      RUBY
      settings = { "Ruby LSP Cell": { defaultViewFileName: "edit.erb" } }

      with_settings_server(source, uri, settings) do |server, uri|
        server.process_message(
          {
            id: 1,
            method: "textDocument/codeLens",
            params: {
              textDocument: { uri: uri },
              position: { line: 0, character: 0 },
            },
          },
        )

        server.pop_response
        response = server.pop_response.response

        assert_equal 1, response.count

        assert_equal "file", response[0].data[:type]
        assert_equal "Go to edit", response[0].command.title
        assert_equal ["file:///test/edit.erb"], response[0].command.arguments[0]
        assert_equal 4, response[0].range.start.line
        assert_equal 4, response[0].range.end.line
      end
    end

    private

    def with_settings_server(source, uri, settings, &block)
      server = RubyLsp::Server.new(test_mode: true)
      initial_options = { initializationOptions: { experimentalFeaturesEnabled: true, addonSettings: settings } }
      server.global_state.apply_options initial_options
      language_id = "ruby"

      server.process_message({
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: uri,
            text: source,
            version: 1,
            languageId: language_id,
          },
        },
      })

      server.global_state.index.index_single(uri, source)
      server.load_addons(include_project_addons: false)

      begin
        block.call(server, uri)
      ensure
        RubyLsp::Addon.addons.each(&:deactivate)
        RubyLsp::Addon.addons.clear
        server.run_shutdown
      end
    end
  end
end
