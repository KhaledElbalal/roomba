class CreateLinearTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :linear_tasks do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.string :task_type, null: false
      t.datetime :synced_at

      t.timestamps
    end

    add_index :linear_tasks, :code, unique: true
  end
end
