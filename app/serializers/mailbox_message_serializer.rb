class MailboxMessageSerializer
  include ApplicationSerializer
  transform_keys :snake

  typelize to: "string[]", text_body: :string, html_body: :string
  hash_attributes :to, :text_body, :html_body
end
