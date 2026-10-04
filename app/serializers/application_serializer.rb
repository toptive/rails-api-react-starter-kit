module ApplicationSerializer
  extend ActiveSupport::Concern

  included do
    include Alba::Resource
    helper Typelizer::DSL
    transform_keys :lower_camel
  end

  class_methods do
    def literal(values) = values.map(&:inspect).join(" | ")

    def hash_attributes(*names)
      names.each { |name| attribute(name) { |payload| payload.fetch(name) } }
    end
  end
end
