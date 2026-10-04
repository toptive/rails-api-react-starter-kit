class User::Input
  def self.validate!(attributes, string_fields:, boolean_fields: [], required: [])
    required.each do |field|
      raise ApiError.bad_request(:bad_request, User.validation_details(field, "validation.required")) unless attributes.key?(field)
    end
    string_fields.each do |field|
      next unless attributes.key?(field)
      next if attributes[field].is_a?(String)

      raise ApiError.bad_request(:bad_request, User.validation_details(field, "validation.cast"))
    end
    boolean_fields.each do |field|
      next unless attributes.key?(field)
      next if [ true, false, "true", "false" ].include?(attributes[field])

      raise ApiError.bad_request(:bad_request, User.validation_details(field, "validation.cast"))
    end
  end
end
