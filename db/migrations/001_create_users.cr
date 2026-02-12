class CreateUsers < Micrate::Migration::V1
  def up
    create_table :users do |t|
      t.string :github_id, unique: true, null: false
      t.string :github_username, null: false
      t.string :name
      t.text :bio
      t.string :location
      t.string :avatar_url
      t.boolean :open_to_work, default: false
      t.string :role, default: "developer" # 'developer' or 'admin'
      t.integer :score, default: 0
      t.integer :projects_count, default: 0
      t.integer :posts_count, default: 0
      t.integer :comments_count, default: 0
      t.integer :stars_count, default: 0
      t.timestamps
    end

    create_index :users, :github_id
    create_index :users, :github_username
    create_index :users, :role
  end

  def down
    drop_table :users
  end
end
