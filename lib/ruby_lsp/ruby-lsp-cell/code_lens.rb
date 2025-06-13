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

        @path = T.let(uri.to_standardized_path, String)
        @class_name = T.let("", String)
        @pattern = T.let("_cell", String)
        @default_view_filename = T.let(default_view_filename, String)
        @in_cell_class = T.let(false, T::Boolean)
        dispatcher.register(self, :on_class_node_enter, :on_class_node_leave, :on_def_node_enter)
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        class_name = node.constant_path.slice
        return unless class_name.end_with?("Cell")
        return unless @global_state.index.linearized_ancestors_of(class_name).include?("Cell::ViewModel")

        @in_cell_class = true
        add_default_goto_code_lens(node)
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_leave(node)
        @in_cell_class = false
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        return unless @in_cell_class
        return unless contains_render_call?(node.body)

        add_function_goto_code_lens(node, node.name.to_s)
      end

      private

      sig { params(node: Prism::Node).void }
      def add_default_goto_code_lens(node)
        erb_filename = remove_last_pattern_in_string @default_view_filename, ".erb"
        uri = compute_erb_view_path @default_view_filename

        create_go_to_file_code_lens(node, erb_filename, uri)
      end

      sig { params(node: T.nilable(Prism::Node)).returns(T::Boolean) }
      def contains_render_call?(node)
        return false if node.nil?

        if node.is_a?(Prism::CallNode)
          return true if node.receiver.nil? && node.name == :render
        end

        node.child_nodes.any? { |child| contains_render_call?(child) }
      end

      sig { params(node: Prism::Node, name: String).void }
      def add_function_goto_code_lens(node, name)
        uri = compute_erb_view_path("#{name}.erb")
        create_go_to_file_code_lens(node, name, uri)
      end

      sig { params(string: String, pattern: String).returns(String) }
      def remove_last_pattern_in_string(string, pattern)
        string.sub(/#{pattern}$/, "")
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

      sig { params(node: Prism::Node, name: String, uri: String).void }
      def create_go_to_file_code_lens(node, name, uri)
        @response_builder << create_code_lens(
          node,
          title: "Go to #{name}",
          command_name: "rubyLsp.openFile",
          arguments: [[uri]],
          data: { type: "file" },
        )
      end
    end
  end
end
