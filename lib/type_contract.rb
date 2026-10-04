# Shared SPA compatibility for Typelizer 0.14's positional helpers and generic envelopes.
module TypeContract
  module Routes
    private

    def write_index(controllers, named)
      path = super
      content = File.read(path)
      exports = "\nexport type { Method, RouteDefinition, RouteOptions } from './runtime'\n"
      File.write(path, content + exports) unless content.include?("export type { Method,")
      path
    end

    def render_template(template, **context)
      return super unless template == "route_controller.erb"

      renderer = ERB.new(File.read(Rails.root.join("lib/templates/route_controller.erb")), trim_mode: "-")
      scope = binding
      context.each { |key, value| scope.local_variable_set(key, value) }
      renderer.result(scope)
    end
  end

  module Serializers
    private

    def write_interface(interface)
      path = super
      if interface.name == "Envelope"
        original = File.read(path)
        content = original.sub("type Envelope =", "type Envelope<T, M = Record<string, unknown>> =")
        File.write(path, content) unless original == content
      end
      path
    end
  end
end
