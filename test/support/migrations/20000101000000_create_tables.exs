defmodule PolymorphicEmbed.CreateTables do
  use Ecto.Migration

  def change do
    create table(:reminders) do
      add(:date, :utc_datetime, null: false)
      add(:text, :text, null: false)

      add(:channel, :map)
      add(:contexts, :map)

      timestamps()
    end
  end
end
