# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Cell
    class CodeLens
      extend T::Sig
      extend T::Generic

      include ::RubyLsp::Requests::Support::Common

      REQUIRED_LIBRARY = T.let("cells-rails", String)

      ResponseType = type_member { { fixed: T::Array[CodeRay] } }

      sig do
        params(
          response_builder: RubyLsp::ResponseBuilders::CollectionResponseBuilder,
          uri: URI::Generic,
          dispatcher: Prism::Dispatcher,
          global_state: RubyLsp::GlobalState,
          enabled: T::Boolean,
          default_view_filename: String,
        ).void
      end
      def initialize(response_builder, uri, dispatcher, global_state, enabled:, default_view_filename:)
        return unless enabled

        @response_builder = response_builder
        @global_state = global_state
        @uri = T.let(uri, URI::Generic)
        @path = T.let(uri.to_standardized_path, String)
        @class_name = T.let("", String)
        @pattern = T.let("_cell", String)
        @default_view_filename = T.let(default_view_filename, String)
        @in_cell_class = T.let(false, T::Boolean)
        dispatcher.register(self, :on_class_node_enter)
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        class_name = node.constant_path.slice
        return unless class_name.end_with?("Cell")
        return unless @global_state.index.linearized_ancestors_of(class_name).include?("Cell::ViewModel")

        uri_views = find_uri_views(@uri, class_name)

        if uri_views.empty?
          uri_views << compute_erb_view_path(@default_view_filename)
        end

        @response_builder << create_code_lens(
          node,
          title: "Go to view",
          command_name: "rubyLsp.openFile",
          arguments: [uri_views],
          data: { type: "file" },
        )
      end

      private

      sig { params(uri: URI::Generic, class_name: String).returns(T::Array[String]) }
      def find_uri_views(uri, class_name)
        dir = File.dirname(uri.to_standardized_path)
        folder = File.basename(uri.to_standardized_path).sub(/_cell\.rb$/, "")
        path = File.join(dir, folder)
        erb_files = Dir.glob(File.join(path, "*.erb"))
        erb_files.map do |file|
          URI::Generic.from_path(path: file).to_s
        end
      end

      sig { params(name: String).returns(String) }
      def compute_erb_view_path(name)
        escaped_pattern = Regexp.escape(@pattern)
        base_path = @path.sub(/#{escaped_pattern}\.rb$/, "")
        folder = File.basename(base_path)
        path = File.join(File.dirname(base_path), folder, name)
        uri = URI::Generic.from_path(path: path).to_s
        uri
      end

    end
  end
end
