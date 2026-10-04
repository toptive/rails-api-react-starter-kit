class CreateBilling < ActiveRecord::Migration[8.1]
  def change
    rename_table :subscriptions, :billing_subscriptions
    change_table :billing_subscriptions do |t|
      # Existing placeholder rows retain their cancellation/deletion semantics.
      t.string :stripe_customer_id, null: false, default: ""
      t.string :stripe_subscription_id, null: false, default: ""
      t.string :offer_id
      t.string :plan, null: false, default: "free"
      t.datetime :current_period_end
      t.boolean :cancel_at_period_end, null: false, default: false
      t.boolean :paused, null: false, default: false
      t.datetime :renewal_notice_sent_for
    end
    reversible do |direction|
      direction.up do
        execute "UPDATE billing_subscriptions SET stripe_customer_id = 'legacy_' || id, stripe_subscription_id = 'legacy_' || id"
      end
    end
    change_column_default :billing_subscriptions, :stripe_customer_id, from: "", to: nil
    change_column_default :billing_subscriptions, :stripe_subscription_id, from: "", to: nil
    add_index :billing_subscriptions, [ :livemode, :stripe_subscription_id ], unique: true
    create_table :billing_events, id: :uuid do |t|
      t.boolean :livemode, null: false
      t.string :stripe_event_id, null: false
      t.string :type, null: false
      t.string :stripe_subscription_id
      t.uuid :organization_id
      t.datetime :processed_at
      t.string :outcome
      t.datetime :created_at, null: false
    end
    add_index :billing_events, [ :livemode, :stripe_event_id ], unique: true
  end
end
