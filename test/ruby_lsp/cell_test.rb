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
        assert_equal "Go to view", response[0].command.title
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

    def test_cell_class_with_views
      uri = URI("file:///#{Dir.pwd}/test/fixtures/foo_cell.rb")
      source = <<~RUBY
        module Cell
          class ViewModel; end
        end

        class FooCell < Cell::ViewModel
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

        assert_equal 1, response.count

        assert_equal "file", response[0].data[:type]
        assert_equal "Go to view", response[0].command.title
        assert_equal [
          "file://#{Dir.pwd}/test/fixtures/foo/edit.erb",
          "file://#{Dir.pwd}/test/fixtures/foo/show.erb",
        ],
          response[0].command.arguments[0]
        assert_equal 4, response[0].range.start.line
        assert_equal 5, response[0].range.end.line
      end
    end

    def test_cell_class_with_no_views
      uri = URI("file:///#{Dir.pwd}/test/fixtures/bar_cell.rb")
      source = <<~RUBY
        module Cell
          class ViewModel; end
        end

        class BarCell < Cell::ViewModel; end
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
        assert_equal "Go to view", response[0].command.title
        assert_equal ["file://#{Dir.pwd}/test/fixtures/bar/show.erb"], response[0].command.arguments[0]
        assert_equal 4, response[0].range.start.line
        assert_equal 4, response[0].range.end.line
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
        assert_equal "Go to view", response[0].command.title
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
